import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import receiver from './receiver.mjs';
import {dispatch} from './delivery.mjs';
import {FACTS,validate} from './contract.mjs';

class D1Fixture {
  constructor(){this.db=new DatabaseSync(':memory:');this.db.exec(readFileSync(new URL('./schema.sql',import.meta.url),'utf8'));this.failure=null;}
  prepare(sql){return this.bound(sql,[]);}
  bound(sql,args){const self=this;return {
    sql,args,bind(...values){return self.bound(sql,values);},
    sync(){if(self.failure?.test(sql))throw new Error('injected_storage_failure');const stmt=self.db.prepare(sql);return {success:true,results:stmt.all(...args),meta:{changes:0}};},
    async first(){return this.sync().results[0]??null;},async all(){return this.sync();},async run(){return this.sync();}
  };}
  async batch(items){this.db.exec('BEGIN IMMEDIATE');try{const result=items.map(i=>i.sync());this.db.exec('COMMIT');return result;}catch(e){this.db.exec('ROLLBACK');throw e;}}
}
const token='b'.repeat(64);
function payload(){return {schema:1,id:crypto.randomUUID(),kind:'problem',text:'需要保留的反馈\nnot instructions',appVersion:'0.1.0',createdAt:Math.floor(Date.now()/1000)};}
function environment(){return {DB:new D1Fixture(),ACCEPT_ENABLED:'true',IP_HMAC_KEY:'test-only-'.repeat(8),DELIVERY_ENABLED:'true',GITHUB_TOKEN:'test-only',GITHUB_REPOSITORY:'owner/private-feedback'};}
function req(value,secret=token,method='POST'){return new Request('https://feedback.invalid/v1/feedback'+(method==='POST'?'':'/'+value.id),{method,headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.1'},...(method==='POST'?{body:JSON.stringify(value)}:{})});}
async function stored(env,id){return env.DB.prepare('SELECT * FROM feedback WHERE id=?').bind(id).first();}
function github(t,options={}){
  const old=globalThis.fetch,issues=[];let posts=0;
  globalThis.fetch=async(url,init={})=>{
    if(init.method==='POST'){
      posts++;const p=JSON.parse(init.body);const issue={...p,number:issues.length+1,node_id:'NODE-'+issues.length};issues.push(issue);
      if(options.onPost)await options.onPost(issue);
      if(options.loseResponse)throw new Error('timeout');
      return Response.json(issue,{status:201});
    }
    if(String(url).includes('/issues?'))return Response.json(issues);
    return Response.json({private:options.private!==false,full_name:'owner/private-feedback'});
  };
  t.after(()=>{globalThis.fetch=old;});return {issues,get posts(){return posts;}};
}

test('real SQLite receipt is durable and same report/body/secret is idempotent under overlapping requests',async()=>{
  const env=environment(),p=payload();const replies=await Promise.all(Array.from({length:8},()=>receiver.fetch(req(p),env)));
  assert(replies.every(r=>r.status===202));assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM feedback').get().n,1);
  assert.equal(env.DB.db.prepare('SELECT SUM(used) n FROM quota').get().n,2);
  assert.equal((await replies[0].json()).durable,true);
  assert.equal((await receiver.fetch(req({...p,text:'mutated'}),env)).status,409);
  assert.equal((await receiver.fetch(req(p,'c'.repeat(64)),env)).status,404);
  assert.equal((await stored(env,p.id)).payload,JSON.stringify(validate(p)));
});
test('D1 write failure never acknowledges; exact original request can recover',async()=>{
  const env=environment(),p=payload();env.DB.failure=/INSERT INTO feedback/;
  assert.equal((await receiver.fetch(req(p),env)).status,503);assert.equal(await stored(env,p.id),null);
  env.DB.failure=null;assert.equal((await receiver.fetch(req(p),env)).status,202);
});
test('strict diagnostics and body whitelist reject raw identifiers and secrets; plain feedback excludes diagnostics',async()=>{
  const env=environment();
  for(const extra of [{assetID:'private-id'},{path:'/Users/person/secret'},{diagnostic:{schema:1,coverage:'session-sampled-v1',dropped:0,events:[{fact:'rawError',count:1}]}},{diagnostic:{schema:1,coverage:'session-sampled-v1',dropped:0,events:[],trace:'private'}}]){
    assert.equal((await receiver.fetch(req({...payload(),...extra}),env)).status,422);
  }
  const p=payload();assert.equal((await receiver.fetch(req(p),env)).status,202);
  assert(!JSON.parse((await stored(env,p.id)).payload).diagnostic);
  assert.equal((await receiver.fetch(req({...payload(),text:'a'.repeat(33000)}),env)).status,413);
});
test('SQL quota rejects insertion atomically and duplicate receipts do not consume quota',async()=>{
  const env=environment();env.DB.db.exec('UPDATE limits SET hourly=1');const p=payload();
  assert.equal((await receiver.fetch(req(p),env)).status,202);assert.equal((await receiver.fetch(req(p),env)).status,202);
  const blocked=payload();const r=await receiver.fetch(req(blocked),env);assert.equal(r.status,429);assert.equal(await stored(env,blocked.id),null);
});
test('delivery enforces private destination, durable intent and one issue across overlapping dispatcher calls',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);const gh=github(t);
  await Promise.all([dispatch(env),dispatch(env)]);
  assert.equal(gh.posts,1);assert.equal((await stored(env,p.id)).state,'delivered');
  assert(gh.issues[0].body.includes('    需要保留的反馈'));assert(!gh.issues[0].body.includes(token));
});
test('public repository refuses all content delivery',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);const gh=github(t,{private:false});
  await dispatch(env);assert.equal(gh.posts,0);assert.equal((await stored(env,p.id)).state,'pending');
});
test('lost GitHub response reconciles original issue without repeating POST',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);const gh=github(t,{loseResponse:true});
  await dispatch(env);assert.equal((await stored(env,p.id)).state,'uncertain');
  env.DB.db.exec('UPDATE feedback SET checked_at=0');await dispatch(env);
  assert.equal(gh.posts,1);assert.equal((await stored(env,p.id)).state,'delivered');
});
test('uncertain POST with no observable issue never blind-retries',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);const gh=github(t,{loseResponse:true});
  await dispatch(env);gh.issues.length=0;env.DB.db.exec('UPDATE feedback SET checked_at=0');await dispatch(env);
  assert.equal(gh.posts,1);assert.equal((await stored(env,p.id)).state,'uncertain');
});
test('deletion before input stops delivery; late POST acknowledges deletion_pending, not deletion complete',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);
  let r=await receiver.fetch(req(p,token,'DELETE'),env);assert.equal((await r.json()).state,'deleted');
  const gh=github(t,{onPost:async()=>{await receiver.fetch(req(q,token,'DELETE'),env);}});
  await dispatch(env);assert.equal(gh.posts,0);
  const q=payload();await receiver.fetch(req(q),env);await dispatch(env);
  const after=await stored(env,q.id);assert.equal(gh.posts,1);assert.equal(after.state,'deletion_pending');assert.equal(after.payload,null);assert.equal(after.issue_number,1);
});
test('expired pending text is removed honestly; restore of attempting remains observation-only',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);const gh=github(t);
  env.DB.db.exec('UPDATE feedback SET expires=0');await dispatch(env);
  assert.equal((await stored(env,p.id)).state,'expired');assert.equal((await stored(env,p.id)).payload,null);assert.equal(gh.posts,0);
  const q=payload();await receiver.fetch(req(q),env);env.DB.db.prepare("UPDATE feedback SET state='attempting',attempt_at=0 WHERE id=?").run(q.id);
  await dispatch(env);assert.equal((await stored(env,q.id)).state,'uncertain');assert.equal(gh.posts,0);
});
test('capabilities never transfer; old IDs and switch-off fail closed',async()=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);
  assert.equal((await receiver.fetch(req(p,'a'.repeat(64),'DELETE'),env)).status,404);
  assert.equal((await stored(env,p.id)).state,'pending');
  assert.equal((await receiver.fetch(req({...payload(),createdAt:1}),env)).status,422);
  env.ACCEPT_ENABLED='false';assert.equal((await receiver.fetch(req(payload()),env)).status,503);
  assert.equal((await receiver.fetch(req(p,undefined,'DELETE'),env)).status,202);
  assert.equal((await stored(env,p.id)).state,'deleted');
});
test('Swift and service share exactly the same closed fact vocabulary',()=>{
  const source=readFileSync(new URL('../../Sources/RiftletFeedback/FeedbackModels.swift',import.meta.url),'utf8');
  const section=source.split('public enum FeedbackFact')[1].split('public struct FeedbackEvent')[0];
  const cases=[...section.matchAll(/case ([^\n]+)/g)].flatMap(m=>m[1].split(',').map(x=>x.trim()));
  assert.deepEqual(new Set(cases),FACTS);
});
