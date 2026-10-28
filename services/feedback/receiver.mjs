import {MAX_BODY,validate,validID,digest,ipBucket,json,receipt} from './contract.mjs';

async function boundedBody(request) {
  if (Number(request.headers.get('Content-Length')) > MAX_BODY) throw new Error('size');
  if (!request.body) throw new Error('schema');
  const reader = request.body.getReader(); let size=0; const chunks=[];
  let timer;
  try {
    const expiry = new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('timeout')),5000);});
    while (true) {
      const {done,value}=await Promise.race([reader.read(),expiry]);
      if(done) break; size+=value.byteLength; if(size>MAX_BODY) throw new Error('size'); chunks.push(value);
    }
    const joined = new Uint8Array(size); let offset=0;
    for(const c of chunks){joined.set(c,offset);offset+=c.length;}
    return new TextDecoder('utf-8',{fatal:true}).decode(joined);
  } finally { clearTimeout(timer); await reader.cancel().catch(()=>{}); reader.releaseLock(); }
}
async function authenticate(request) {
  const auth=request.headers.get('Authorization')??'';
  if(!/^Bearer [0-9a-f]{64}$/.test(auth)) return null;
  return digest(auth.slice(7));
}
const lookup = (db,id) => db.prepare('SELECT * FROM feedback WHERE id=?').bind(id).first();
async function handle(request,env) {
  const url=new URL(request.url);
  if(url.search || url.hash) return json({error:'invalid_route'},400);
  const hash=await authenticate(request);
  if(!hash) return json({error:'unauthorized'},401);
  const now=Math.floor(Date.now()/1000);
  if(request.method==='POST' && url.pathname==='/v1/feedback') {
    if(env.ACCEPT_ENABLED !== 'true' || typeof env.IP_HMAC_KEY !== 'string' || env.IP_HMAC_KEY.length<32) return json({error:'unavailable'},503);
    if(request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase()!=='application/json'
        || request.headers.has('Content-Encoding')) return json({error:'content_type'},415);
    let value;
    try {value=validate(JSON.parse(await boundedBody(request)));}
    catch(e){return json({error:e.message==='size'?'size':'schema'},e.message==='size'?413:422);}
    const payload=JSON.stringify(value), payloadHash=await digest(payload);
    let row=await lookup(env.DB,value.id);
    if(!row) {
      if(value.createdAt<now-30*86400 || value.createdAt>now+300) return json({error:'submission_age'},422);
      const ip=request.headers.get('CF-Connecting-IP');
      if(!ip) return json({error:'unavailable'},503);
      const day='day:'+Math.floor(now/86400), bucket=await ipBucket(ip,Math.floor(now/3600),env.IP_HMAC_KEY);
      try {
        const result=await env.DB.batch([
          env.DB.prepare("INSERT INTO feedback(id,payload_hash,secret_hash,payload,created,expires,day_bucket,ip_bucket) SELECT ?,?,?,?,?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM feedback WHERE id=?)")
            .bind(value.id,payloadHash,hash,payload,now,now+90*86400,day,bucket,value.id),
          env.DB.prepare('SELECT * FROM feedback WHERE id=?').bind(value.id)
        ]);
        row=result[1].results[0];
      } catch(e) {
        if(String(e.message).includes('feedback_quota')) return json({error:'rate_limited'},429,{'Retry-After':'3600'});
        return json({error:'unavailable'},503);
      }
    }
    if(!row) return json({error:'unavailable'},503);
    if(row.secret_hash!==hash) return json({error:'not_found'},404);
    // Empty hash is only a capability-bound delete-before-submit tombstone.
    if(row.payload_hash==='' && row.state==='deleted' && row.delete_requested===1) return json(receipt(row),202);
    if(row.payload_hash!==payloadHash) return json({error:'conflict'},409);
    return json(receipt(row),202);
  }
  const match=/^\/v1\/feedback\/([^/]+)$/.exec(url.pathname);
  if(!match || !validID(match[1]) || !['GET','DELETE'].includes(request.method)) return json({error:'not_found'},404);
  const id=match[1];
  let row=await lookup(env.DB,id);
  if(row && row.secret_hash!==hash) return json({error:'not_found'},404);
  if(request.method==='DELETE') {
    const statements=[];
    if(!row) {
      // DELETE may beat an already-in-flight POST. Record a bounded tombstone
      // under this exact capability instead of allowing a late POST to revive it.
      const ip=request.headers.get('CF-Connecting-IP');
      if(!ip || typeof env.IP_HMAC_KEY!=='string' || env.IP_HMAC_KEY.length<32) return json({error:'unavailable'},503);
      const day='day:'+Math.floor(now/86400), bucket=await ipBucket(ip,Math.floor(now/3600),env.IP_HMAC_KEY);
      statements.push(env.DB.prepare("INSERT INTO feedback(id,payload_hash,secret_hash,payload,created,expires,day_bucket,ip_bucket,state,delete_requested) SELECT ?,'',?,NULL,?,?,?,?,'deleted',1 WHERE NOT EXISTS(SELECT 1 FROM feedback WHERE id=?)")
        .bind(id,hash,now,now+365*86400,day,bucket,id));
    }
    // Insertion, authorization recheck, content removal and receipt are one
    // transaction. A concurrently inserted different capability is never deleted.
    statements.push(env.DB.prepare("UPDATE feedback SET delete_requested=1,payload=NULL,day_bucket='',ip_bucket='',state=CASE WHEN state IN ('pending','expired','deleted') THEN 'deleted' ELSE 'deletion_pending' END WHERE id=? AND secret_hash=?").bind(id,hash));
    statements.push(env.DB.prepare('SELECT * FROM feedback WHERE id=?').bind(id));
    try {
      const result=await env.DB.batch(statements);
      row=result[result.length-1].results[0];
    } catch(e) {
      if(String(e.message).includes('feedback_quota')) return json({error:'rate_limited'},429,{'Retry-After':'3600'});
      return json({error:'unavailable'},503);
    }
    if(!row || row.secret_hash!==hash) return json({error:'not_found'},404);
    return json(receipt(row),202);
  }
  if(!row) return json({error:'not_found'},404);
  return json(receipt(row));
}
export default {
  async fetch(request,env) {
    try {return await handle(request,env);} catch {return json({error:'unavailable'},503);}
  }
};
