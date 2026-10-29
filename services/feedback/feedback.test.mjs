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
test('reconciliation stays within free Worker request budget and leaves later reports eligible',async(t)=>{
  const env=environment();
  for(let i=0;i<10;i++) await receiver.fetch(req(payload()),env);
  env.DB.db.exec("UPDATE feedback SET state='uncertain'");
  const old=globalThis.fetch;let requests=0,posts=0;
  globalThis.fetch=async(url,init={})=>{
    requests++;
    if(init.method==='POST'){posts++;throw new Error('must not post');}
    if(String(url).includes('/issues?')) return Response.json(Array.from({length:100},(_,i)=>({number:i+1,title:'unrelated',body:'unrelated'})));
    return Response.json({private:true,full_name:'owner/private-feedback'});
  };
  t.after(()=>{globalThis.fetch=old;});
  for(const expected of [4,8,10]) {
    requests=0;await dispatch(env);
    assert(requests<=50,`external subrequests: ${requests}`);
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM feedback WHERE checked_at>0').get().n,expected);
  }
  assert.equal(posts,0);assert.equal(env.DB.db.prepare("SELECT COUNT(*) n FROM feedback WHERE state='uncertain'").get().n,10);
});
test('five-minute cron ticks cannot starve a pending report behind unresolved reconciliation scans',async(t)=>{
  const originalNow=Date.now,originalFetch=globalThis.fetch;
  const firstTick=2_000_000_000;let now=firstTick,requests=0;
  Date.now=()=>now*1000;
  t.after(()=>{Date.now=originalNow;globalThis.fetch=originalFetch;});
  const env=environment(),uncertain=[];
  for(let i=0;i<9;i++) {
    const p=payload();uncertain.push(p.id);
    assert.equal((await receiver.fetch(req(p),env)).status,202);
    env.DB.db.prepare("UPDATE feedback SET state='uncertain',created=?,attempt_at=? WHERE id=?")
      .run(firstTick-9+i,firstTick-600,p.id);
  }
  const pending=payload();assert.equal((await receiver.fetch(req(pending),env)).status,202);
  const posts=[];
  globalThis.fetch=async(url,init={})=>{
    requests++;
    if(init.method==='POST') {
      posts.push(JSON.parse(init.body));
      return Response.json({number:700,node_id:'NODE-NEW-PENDING'},{status:201});
    }
    if(String(url).includes('/issues?')) {
      // Every unresolved row consumes its complete ten-page safety scan.
      // None of these unrelated Issues proves absence or permits a new POST.
      return Response.json(Array.from({length:100},(_,i)=>({number:i+1,title:'unrelated',body:'unrelated'})));
    }
    return Response.json({private:true,full_name:'owner/private-feedback'});
  };
  for(let tick=0;tick<8;tick++) {
    // Match the configured five-minute cron exactly. Previously tested calls
    // in a frozen second hid old rows becoming eligible again after two ticks.
    now=firstTick+tick*300;requests=0;await dispatch(env);
    assert(requests<=50,`tick ${tick}: ${requests} external requests`);
    assert.equal(env.DB.db.prepare("SELECT COUNT(*) n FROM feedback WHERE state='uncertain'").get().n,9);
    const visited=env.DB.db.prepare("SELECT COUNT(*) n FROM feedback WHERE state='uncertain' AND checked_at>0").get().n;
    const state=(await stored(env,pending.id)).state;
    t.diagnostic(JSON.stringify({tick,elapsedSeconds:tick*300,externalRequests:requests,uncertainVisited:visited,pendingState:state,posts:posts.length}));
  }
  assert.equal((await stored(env,pending.id)).state,'delivered','a fresh pending report must progress despite unresolved older reports');
  assert.equal((await stored(env,pending.id)).issue_number,700);
  assert.deepEqual(posts.map(p=>p.title),[`Riftlet feedback RF-${pending.id}`]);
  for(const id of uncertain) {
    const record=await stored(env,id);
    assert(record.checked_at>0,'every old uncertain report must eventually be observed');
    assert.equal(record.state,'uncertain');assert.equal(record.issue_number,null);
  }
});

test('deletion before input stops delivery; late POST acknowledges deletion_pending, not deletion complete',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);
  let r=await receiver.fetch(req(p,token,'DELETE'),env);assert.equal((await r.json()).state,'deleted');
  const gh=github(t,{onPost:async()=>{await receiver.fetch(req(q,token,'DELETE'),env);}});
  await dispatch(env);assert.equal(gh.posts,0);
  const q=payload();await receiver.fetch(req(q),env);await dispatch(env);
  const after=await stored(env,q.id);assert.equal(gh.posts,1);assert.equal(after.state,'deletion_pending');assert.equal(after.payload,null);assert.equal(after.issue_number,1);
});
test('deletion after claim but before POST resolves without an imaginary remote deletion obligation',async(t)=>{
  const env=environment(),p=payload();await receiver.fetch(req(p),env);const gh=github(t);
  const bound=env.DB.bound.bind(env.DB);let deleted=false;
  env.DB.bound=(sql,args)=>{
    const statement=bound(sql,args);
    if(sql.includes("state='attempting',attempt_at=?")) {
      const all=statement.all.bind(statement);
      statement.all=async()=>{
        const result=await all();
        if(result.results.length===1 && !deleted) {
          deleted=true;
          const response=await receiver.fetch(req(p,token,'DELETE'),env);
          assert.equal((await response.json()).state,'deletion_pending');
        }
        return result;
      };
    }
    return statement;
  };
  await dispatch(env);
  const after=await stored(env,p.id);
  assert.equal(deleted,true);assert.equal(gh.posts,0);assert.equal(after.state,'deleted');
  assert.equal(after.payload,null);assert.equal(after.issue_number,null);
  assert.equal((await (await receiver.fetch(req(p,token,'GET'),env)).json()).state,'deleted');
  env.DB.db.exec('UPDATE feedback SET checked_at=0');await dispatch(env);assert.equal(gh.posts,0);
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

// Workers only accepts follow/manual. Never follow a GitHub redirect with the
// server capability or user content; status checks must keep the claim honest.
test('repository redirects never follow or permit a feedback creation claim',async(t)=>{
  const old=globalThis.fetch;t.after(()=>{globalThis.fetch=old;});
  for(const status of [301,302,307,308]) {
    const env=environment(),p=payload();await receiver.fetch(req(p),env);const calls=[];
    globalThis.fetch=async(url,init={})=>{
      assert.equal(init.redirect,'manual','Cloudflare Workers supports manual, not error');
      calls.push([String(url),init.method??'GET']);
      assert.equal(String(url),'https://api.github.com/repos/owner/private-feedback');
      return Response.json({private:true,full_name:'owner/private-feedback'},
        {status,headers:{Location:'https://untrusted.invalid/collect'}});
    };
    await dispatch(env);
    assert.deepEqual(calls,[['https://api.github.com/repos/owner/private-feedback','GET']]);
    const record=await stored(env,p.id);
    assert.equal(record.state,'pending');assert.equal(record.checked_at,0);
    assert.equal(record.attempt_at,null);assert.equal(record.issue_number,null);
    assert.equal(record.payload,JSON.stringify(validate(p)));
  }
});
test('reconciliation redirects cannot disclose credentials or resolve an uncertain report',async(t)=>{
  const old=globalThis.fetch;t.after(()=>{globalThis.fetch=old;});
  for(const status of [301,302,307,308]) {
    const env=environment(),p=payload();await receiver.fetch(req(p),env);
    env.DB.db.prepare("UPDATE feedback SET state='uncertain' WHERE id=?").run(p.id);
    const calls=[];
    globalThis.fetch=async(url,init={})=>{
      assert.equal(init.redirect,'manual','Cloudflare Workers supports manual, not error');
      assert.equal(init.method,undefined);assert.equal(new URL(url).origin,'https://api.github.com');
      calls.push(String(url));
      if(String(url).includes('/issues?')) return Response.json([
        {number:71,node_id:'SYNTHETIC-REDIRECT',title:`Riftlet feedback RF-${p.id}`,body:`<!-- riftlet-feedback:v1:${p.id} -->\n`}
      ],{status,headers:{Location:'https://untrusted.invalid/collect'}});
      return Response.json({private:true,full_name:'owner/private-feedback'});
    };
    await dispatch(env);assert.equal(calls.length,2);
    const record=await stored(env,p.id);
    assert.equal(record.state,'uncertain');assert.equal(record.issue_number,null);
    assert.equal(record.issue_node_id,null);assert(record.checked_at>0);
  }
});
test('Issue POST redirects stay uncertain and later ticks never repeat or follow POST',async(t)=>{
  const oldFetch=globalThis.fetch,oldNow=Date.now;let now=2_000_000_000;
  Date.now=()=>now*1000;t.after(()=>{globalThis.fetch=oldFetch;Date.now=oldNow;});
  for(const status of [301,302,307,308]) {
    const env=environment(),p=payload();await receiver.fetch(req(p),env);let posts=0,requests=0,reconciles=0;
    globalThis.fetch=async(url,init={})=>{
      assert.equal(init.redirect,'manual','Cloudflare Workers supports manual, not error');
      assert.equal(new URL(url).origin,'https://api.github.com');requests++;
      if(init.method==='POST') {
        posts++;assert.equal(String(url),'https://api.github.com/repos/owner/private-feedback/issues');
        assert.equal(JSON.parse(init.body).title,`Riftlet feedback RF-${p.id}`);
        return Response.json({number:72,node_id:'SYNTHETIC-REDIRECT'},
          {status,headers:{Location:'https://untrusted.invalid/collect'}});
      }
      if(String(url).includes('/issues?')) {reconciles++;return Response.json([]);}
      return Response.json({private:true,full_name:'owner/private-feedback'});
    };
    await dispatch(env);
    let record=await stored(env,p.id);
    assert.equal(record.state,'uncertain');assert.equal(record.attempt_at,now);
    assert.equal(record.issue_number,null);assert.equal(record.issue_node_id,null);
    for(let tick=0;tick<2;tick++){now+=301;await dispatch(env);}
    record=await stored(env,p.id);
    assert.equal(record.state,'uncertain');assert.equal(record.issue_number,null);
    assert.equal(record.payload,JSON.stringify(validate(p)));
    assert.equal(posts,1);assert.equal(reconciles,2);assert.equal(requests,6);
  }
});
