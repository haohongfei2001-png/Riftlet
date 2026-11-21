'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const {createLockedDraft,withLockedDraft} = require('./locked-draft.cjs');

function environment() {
  const prior = {member:'a'.repeat(64),payload:'1'.repeat(64)};
  const next = {member:'b'.repeat(64),payload:'2'.repeat(64)};
  const bundle = 'com.microsoft.edgemac';
  const s = {bundle,sessionID:'edge-kernel-v1:11:22:33',windowID:'20',tabID:'25',windowHandle:'20',tabHandle:'tab',
    nativeHandleMatched:true,frontSessionID:'edge-kernel-v1:11:22:33',frontWindowID:'20',selectedTabID:'25',route:'about:blank',
    documentID:'document',composerID:'compose',draftGeneration:'generation',navigationID:'nav',text:'',selection:'',
    editorCount:1,messageCount:0,cards:[],signedIn:true,focusedOriginalEditor:false};
  const keys = [], events = [];
  const tab = {id:'tab',goto:async url=>{s.route=url},cua:{keypress:async ({keys:chord})=>{
    keys.push(chord.slice());
    if (chord.length===1) s.text+=chord[0];
    else if (String(chord)==='SHIFT,LEFT') s.selection=s.text.slice(-1);
    else assert.fail('unexpected key');
  }}};
  const e = {tab,bundle,s,prior,next,keys,events};
  e.closes = 0;
  tab.close = async () => { e.closes++; };
  const blankRef = {id:'unclaimed',providerTabId:'25',url:'about:blank'};
  const management = {
    windows:{getAll:async()=>[{id:19}], create:async()=>{
      e.creates=(e.creates||0)+1;return {id:20,incognito:false,type:'normal'};
    }},
    tabs:{query:async({windowId})=>[{id:25,active:true,incognito:false,windowId,url:s.route}]},
  };
  const browser = {browserId:'extension-edge',tabs:{list:async()=>e.claimed?
    [{id:tab.id,providerTabId:'25'}]:e.existing||[]},
    user:{openTabs:async()=>e.creates?[blankRef]:e.existing||[],claimTab:async ref=>{
      assert.equal(ref,blankRef);e.claimed=true;return tab;
    }},
    capabilities:{list:async()=>[{id:'management'}],get:async()=>management}};
  e.browser = browser;
  e.management = management;
  e.options = {
    bundle,browser,browsers:{list:async()=>[{type:'extension',family:'edge',id:browser.browserId}]},
    readNative:async()=>({bundle,sessionID:s.frontSessionID,windowID:s.frontWindowID,tabID:s.selectedTabID}),
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
    await assert.rejects(e.start(),/existing content|QA_ROUTE_CHANGED/);
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

const {browserHealth} = require('./browser-preflight.cjs');

test('startup uses the selected family and reports RPC failure before any window or key',async()=>{
  const cases = [
    [e=>{e.options.browsers.list=async()=>{throw Error('Trusted RPC service is not configured: browser')}},
      'BROWSER_RPC_UNCONFIGURED'],
    [e=>{e.options.browsers.list=async()=>[{id:'other',family:'chrome',type:'extension'}]},
      'EXACT_EXTENSION_BROWSER_UNAVAILABLE'],
    [e=>{e.options.browsers.list=async()=>['one','two'].map(id=>({id,family:'edge',type:'extension'}))},
      'EXACT_EXTENSION_BROWSER_UNAVAILABLE'],
    [e=>{e.browser.capabilities.list=async()=>[]},'WINDOW_MANAGEMENT_UNAVAILABLE'],
    [e=>{delete e.options.readNative},'NATIVE_FRONT_OBSERVER_UNAVAILABLE'],
  ];
  for (const [alter,code] of cases) {
    const e=environment();alter(e);
    assert.deepEqual(await browserHealth(e.options),{status:'BLOCKED',code});
    assert.equal(e.creates,undefined);
    assert.equal(e.closes,0);
    assert.equal(e.keys.length,0);
  }
});

test('preflight returns no personal metadata, and canary opens only its one window',async()=>{
  const e=environment();
  e.existing=[{id:'other',title:'private title',url:'https://example.net/personal'}];
  assert.deepEqual(await browserHealth(e.options),{
    status:'AVAILABLE',windowCreation:'NOT_RUN',keyboardDelivery:'NOT_RUN'
  });
  assert.equal(e.creates,undefined);
  const run=await e.start();
  assert.equal(e.creates,1);
  await run.seed();
  assert.equal(await run.close(),'closed');
  assert.equal(e.creates,1);
});

test('refuses reused window or tab, mismatched foreground and ambiguous provider claim before any content read',async()=>{
  const cases = [
    e=>{e.management.windows.getAll=async()=>[{id:20}]},
    e=>{const open=e.browser.user.openTabs;e.browser.user.openTabs=async()=>e.creates?open():[{id:'other',providerTabId:'25'}]},
    e=>{e.s.frontSessionID='chrome-kernel-v1:7:8:9'},
    e=>{e.s.frontWindowID='19'},
    e=>{const open=e.browser.user.openTabs;e.browser.user.openTabs=async()=>[...await open(),...await open()]},
    e=>{const query=e.management.tabs.query;e.management.tabs.query=async opts=>(await query(opts)).map(t=>({...t,active:false}))},
  ];
  for (const alter of cases) {
    const e=environment();alter(e);let reads=0;e.options.read=async()=>{reads++;return e.s};
    await assert.rejects(e.start(),err=>err.status==='BLOCKED' && err.cleanup==='retainedUnverified');
    assert.equal(reads,0);assert.equal(e.closes,0);assert.equal(e.keys.length,0);
  }
});

test('lost creation or claim is UNKNOWN and is never retried',async()=>{
  for (const kind of ['creation','claim']) {
    const e=environment();let attempts=0;
    const lost=async()=>{attempts++;throw Error('private URL and content')};
    if (kind==='creation') e.management.windows.create=lost;
    else e.browser.user.claimTab=lost;
    await assert.rejects(e.start(),err=>err.status==='UNKNOWN' &&
      err.message==='QA_WINDOW_OR_CLAIM_REPLY_UNKNOWN' && err.cleanup==='retainedUnverified');
    assert.equal(attempts,1);assert.equal(e.closes,0);assert.deepEqual(e.keys,[]);
  }
});

test('missing directed keyboard closes only its witnessed blank tab',async()=>{
  const e=environment();delete e.tab.cua.keypress;
  await assert.rejects(e.start(),err=>err.code==='DIRECTED_TAB_API_UNAVAILABLE' && err.cleanup==='closed');
  assert.equal(e.closes,1);assert.deepEqual(e.events,[]);
});

test('guard observes native process replacement or extra tab before next page read or key',async()=>{
  for (const alter of [
    e=>{e.s.frontSessionID='edge-kernel-v1:11:22:34'},
    e=>{const q=e.management.tabs.query;e.management.tabs.query=async opts=>[...await q(opts),{id:98}]},
    e=>{e.s.route='https://chatgpt.com/c/personal'},
  ]) {
    const e=environment(),run=await e.start();alter(e);
    let reads=0;e.duringRead=()=>{reads++};
    await assert.rejects(run.seed());assert.equal(await run.close(),'retainedUnverified');
    assert.equal(reads,0);assert.equal(e.closes,0);assert.deepEqual(e.keys,[]);
  }
});

test('a New chat action without a fresh draft witness cannot start the keyboard canary',async()=>{
  const e=environment();
  e.options.locateNewChat=async()=>({count:async()=>1,isVisible:async()=>true,click:async()=>{}});
  await assert.rejects(e.start(),/no observable fresh draft/);
  assert.deepEqual(e.keys,[]);assert.equal(e.closes,1);
});


test('uses a persistent family-selected handle, no personal tab enumeration during health or keyboard guards',async()=>{
  const e=environment();
  e.options.browsers.get=async()=>assert.fail('must reuse the documented Browser');
  let userLists=0,tabLists=0;
  const users=e.browser.user.openTabs,tabs=e.browser.tabs.list;
  e.browser.user.openTabs=async()=>{userLists++;return users()};
  e.browser.tabs.list=async()=>{tabLists++;return tabs()};
  assert.equal((await browserHealth(e.options)).status,'AVAILABLE');
  assert.deepEqual([userLists,tabLists],[0,0]);
  e.management.windows.create=async()=>{e.creates=1;return {id:20}};
  const run=await e.start();
  await run.seed();await run.close();
  assert.deepEqual([userLists,tabLists],[2,1]);
});

test('refuses contradictory create reply and pending navigation before accessing the page',async()=>{
  for (const alter of [
    e=>{e.management.windows.create=async()=>({id:20,incognito:true})},
    e=>{e.management.windows.create=async()=>({id:20,tabs:[{id:21}]})},
    e=>{const q=e.management.tabs.query;e.management.tabs.query=async opts=>(await q(opts))
      .map(t=>({...t,pendingUrl:'https://example.net/'}))},
  ]) {
    const e=environment();alter(e);let reads=0;e.options.read=async()=>{reads++;return e.s};
    await assert.rejects(e.start());assert.equal(reads,0);assert.equal(e.closes,0);
  }
});

test('a delayed New chat witness settles after two old identities and receives exactly one click',async()=>{
  const e=environment();
  let observations=0;
  e.afterNew=()=>{
    e.s.composerID='compose';
    e.duringRead=()=>{if (++observations===3) e.s.composerID='fresh'};
  };
  const run=await e.start();
  assert.ok(observations>=3);assert.deepEqual(e.events,['new']);assert.deepEqual(e.keys,[]);
  assert.equal(await run.close(),'closed');
});

test('route, signed-in state and native focus changes retire the wait before another page read',async()=>{
  for (const alter of [
    e=>{e.s.route='https://chatgpt.com/?temporary-chat=true'},
    e=>{e.s.signedIn=false},
    e=>{e.s.selectedTabID='99'},
  ]) {
    const e=environment();
    let reads=0;e.afterNew=()=>{e.s.composerID='compose';alter(e);e.duringRead=()=>{reads++}};
    await assert.rejects(e.start());
    assert.ok(reads<=1);assert.equal(e.closes,0);assert.deepEqual(e.events,['new']);assert.deepEqual(e.keys,[]);
  }
});

test('an unresolved post-click page read times out without another read or unsafe cleanup',async()=>{
  const e=environment(),original=e.options.read;
  let after=false,reads=0;e.afterNew=()=>{after=true};
  e.options.read=async tab=>{
    if (!after) return original(tab);
    reads++;return new Promise(()=>{});
  };
  await assert.rejects(e.start(),err=>/no observable fresh draft/.test(err.message) && err.cleanup==='retainedUnverified');
  assert.equal(reads,1);assert.equal(e.closes,0);assert.deepEqual(e.events,['new']);assert.deepEqual(e.keys,[]);
});


test('AX-only tab delivers the seed and selection to the already focused editor', async () => {
  const e = environment();
  delete e.tab.cua;
  const sent = [];
  e.tab.ax = {pressKey: async (index, key) => {
    assert.equal(index, null);
    assert.equal(e.s.focusedOriginalEditor, true);
    sent.push(key);
    if (key === 'shift+Left') e.s.selection = e.s.text.slice(-1);
    else { assert.match(key, /^[a-z0-9]$/); e.s.text += key; }
  }};
  const run = await e.start();
  const result = await run.seed();
  assert.deepEqual(sent, [...result.text, 'shift+Left']);
  assert.equal(result.selection, result.text.slice(-1));
});

test('a lost AX reply spends the seed with no alternate keyboard dispatch', async () => {
  const e = environment();
  let attempts = 0;
  e.tab.ax = {pressKey: async () => { attempts++; throw Error('lost AX reply'); }};
  const run = await e.start();
  await assert.rejects(run.seed(), /lost AX reply/);
  await assert.rejects(run.seed(), /consumed/);
  assert.equal(attempts, 1);
  assert.equal(e.keys.length, 0);
});
