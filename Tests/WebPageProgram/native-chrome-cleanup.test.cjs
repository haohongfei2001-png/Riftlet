'use strict';
// Pure fault fixtures. They never launch a browser or query the host process list.
const test=require('node:test');
const assert=require('node:assert/strict');
const {execFile}=require('node:child_process');
const {promisify}=require('node:util');
const {bounded,ownedLiveMembers,cleanupOwnedChrome,closeLoopbackServer}=require('./native-chrome-cleanup.cjs');

function fakeChild({exited=false}={}) {
  const calls=[];let resolveExit;
  const exit=new Promise(resolve=>{resolveExit=resolve;});
  const child={pid:1234,exitCode:exited?0:null,signalCode:null,
    stderr:{destroy(){calls.push('pipe-destroy');}},unref(){calls.push('child-unref');},
    kill(signal){calls.push('root-'+signal);child.signalCode=signal;resolveExit();return true;}};
  if(exited)resolveExit();
  return {child,exit,calls};
}
const quick={totalMs:300,queryMs:20,termMs:0,killMs:0,exitMs:20,pollMs:1};

test('Darwin unknown process states stay live; only exact owned PGID is selected',()=>{
  const snapshot=' 0 0 I\n 1 1 S\n 1234 1234 ?\n 1235 1234 ?N+\n 1236 1234 Z\n 2222 2222 S<\n';
  assert.deepEqual(ownedLiveMembers(snapshot,1234),[
    {pid:1234,pgid:1234,state:'?'},{pid:1235,pgid:1234,state:'?N+'}]);
});

test('every snapshot line and numeric identifier must validate before cleanup',()=>{
  for(const invalid of ['', '1234 1234 S\nnot metadata', '1234 -1234 S', '1e3 1234 S',
    '9007199254740992 1234 S', '1234 9007199254740992 S', '1234 1234 S command',
    '1234 1234 7', '1234 1234 S2', '1234 1234 S\n1234 2222 R']) {
    assert.throws(()=>ownedLiveMembers(invalid,1234));
  }
  for(const group of [0,1,-1,1.5,Number.MAX_SAFE_INTEGER+1])assert.throws(()=>ownedLiveMembers('1 1 S',group));
});

test('cleanup escalates only its exact group and requires an observed empty group',async()=>{
  const f=fakeChild({exited:true}),signals=[];let reads=0;
  await cleanupOwnedChrome(f.child,f.exit,{...quick,
    readPS:async()=>++reads<4?'1 1 S\n1235 1234 ?\n':'1 1 S\n1235 1234 Z\n',
    killGroup:(group,signal)=>signals.push([group,signal])});
  assert.deepEqual(signals,[[-1234,'SIGTERM'],[-1234,'SIGKILL']]);
  assert.equal(reads,4);assert.deepEqual(f.calls,['pipe-destroy','child-unref']);
});

test('EPERM is accepted only after a second snapshot proves no live group member',async()=>{
  const f=fakeChild({exited:true});let reads=0;
  await cleanupOwnedChrome(f.child,f.exit,{...quick,
    readPS:async()=>++reads===1?'1234 1234 S':'1234 1234 Z',
    killGroup:()=>{throw Object.assign(Error('synthetic group signal error'),{code:'EPERM'});}});
  assert.equal(reads,2);assert.ok(f.calls.includes('child-unref'));
});

test('a malformed ownership query fails without signalling any process group',async()=>{
  const f=fakeChild(),signals=[];
  await assert.rejects(cleanupOwnedChrome(f.child,f.exit,{...quick,
    readPS:async()=>'1234 1234 S\nmalformed',killGroup:(...args)=>signals.push(args)}),/cleanup failed; profile retained/);
  assert.deepEqual(signals,[]);
  assert.deepEqual(f.calls,['root-SIGKILL','pipe-destroy','child-unref']);
});

test('query rejection and timeout preserve failure while releasing only owned handles',async()=>{
  for(const readPS of [async()=>{throw Object.assign(Error('fixture query failed'),{code:'ETIMEDOUT'});},()=>new Promise(()=>{})]) {
    const f=fakeChild();let groupSignals=0;
    await assert.rejects(cleanupOwnedChrome(f.child,f.exit,{...quick,readPS,killGroup:()=>groupSignals++}),/cleanup failed; profile retained/);
    assert.equal(groupSignals,0);assert.deepEqual(f.calls,['root-SIGKILL','pipe-destroy','child-unref']);
  }
});

test('queries tolerate up to three seconds but remain limited by the total cleanup deadline',async()=>{
  const normal=fakeChild({exited:true});let budget;
  await cleanupOwnedChrome(normal.child,normal.exit,{readPS:async options=>{budget=options.timeoutMs;return '1 1 S';}});
  assert.equal(budget,3000);
  const stalled=fakeChild();let limited;
  await assert.rejects(cleanupOwnedChrome(stalled.child,stalled.exit,{...quick,totalMs:15,queryMs:3000,
    readPS:options=>{limited=options.timeoutMs;return new Promise(()=>{});}}),/cleanup deadline: process-query/);
  assert.ok(limited>0&&limited<=15);
  assert.deepEqual(stalled.calls,['root-SIGKILL','pipe-destroy','child-unref']);
});

test('live members after SIGKILL remain a failure rather than successful cleanup',async()=>{
  const f=fakeChild({exited:true}),signals=[];
  await assert.rejects(cleanupOwnedChrome(f.child,f.exit,{...quick,
    readPS:async()=>'1235 1234 ?',killGroup:(...args)=>signals.push(args)}),error=>{
      assert.match(error.errors[0].message,/remained after SIGKILL/);return true;
    });
  assert.deepEqual(signals,[[-1234,'SIGTERM'],[-1234,'SIGKILL']]);
  assert.deepEqual(f.calls,['pipe-destroy','child-unref']);
});

test('a missing root exit event is bounded and cannot retain child or stderr references',async()=>{
  const f=fakeChild();f.child.kill=signal=>{f.calls.push('root-'+signal);return true;};
  await assert.rejects(cleanupOwnedChrome(f.child,f.exit,{...quick,
    readPS:async()=>'1 1 S',killGroup:()=>assert.fail('empty group must not be signalled')}),error=>{
      assert.match(error.errors[0].message,/exit event/);return true;
    });
  assert.deepEqual(f.calls,['root-SIGKILL','pipe-destroy','child-unref']);
});

test('fixture abort interrupts its report wait and still executes owned cleanup',async()=>{
  const controller=new AbortController(),f=fakeChild({exited:true});let cleanupRan=false;
  const waiting=bounded(new Promise(()=>{}),5000,'unexpected timeout',controller.signal);
  controller.abort(Error('fixture test cancelled'));
  try { await assert.rejects(waiting,/fixture test cancelled/); }
  finally {
    await cleanupOwnedChrome(f.child,f.exit,{...quick,readPS:async()=>'1 1 S'});cleanupRan=true;
  }
  assert.equal(cleanupRan,true);assert.deepEqual(f.calls,['pipe-destroy','child-unref']);
});

test('loopback close stops accepting before dropping connections and has a deadline',async()=>{
  const calls=[],socket={destroy(){calls.push('socket-destroy');}};
  const server={close(){calls.push('close');},closeAllConnections(){calls.push('close-all');},unref(){calls.push('server-unref');}};
  await assert.rejects(closeLoopbackServer(server,new Set([socket]),{timeoutMs:10}),error=>{
    assert.match(error.errors[0].message,/close deadline/);return true;
  });
  assert.deepEqual(calls,['close','close-all','close-all','socket-destroy','server-unref']);
});

test('normal loopback close and an unstarted server both settle without leaked references',async()=>{
  for(const error of [undefined,Object.assign(Error('not listening'),{code:'ERR_SERVER_NOT_RUNNING'})]) {
    const calls=[],server={close(callback){calls.push('close');queueMicrotask(()=>callback(error));},
      closeAllConnections(){calls.push('close-all');},unref(){calls.push('server-unref');}};
    await closeLoopbackServer(server,new Set(),{timeoutMs:20});
    assert.deepEqual(calls,['close','close-all','close-all','server-unref']);
  }
});

test('faulted cleanup lets a real Node executor exit naturally despite simulated child and pipe refs',async()=>{
  // Actual referenced timers stand in for the two libuv handles. The worker
  // must exit without process.exit(); omitting destroy OR unref hangs it and
  // makes execFile's external deadline fail this regression.
  const worker=String.raw`
const {cleanupOwnedChrome,bounded}=require(HELPER);
const mode=process.argv[1],refs=[setInterval(()=>{},100),setInterval(()=>{},100)],events=[];
let resolveExit;const exit=new Promise(resolve=>resolveExit=resolve);
const child={pid:1234,exitCode:null,signalCode:null,stderr:{destroy(){clearInterval(refs[0]);events.push('pipe');}},
  unref(){refs[1].unref();events.push('unref');},kill(signal){this.signalCode=signal;resolveExit();events.push('root');return true;}};
(async()=>{
  let failed=false;
  if(mode==='abort'){
    const controller=new AbortController();controller.abort(Error('cancelled'));
    try{await bounded(new Promise(()=>{}),5000,'unexpected timeout',controller.signal);}catch{events.push('abort');}
  }
  try{
    await cleanupOwnedChrome(child,exit,{totalMs:200,queryMs:10,exitMs:10,
      readPS:()=>mode==='parse'?Promise.resolve('malformed'):mode==='stall'?new Promise(()=>{}):Promise.reject(Error('query failed')),
      killGroup:()=>{throw Error('UNEXPECTED_GROUP_SIGNAL');}});
  }catch{failed=true;}
  console.log(JSON.stringify({failed,events}));
})();`.replace('HELPER',JSON.stringify(require.resolve('./native-chrome-cleanup.cjs')));
  for(const mode of ['parse','query','stall','abort']) {
    const {stdout}=await promisify(execFile)(process.execPath,['-e',worker,mode],{timeout:2500,maxBuffer:65536});
    const result=JSON.parse(stdout);assert.equal(result.failed,true);assert.ok(result.events.includes('pipe'));
    assert.ok(result.events.includes('unref'));assert.ok(result.events.includes('root'));
    if(mode==='abort')assert.ok(result.events.includes('abort'));
  }
});
