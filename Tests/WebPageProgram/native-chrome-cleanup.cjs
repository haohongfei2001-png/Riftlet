'use strict';
// Only the disposable native-Chrome test process and its loopback server are
// managed here. A failed ownership query is a failed cleanup, never permission
// to signal a different browser or to remove a potentially active profile.
const assert=require('node:assert/strict');
const {execFile}=require('node:child_process');

async function bounded(promise,milliseconds,label,signal) {
  let timer,onAbort;
  // An already-aborted caller may never reach Promise.race. Still observe a
  // later rejection from the operation it has just cancelled.
  promise=Promise.resolve(promise);promise.catch(()=>{});
  try {
    if(signal?.aborted)throw signal.reason||Error('fixture aborted');
    const limits=[promise,new Promise((_,reject)=>{
      timer=setTimeout(()=>reject(Error(typeof label==='function'?label():label)),Math.max(1,milliseconds));
    })];
    if(signal)limits.push(new Promise((_,reject)=>{
      onAbort=()=>reject(signal.reason||Error('fixture aborted'));
      signal.addEventListener('abort',onAbort,{once:true});
    }));
    return await Promise.race(limits);
  } finally {
    clearTimeout(timer);
    if(onAbort)signal.removeEventListener('abort',onAbort);
  }
}

function ownedLiveMembers(output,ownedPGID) {
  assert.ok(Number.isSafeInteger(ownedPGID)&&ownedPGID>1,'invalid owned Chrome PGID');
  assert.ok(typeof output==='string'&&output.trim(),'empty process-state snapshot cannot prove cleanup');
  const members=[],seen=new Set();
  for(const line of output.split(/\r?\n/).filter(line=>line.trim())) {
    // Darwin can report '?' (mach_state_table), followed by ordinary modifiers.
    // Unknown states remain live. Only an explicitly reported zombie is omitted.
    const match=/^\s*(\d+)\s+(\d+)\s+([A-Za-z?][A-Za-z+<>=-]*)\s*$/.exec(line);
    assert.ok(match,'cannot parse owned Chrome process-state query');
    const pid=Number(match[1]),pgid=Number(match[2]),state=match[3];
    assert.ok(Number.isSafeInteger(pid)&&Number.isSafeInteger(pgid)&&!seen.has(pid),'invalid process metadata');
    seen.add(pid);
    if(pgid===ownedPGID&&state[0]!=='Z')members.push({pid,pgid,state});
  }
  return members;
}

function releaseChildHandles(child) {
  const errors=[];
  // Descendants may still own a duplicated stderr descriptor after root exit.
  // The exit event alone does not close that pipe or unreference a detached child.
  for(const stream of [child?.stdin,child?.stdout,child?.stderr]) {
    try { stream?.destroy(); } catch(error) { errors.push(error); }
  }
  try { child?.unref(); } catch(error) { errors.push(error); }
  return errors;
}

async function readProcessSnapshot({timeoutMs,signal}) {
  let query;
  const result=new Promise((resolve,reject)=>{
    query=execFile('/bin/ps',['-A','-o','pid=,pgid=,stat='],
      {encoding:'utf8',timeout:timeoutMs,maxBuffer:2*1024*1024},(error,stdout,stderr)=>{
        if(error) {
          // No command output, process arguments or arbitrary error descriptions.
          const detail={code:typeof error.code==='number'||typeof error.code==='string'?error.code:null,
            signal:typeof error.signal==='string'?error.signal:null,killed:error.killed===true};
          reject(Error('owned Chrome cleanup process-query failed: '+JSON.stringify(detail)));return;
        }
        if(stderr.trim()){reject(Error('owned Chrome cleanup process-query wrote stderr'));return;}
        resolve(stdout);
      });
  });
  try { return await bounded(result,timeoutMs+50,'owned Chrome cleanup process-query deadline',signal); }
  finally {
    const errors=[];
    try { if(query?.pid&&query.exitCode===null&&query.signalCode===null)query.kill('SIGKILL'); }
    catch(error) { errors.push(error); }
    errors.push(...releaseChildHandles(query));
    if(errors.length)throw new AggregateError(errors,'owned process-query handle release failed');
  }
}

async function cleanupOwnedChrome(child,exit,options={}) {
  const readPS=options.readPS||readProcessSnapshot,killGroup=options.killGroup||process.kill;
  const totalMs=options.totalMs??9000,queryMs=options.queryMs??3000;
  const termMs=options.termMs??3000,killMs=options.killMs??2000,exitMs=options.exitMs??1000,pollMs=options.pollMs??50;
  const controller=new AbortController(),deadline=performance.now()+totalMs,errors=[];
  let phase='ownership',ownedPGID;
  const timer=setTimeout(()=>controller.abort(Error('owned Chrome cleanup deadline: '+phase)),totalMs);
  const remaining=()=>{
    const value=deadline-performance.now();
    if(controller.signal.aborted)throw controller.signal.reason;
    if(value<=0)throw Error('owned Chrome cleanup deadline: '+phase);
    return value;
  };
  const members=async()=>{
    phase='process-query';
    const timeoutMs=Math.max(1,Math.floor(Math.min(queryMs,remaining())));
    const output=await bounded(Promise.resolve().then(()=>readPS({timeoutMs,signal:controller.signal})),
      timeoutMs+50,'owned Chrome cleanup process-query deadline',controller.signal);
    phase='process-parse';
    return ownedLiveMembers(output,ownedPGID);
  };
  const signal=async kind=>{
    if(!(await members()).length)return false;
    phase=kind;remaining();
    try { killGroup(-ownedPGID,kind);return true; }
    catch(error) {
      // ESRCH/EPERM can occur for zombie-only groups, but never prove exit alone.
      if(!['ESRCH','EPERM'].includes(error.code)||(await members()).length)throw error;
      return false;
    }
  };
  const groupExitedWithin=async milliseconds=>{
    const until=performance.now()+milliseconds;
    while((await members()).length) {
      if(performance.now()>=until)return false;
      phase='process-wait';
      await bounded(new Promise(resolve=>setTimeout(resolve,pollMs)),remaining(),
        'owned Chrome cleanup process-wait deadline',controller.signal);
    }
    return true;
  };
  try {
    if(child?.pid) {
      ownedPGID=child.pid;
      assert.ok(Number.isSafeInteger(ownedPGID)&&ownedPGID>1,'invalid owned Chrome PGID');
      if(await signal('SIGTERM')&&!(await groupExitedWithin(termMs))) {
        await signal('SIGKILL');
        assert.ok(await groupExitedWithin(killMs),'owned Chrome process group remained after SIGKILL');
      }
      phase='root-exit';
      await bounded(exit,Math.min(exitMs,remaining()),'Chrome main exit event was not received',controller.signal);
    }
  } catch(error) {
    errors.push(error);
    // If process-group evidence is unavailable, only the still-running process
    // handle returned by our spawn may be terminated. Helpers remain unverified,
    // so preserve the original failure and leave the profile for runner cleanup.
    if(Number.isSafeInteger(ownedPGID)&&ownedPGID>1&&child.exitCode===null&&child.signalCode===null) {
      try { child.kill('SIGKILL'); } catch(failure) { errors.push(failure); }
      try { await bounded(exit,exitMs,'Chrome root fallback exit deadline'); } catch(failure) { errors.push(failure); }
    }
  } finally {
    clearTimeout(timer);controller.abort(Error('owned Chrome cleanup finished'));
    errors.push(...releaseChildHandles(child));
  }
  if(errors.length)throw new AggregateError(errors,'owned Chrome cleanup failed; profile retained; phase='+phase+
    '; '+errors.map(error=>error.message).join('; '));
}

async function closeLoopbackServer(server,connections,{timeoutMs=2000}={}) {
  const errors=[];
  try {
    const closed=new Promise((resolve,reject)=>server.close(error=>{
      if(error&&error.code!=='ERR_SERVER_NOT_RUNNING')reject(error);else resolve();
    }));
    closed.catch(()=>{});
    // Stop accepting first; otherwise a new socket can race closeAllConnections.
    server.closeAllConnections();
    await bounded(closed,timeoutMs,'loopback server close deadline');
  } catch(error) { errors.push(error); }
  finally {
    try { server.closeAllConnections(); } catch(error) { errors.push(error); }
    for(const socket of connections) {
      try { socket.destroy(); } catch(error) { errors.push(error); }
    }
    try { server.unref(); } catch(error) { errors.push(error); }
  }
  if(errors.length)throw new AggregateError(errors,'loopback server cleanup failed: '+errors.map(error=>error.message).join('; '));
}

module.exports={bounded,ownedLiveMembers,cleanupOwnedChrome,closeLoopbackServer};
