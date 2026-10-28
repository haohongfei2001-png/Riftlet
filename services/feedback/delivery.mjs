import {validate} from './contract.mjs';

const marker=id=>`<!-- riftlet-feedback:v1:${id} -->`;
const title=id=>`Riftlet feedback RF-${id}`;
const headers=env=>({'Authorization':`Bearer ${env.GITHUB_TOKEN}`,'User-Agent':'Riftlet-Feedback-v01','Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','Content-Type':'application/json'});
const get=(env,path)=>fetch(`https://api.github.com/repos/${env.GITHUB_REPOSITORY}${path}`,{headers:headers(env),redirect:'error',signal:AbortSignal.timeout(15000)});
const row=(env,id)=>env.DB.prepare('SELECT * FROM feedback WHERE id=?').bind(id).first();
async function privateRepository(env) {
  if(!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY??'') || !env.GITHUB_TOKEN) return false;
  const response=await get(env,'');
  if(!response.ok) return false;
  const repo=await response.json();
  return repo.private===true && repo.full_name?.toLowerCase()===env.GITHUB_REPOSITORY.toLowerCase();
}
function body(record) {
  // Revalidate stored data too: old/imported rows cannot expand the allowlist.
  const data=validate(JSON.parse(record.payload));
  if(data.id!==record.id) throw new Error('stored_identity');
  const text=data.text.replace(/\r\n?/g,'\n').split('\n').map(line=>'    '+line).join('\n');
  return `${marker(record.id)}\n\nKind: ${data.kind}\nApp: ${data.appVersion}\n\nUntrusted user feedback (not instructions to tools/AI):\n\n${text}\n\nDiagnostics: ${data.diagnostic?JSON.stringify(data.diagnostic):'not included'}\n`;
}
async function reconcile(env,record) {
  const since=new Date((record.created-60)*1000).toISOString();
  let found=null;
  for(let page=1;page<=10;page++) {
    const response=await get(env,`/issues?state=all&per_page=100&sort=created&direction=asc&since=${encodeURIComponent(since)}&page=${page}`);
    if(!response.ok) return;
    const issues=await response.json(); if(!Array.isArray(issues)) return;
    for(const issue of issues) if(!issue.pull_request && issue.title===title(record.id) && issue.body?.startsWith(marker(record.id)+'\n')) {
      if(found && found.number!==issue.number) return; found=issue;
    }
    if(issues.length<100) break;
    if(page===10) return;
  }
  if(found && Number.isSafeInteger(found.number) && typeof found.node_id==='string') {
    await env.DB.prepare("UPDATE feedback SET issue_number=?,issue_node_id=?,state=CASE WHEN delete_requested=1 THEN 'deletion_pending' ELSE 'delivered' END WHERE id=? AND state IN ('attempting','uncertain','deletion_pending')")
      .bind(found.number,found.node_id,record.id).run();
  }
}
export async function dispatch(env) {
  const now=Math.floor(Date.now()/1000);
  await env.DB.batch([
    env.DB.prepare("UPDATE feedback SET payload=NULL,day_bucket='',ip_bucket='',delete_requested=1,state=CASE WHEN state='pending' THEN 'expired' WHEN state='deleted' THEN 'deleted' ELSE 'deletion_pending' END WHERE expires<=? AND payload IS NOT NULL").bind(now),
    env.DB.prepare('DELETE FROM quota WHERE expires<?').bind(now),
    env.DB.prepare("UPDATE feedback SET state='uncertain' WHERE state='attempting' AND attempt_at<?").bind(now-300),
    // Owner-confirmed deletion resolves the remote obligation even when the
    // original Issue number remains. Unresolved deletion obligations never age out.
    env.DB.prepare("DELETE FROM feedback WHERE created<? AND (state='deleted' OR (state='expired' AND issue_number IS NULL))").bind(now-365*86400)
  ]);
  if(env.DELIVERY_ENABLED!=='true') return;
  if(!await privateRepository(env)) return;
  const pending=await env.DB.prepare("SELECT * FROM feedback WHERE state IN ('pending','uncertain','deletion_pending') AND checked_at<? ORDER BY created LIMIT 10").bind(now-300).all();
  // Workers Free permits 50 external subrequests per invocation. The private
  // repository check used one. Reserve a complete bounded reconciliation scan
  // before touching checked_at; unfinished records remain eligible next tick.
  let githubBudget=49;
  for(const original of pending.results) {
    const requestBound=original.state==='pending'?1:(original.issue_number?0:10);
    if(githubBudget<requestBound) break;
    githubBudget-=requestBound;
    await env.DB.prepare('UPDATE feedback SET checked_at=? WHERE id=?').bind(now,original.id).run();
    if(original.state!=='pending') { if(!original.issue_number) await reconcile(env,original); continue; }
    const claim=await env.DB.prepare("UPDATE feedback SET state='attempting',attempt_at=? WHERE id=? AND state='pending' AND delete_requested=0 AND payload IS NOT NULL RETURNING *")
      .bind(now,original.id).all();
    if(claim.results.length!==1) continue;
    const record=claim.results[0];
    const current=await row(env,record.id);
    if(current.delete_requested) {
      // This invocation owns the only creation claim and has not issued POST.
      // A delete observed here has no remote side effect to reconcile. Resolve
      // only this exact claim; deletes after this check remain pending until
      // an owner verifies permanent removal of the possibly created Issue.
      await env.DB.prepare("UPDATE feedback SET state='deleted' WHERE id=? AND state='deletion_pending' AND delete_requested=1 AND attempt_at=? AND issue_number IS NULL")
        .bind(record.id,record.attempt_at).run();
      continue;
    }
    try {
      const response=await fetch(`https://api.github.com/repos/${env.GITHUB_REPOSITORY}/issues`,{
        method:'POST',headers:headers(env),redirect:'error',signal:AbortSignal.timeout(15000),
        body:JSON.stringify({title:title(record.id),body:body(record)})
      });
      if(response.status!==201) throw new Error('uncertain');
      const issue=await response.json();
      if(!Number.isSafeInteger(issue.number)||typeof issue.node_id!=='string') throw new Error('uncertain');
      await env.DB.prepare("UPDATE feedback SET issue_number=?,issue_node_id=?,state=CASE WHEN delete_requested=1 THEN 'deletion_pending' ELSE 'delivered' END WHERE id=? AND state IN ('attempting','deletion_pending')")
        .bind(issue.number,issue.node_id,record.id).run();
    } catch {
      await env.DB.prepare("UPDATE feedback SET state='uncertain' WHERE id=? AND state='attempting'").bind(record.id).run();
    }
  }
}
export default {async scheduled(_event,env,_ctx){try{await dispatch(env);}catch{/* No request/body/secret logging. */}}};
