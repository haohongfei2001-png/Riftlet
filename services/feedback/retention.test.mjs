import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import receiver from './receiver.mjs';
import {dispatch} from './delivery.mjs';

// Executes actual schema/SQL. D1 scheduling and GitHub remain mocked, not live.
function fixture() {
  const sqlite=new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('./schema.sql',import.meta.url),'utf8'));
  const prepare=(sql,args=[])=>({
    sql,
    bind(...values){return prepare(sql,values);},
    execute(){return {results:sqlite.prepare(sql).all(...args)};},
    async first(){return this.execute().results[0]??null;},
    async all(){return this.execute();},async run(){return this.execute();}
  });
  const DB={prepare,async batch(statements){
    sqlite.exec('BEGIN');try{const results=statements.map(s=>s.execute());sqlite.exec('COMMIT');return results;}
    catch(e){sqlite.exec('ROLLBACK');throw e;}
  }};
  return {sqlite,DB,ACCEPT_ENABLED:'true',IP_HMAC_KEY:'test-key-'.repeat(8),DELIVERY_ENABLED:'false',GITHUB_TOKEN:'test-only',GITHUB_REPOSITORY:'owner/private-feedback'};
}
const token='f'.repeat(64);
const payload=()=>({schema:1,id:crypto.randomUUID(),kind:'problem',text:'synthetic retention test',appVersion:'0.1.0',createdAt:Math.floor(Date.now()/1000)});
function request(p,method='POST') {
  return new Request('https://feedback.invalid/v1/feedback'+(method==='POST'?'':'/'+p.id),{
    method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.42'},
    ...(method==='POST'?{body:JSON.stringify(p)}:{})
  });
}
test('expiry scrubs payload and report IP bucket; never-attempted expired report can be deleted',async()=>{
  const env=fixture(),p=payload();
  assert.equal((await receiver.fetch(request(p),env)).status,202);
  env.sqlite.exec('UPDATE feedback SET expires=0');await dispatch(env);
  const expired=env.sqlite.prepare('SELECT * FROM feedback').get();
  assert.equal(expired.state,'expired');assert.equal(expired.payload,null);assert.equal(expired.ip_bucket,'');assert.equal(expired.day_bucket,'');
  const deletion=await receiver.fetch(request(p,'DELETE'),env);assert.equal((await deletion.json()).state,'deleted');
  const retry=await receiver.fetch(request(p),env);assert.equal((await retry.json()).state,'deleted');
  assert.equal(env.sqlite.prepare('SELECT COUNT(*) n FROM feedback').get().n,1);
});
test('claimed or delivered deletion remains pending and retains its remote obligation',async()=>{
  for(const state of ['attempting','uncertain','delivered']) {
    const env=fixture(),p=payload();await receiver.fetch(request(p),env);
    env.sqlite.prepare('UPDATE feedback SET state=?,issue_number=1,issue_node_id=?').run(state,'SYNTHETIC');
    const r=await receiver.fetch(request(p,'DELETE'),env);assert.equal((await r.json()).state,'deletion_pending');
    const row=env.sqlite.prepare('SELECT * FROM feedback').get();
    assert.equal(row.payload,null);assert.equal(row.ip_bucket,'');assert.equal(row.issue_number,1);
  }
});
test('stored unknown fields are never projected into a private Issue',async(t)=>{
  const env=fixture(),p=payload();await receiver.fetch(request(p),env);
  env.sqlite.prepare('UPDATE feedback SET payload=?').run(JSON.stringify({...p,path:'/Users/synthetic/private'}));
  const old=globalThis.fetch;let posts=0;
  globalThis.fetch=async(url,init={})=>{
    if(init.method==='POST'){posts++;throw new Error('must not post');}
    return Response.json({private:true,full_name:'owner/private-feedback'});
  };
  t.after(()=>{globalThis.fetch=old;});env.DELIVERY_ENABLED='true';await dispatch(env);
  assert.equal(posts,0);assert.equal(env.sqlite.prepare('SELECT state FROM feedback').get().state,'uncertain');
});
test('resolved tombstones expire even with old Issue metadata; pending deletion obligations survive',async()=>{
  const env=fixture();
  const old=Math.floor(Date.now()/1000)-366*86400;
  const cases=[
    ['deleted',1,old,false],['deleted',null,old,false],['expired',null,old,false],
    ['deletion_pending',1,old,true],['deletion_pending',null,old,true],
    ['uncertain',null,old,true],['expired',1,old,true],
    ['deleted',1,Math.floor(Date.now()/1000),true]
  ];
  const ids=[];
  for(const [state,issue,created] of cases){
    const p=payload();await receiver.fetch(request(p),env);ids.push(p.id);
    env.sqlite.prepare("UPDATE feedback SET state=?,issue_number=?,issue_node_id=?,created=?,payload=NULL,day_bucket='',ip_bucket='' WHERE id=?")
      .run(state,issue,issue===null?null:'SYNTHETIC',created,p.id);
  }
  await dispatch(env);
  for(let i=0;i<ids.length;i++){
    const found=env.sqlite.prepare('SELECT id FROM feedback WHERE id=?').get(ids[i]);
    assert.equal(Boolean(found),cases[i][3],`${cases[i][0]} / issue ${cases[i][1]}`);
  }
});

test('DELETE preceding the first POST commit creates a durable capability-bound tombstone',async()=>{
  const env=fixture(),p=payload();
  const batch=env.DB.batch.bind(env.DB);
  let enter,release;
  const entered=new Promise(r=>{enter=r;});
  const parked=new Promise(r=>{release=r;});
  let held=false;
  env.DB.batch=async statements=>{
    if(!held && statements[0].sql.includes('INSERT INTO feedback')){
      held=true;enter();await parked;
    }
    return batch(statements);
  };
  const submitting=receiver.fetch(request(p),env);
  await entered;
  const deleted=await receiver.fetch(request(p,'DELETE'),env);
  assert.equal(deleted.status,202);assert.equal((await deleted.json()).state,'deleted');
  release();const late=await submitting;
  assert.equal(late.status,202);assert.equal((await late.json()).state,'deleted');
  const row=env.sqlite.prepare('SELECT * FROM feedback WHERE id=?').get(p.id);
  assert.equal(row.payload,null);assert.equal(row.payload_hash,'');assert.equal(row.state,'deleted');
  assert.equal(row.issue_number,null);
  assert.equal(env.sqlite.prepare('SELECT SUM(used) n FROM quota').get().n,2);
  const wrong=new Request('https://feedback.invalid/v1/feedback/'+p.id,{method:'DELETE',headers:{Authorization:'Bearer '+'a'.repeat(64)}});
  assert.equal((await receiver.fetch(wrong,env)).status,404);
});
test('unknown-ID deletion is quota-bounded even with new submissions disabled',async()=>{
  const env=fixture();env.ACCEPT_ENABLED='false';env.sqlite.exec('UPDATE limits SET hourly=1');
  const a=payload(),b=payload();
  assert.equal((await receiver.fetch(request(a,'DELETE'),env)).status,202);
  assert.equal((await receiver.fetch(request(a,'DELETE'),env)).status,202);
  assert.equal((await receiver.fetch(request(b,'DELETE'),env)).status,429);
  assert.equal(env.sqlite.prepare('SELECT COUNT(*) n FROM feedback').get().n,1);
});
