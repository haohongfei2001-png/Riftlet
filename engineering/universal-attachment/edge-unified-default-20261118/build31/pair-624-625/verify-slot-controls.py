"""Real DOM, offline QA-observer verification. All windows, files, names, account scope and route are synthetic."""
import json, subprocess,tempfile,sys,html,re,hashlib,gzip
from pathlib import Path
here=Path(__file__).resolve().parent
base=(here/'semantics/observer.js').read_text()
with tempfile.TemporaryDirectory(prefix='riftlet-slot-patch-') as patchdir:
 patchdir=Path(patchdir); (patchdir/'semantics').mkdir()
 (patchdir/'semantics/observer.js').write_text(base)
 patch=gzip.decompress((here/'next-observation.patch.gz').read_bytes())
 subprocess.run(['patch','-s','-p1'],cwd=patchdir,input=patch,check=True)
 candidate=(patchdir/'semantics/observer.js').read_text()
assert hashlib.sha256(candidate.encode()).hexdigest()=='0aa1ffeb9fce2466bd9ee4dd094236433e059c2d6a87f490323011fa32884ea5'
assert hashlib.sha256(base.encode()).hexdigest()=='bb7a4c56a56222d5dfbd4a11d60dc2ec126d5ffdd73d245dd334dae8dfba850d'
fixture=re.search(r'e\.textContent==="([^"]+)"',base)[1]
suite=r"""
(async()=>{
const testText=FIXTURE_TEXT, locationFixture={href:'https://chatgpt.com/?temporary-chat=true'}, navigationFixture={currentEntry:{id:'fixture'}};
const previous=new Function('location','navigation','return ('+BASE+')')(locationFixture,navigationFixture);
const candidate=new Function('location','navigation','return ('+CANDIDATE+')')(locationFixture,navigationFixture);
const output=[],flush=()=>new Promise(r=>setTimeout(r,0));
const node=(tag,atts={})=>{const e=document.createElement(tag);for(const [k,v] of Object.entries(atts))e.setAttribute(k,v);return e;};
async function trial(mode) {
 const f=node('form'),editor=node('div',{contenteditable:'true'});editor.textContent=testText;f.append(editor);document.body.append(f);
 function tray(){const el=node('div');const prior=node('button',{'aria-label':'prior.png'});el.append(prior);f.append(el);return el;}
 const left=tray(),right=tray();const name='riftlet-AAAA0000-0000-4000-8000-000000000000.png';
 const ref={f,e:editor,document,n:'fixture',interactions:()=>0},states=[previous,candidate].map((fn,i)=>({fn,plan:{seeds:[1],baseline:['prior.png'],ticket:mode+i}}));
 for(const {fn,plan} of states){if(fn(ref,'arm',plan,[]).status!=='ARMED')throw Error('not armed');fn(ref,'bind',plan,[[1,name]]);}
 const make=(next,declared)=>{
   const card=node('div'),remove=node('button',{'aria-label':'Remove '+name});
   if(next){const popup=node('div',{'aria-label':name});popup.append(node('img',{alt:name}));card.append(popup);}
   else{const label=node('span',{'aria-label':name});label.append(node('span',{role:'progressbar','aria-valuenow':'5'}));card.append(label);}
   if(declared)card.setAttribute('data-status',declared);
   card.append(remove);return card;
 };
 const old=make(false),marker=node('span');left.append(old,marker);await flush();
 const bar=old.querySelector('[role=progressbar]');bar.setAttribute('aria-valuenow','23');await flush();
 bar.setAttribute('role','status');await flush();
 const next=make(true,mode==='processing'?'processing':mode==='failed'?'failed':null);
 if(mode==='intermediateABA'){old.remove();left.insertBefore(old,marker);await flush();}
 if(mode==='atomic'||mode==='intermediateABA'||mode==='processing'||mode==='failed')old.replaceWith(next);
 if(mode==='splitSameTurn'){old.remove();left.insertBefore(next,marker);}
 if(mode==='differentParent'){old.remove();right.append(next);}
 if(mode==='gap'){old.remove();await flush();left.insertBefore(next,marker);}
 if(mode==='competingEdit'){const temp=node('span');left.append(temp);temp.remove();old.replaceWith(next);}
 if(mode==='movedSlot'){old.remove();left.append(next);}
 if(mode==='foreignClaim'){next.firstChild.append(node('span',{title:'other-image.png'}));old.replaceWith(next);}
 await flush();
 const [a,b]=states.map(({fn,plan})=>fn(ref,'close',plan,[]).files[0]);
 // Compare the entire original output event sequence, removing only clock readings.
 const oldProjection={seen:a.seen,truncated:a.truncated,events:a.events.map(([,field,value])=>[field,value])};
 const qa=b.slotAudit;if(!qa || qa.fileHandleCompared||qa.operationReceiptCreated||qa.limited)throw Error('scope or bounds');
 const kinds=qa.changes.map(x=>x.kind);const expected={atomic:'oneForOneFormDOMEdit',splitSameTurn:'multiRecordOrMissingEdit',differentParent:'differentParent',gap:'appearedAfterGap',intermediateABA:'continuityUncertain',competingEdit:'multiRecordOrMissingEdit',movedSlot:'differentSlotOrNeighbors',foreignClaim:'originalNoLongerUniquelyVisible',processing:'oneForOneFormDOMEdit',failed:'conflictingProcessingState'}[mode];
 if(kinds.at(-1)!==expected)throw Error(mode+' '+JSON.stringify(qa));
 if(mode==='atomic'){
   const c=qa.changes[0],record=c.records[0];if(c.deliveryRecords!==1||c.before.parent!==c.after.parent||c.before.slot!==c.after.slot||record.target!==c.before.parent||record.removed[0]!==c.before.root||record.added[0]!==c.after.root||record.previous!==c.before.previous||record.next!==c.after.next)throw Error('slot projections');
 }
 if(qa.last && qa.last.processing!==(mode==='processing'?'processing':mode==='failed'?'failed':'unreported'))throw Error('processing');
 if(JSON.stringify(qa).includes(name)||JSON.stringify(qa).includes(testText))throw Error('private payload');
 output.push({mode,kinds,oldProjection});f.remove();
}
try{
 for(const mode of ['atomic','splitSameTurn','differentParent','gap','intermediateABA','competingEdit','movedSlot','foreignClaim','processing','failed'])await trial(mode);
 const original=JSON.stringify(output[0].oldProjection);
 const same=output.filter(x=>JSON.stringify(x.oldProjection)===original).map(x=>x.mode);
 if(!['splitSameTurn','differentParent','competingEdit','intermediateABA'].every(m=>same.includes(m)))throw Error('counterexample invalid');
 document.getElementById('result').textContent=JSON.stringify({status:'PASS',scope:'isolated native headless DOM / synthetic fixture; no service, no original input',cases:output.map(({mode,kinds})=>({mode,kinds})),identicalCompleteOriginalEventSequenceExceptClock:same});
}catch(e){document.getElementById('result').textContent=JSON.stringify({status:'FAIL',reason:String(e).slice(0,1500)});}
})();
"""
suite=suite.replace('FIXTURE_TEXT',json.dumps(fixture)).replace('+BASE+','+'+json.dumps(base)+'+').replace('+CANDIDATE+','+'+json.dumps(candidate)+'+')
binary=Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
with tempfile.TemporaryDirectory(prefix='riftlet-625-native-slot-') as d:
 d=Path(d);page=d/'native.html';page.write_text('<!doctype html><meta charset="UTF-8"><pre id="result">RUNNING</pre><script>'+suite+'</script>')
 cmd=[str(binary),'--headless=new','--user-data-dir='+str(d/'temp-profile'),'--no-first-run','--no-default-browser-check','--disable-extensions','--disable-sync','--disable-background-networking','--disable-component-update','--host-resolver-rules=MAP * ~NOTFOUND','--dump-dom','--virtual-time-budget=8000',page.as_uri()]
 result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=25)
 body=re.search(r'<pre id="result">(.*?)</pre>',result.stdout.decode(),re.S)
 if not body:raise RuntimeError('missing offline fixture result')
 receipt=json.loads(html.unescape(body[1]));print(json.dumps(receipt,indent=2,ensure_ascii=False));sys.exit(receipt['status']!='PASS')
