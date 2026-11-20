'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const {createLockedDraft,withLockedDraft} = require('./locked-draft.cjs');

function environment() {
  const prior = {member:'a'.repeat(64),payload:'1'.repeat(64)};
  const next = {member:'b'.repeat(64),payload:'2'.repeat(64)};
  const bundle = 'com.microsoft.edgemac';
  const s = {bundle,sessionID:'edge-birth',windowID:'20',tabID:'25',windowHandle:'win',tabHandle:'tab',
    nativeHandleMatched:true,frontSessionID:'edge-birth',frontWindowID:'20',selectedTabID:'25',route:'about:blank',
    documentID:'document',composerID:'compose',draftGeneration:'generation',navigationID:'nav',text:'',selection:'',
    editorCount:1,messageCount:0,cards:[],signedIn:true,focusedOriginalEditor:false};
  const keys = [], events = [];
  const tab = {id:'tab',windowId:'win',goto:async url=>{s.route=url},cua:{keypress:async ({keys:chord})=>{
    keys.push(chord.slice());
    if (chord.length===1) s.text+=chord[0];
    else if (String(chord)==='SHIFT,LEFT') s.selection=s.text.slice(-1);
    else assert.fail('unexpected key');
  }}};
  const e = {tab,bundle,s,prior,next,keys,events};
  e.closes = 0;
  tab.close = async () => { e.closes++; };
  e.options = {
    bundle,browser:{tabs:{list:async()=>e.existing||[],new:async options=>{assert.equal(options.newWindow,true);return tab}}},
    read:async t=>{assert.equal(t,tab);e.duringRead?.();return {...s,cards:s.cards.slice()}},
    locateNewChat:async()=>({count:async()=>1,isVisible:async()=>true,click:async()=>{
      events.push('new');s.composerID='fresh';e.afterNew?.();
    }}),
    locateEditor:async()=>({count:async()=>1,isVisible:async()=>true,click:async()=>{s.focusedOriginalEditor=true}}),
  };
  e.start = () => createLockedDraft(e.options);
  return e;
}

test('opens a dedicated window and seeds only through keys, no Send',async()=>{
  const e=environment(), run=await e.start(), seed=await run.seed();
  assert.deepEqual(e.events,['new']);
  assert.deepEqual(e.keys.at(-1),['SHIFT','LEFT']);
  assert.equal(e.keys.slice(0,-1).map(k=>k[0]).join(''),seed.text);
  assert.equal(seed.selection,seed.text.slice(-1));
  assert.ok(e.keys.every(k=>k.length!==1 || /^[a-z0-9]$/.test(k[0])));
  await assert.rejects(run.seed(),/consumed/);
});

test('existing conversation or dirty draft stops before opening new chat',async()=>{
  for (const override of [{route:'https://chatgpt.com/c/existing'},{text:'pre-existing'},
                           {cards:[environment().prior]},{messageCount:1},{signedIn:false}]) {
    const e=environment();
    const go=e.tab.goto;
    e.tab.goto=async url=>{await go(url);Object.assign(e.s,override)};
    await assert.rejects(e.start(),/existing content/);
    assert.deepEqual(e.events,[]);assert.deepEqual(e.keys,[]);
  }
});

test('all native and page mismatches retire this original run',async()=>{
  for (const key of ['bundle','sessionID','windowID','tabID','windowHandle','tabHandle','frontWindowID',
                     'selectedTabID','documentID','composerID','draftGeneration','navigationID','route']) {
    const e=environment(),run=await e.start(), old=e.s[key];
    e.s[key]='replacement';
    await assert.rejects(run.seed());
    e.s[key]=old;
    await assert.rejects(run.seed());
    assert.deepEqual(e.keys,[]);
  }
});

test('lost reply after one key cannot cause another keyboard pass',async()=>{
  const e=environment(),run=await e.start();
  e.tab.cua.keypress=async ({keys})=>{e.keys.push(keys);throw new Error('lost reply')};
  await assert.rejects(run.seed(),/lost reply/);
  await assert.rejects(run.seed(),/consumed/);
  assert.equal(e.keys.length,1);
});

test('a change after the first key stops before a second',async()=>{
  const e=environment(), run=await e.start();e.duringRead=()=>{
    if (e.keys.length) e.s.selectedTabID='changed';
  };
  await assert.rejects(run.seed(),/destination changed/);
  assert.equal(e.keys.length,1);
});

test('prior selection, exact old members and new payload must all survive',async()=>{
  const e=environment(), run=await e.start();
  await run.seed();
  await assert.rejects(run.beforeClick(e.prior),/prior/);
  e.s.cards=[e.prior];const before=await run.beforeClick(e.prior);
  await assert.rejects(run.afterClick({...before}, e.next.payload),/outstanding/);
  e.s.cards=[e.next];await assert.rejects(run.afterClick(before,e.next.payload),/prior/);
  e.s.cards=[e.prior,e.next];await assert.rejects(run.afterClick(before,e.prior.payload),/matching/);
  assert.equal((await run.afterClick(before,e.next.payload)).outcome,'OBSERVED_NEW_CARD_ONLY');
  await assert.rejects(run.afterClick(before,e.next.payload),/outstanding/);
});

test('setup failure closes its confirmed fresh tab, never an existing or repurposed tab',async()=>{
  const e=environment();
  e.options.locateNewChat=async()=>{throw Error('missing control')};
  await assert.rejects(e.start(),err=>err.message==='missing control' && err.cleanup==='closed');
  assert.equal(e.closes,1);
  for (const change of [
    env=>{env.existing=[{id:env.tab.id}];},
    env=>{env.s.route='https://chatgpt.com/c/private';},
    env=>{env.tab.goto=async()=>{env.s.route='https://chatgpt.com/c/private'};},
    env=>{env.tab.goto=async()=>{env.s.route='https://chatgpt.com/';env.s.text='private';};},
    env=>{env.tab.goto=async()=>{env.s.route='https://chatgpt.com/';env.s.nativeHandleMatched=false;};},
  ]) {
    const other=environment(); change(other);
    await assert.rejects(other.start());assert.equal(other.closes,0);
  }
});

test('callback cleanup is once-only, original-tab scoped and preserves unknown contents',async()=>{
  const e=environment();
  const value=await withLockedDraft(e.options,async run=>{
    await run.seed();
    assert.equal(await run.close(),'closed');return 7;
  });
  assert.deepEqual(value,{result:7,cleanup:'closed'});assert.equal(e.closes,1);
  const failed=environment();
  await assert.rejects(withLockedDraft(failed.options, async()=>{throw Error('case failed');}),
    err=>err.message==='case failed' && err.cleanup==='closed');
  assert.equal(failed.closes,1);
  const unknown=environment(),run=await unknown.start();unknown.s.text='new personal content';
  assert.equal(await run.close(),'retainedUnverified');assert.equal(unknown.closes,0);
  const lost=environment(),leased=await lost.start();lost.tab.close=async()=>{lost.closes++;throw Error('reply lost');};
  assert.deepEqual(await Promise.all([leased.close(),leased.close()]),['closeUnconfirmed','closeUnconfirmed']);
  assert.equal(lost.closes,1);
});

test('Edge shape uses the individually bound original editor even after blur',async()=>{
  const filename='riftlet-6c4ab72a-1234-5678-9abc-101010101010.png';
  const e=environment(), form={querySelectorAll:()=>[]};
  let probes=0;
  e.options.locateOriginalEditor=async(tab,target)=>({...target,locator:{
    count:async()=>1,isVisible:async()=>true,
    evaluate:async(fn,arg)=>{probes++;assert.equal(arg,filename);return fn({matches:()=>true,closest:()=>form},arg);}
  }});
  const run=await e.start();e.s.focusedOriginalEditor=false;
  assert.deepEqual(await run.edgePreviewShape(filename),{matchingPreviewCount:0});assert.equal(probes,1);
  const bad=environment(); bad.options.locateOriginalEditor=async(tab,target)=>({...target,composerID:'replacement'});
  await assert.rejects((await bad.start()).edgePreviewShape(filename),/original editor unavailable/);
  const absent=environment();await assert.rejects((await absent.start()).edgePreviewShape(filename),/no original editor locator/);
});
