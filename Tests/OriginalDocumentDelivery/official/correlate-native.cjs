'use strict';
// Join independent native readings only after the browser-side result. This
// command does not launch/access a browser or infer a PID from a web page.
const assert=require('node:assert/strict');
const crypto=require('node:crypto'),fs=require('node:fs'),path=require('node:path');
const [dir,family,beforeFile,afterFile]=process.argv.slice(2);
const bundle={chrome:'com.google.Chrome',edge:'com.microsoft.edgemac'}[family];
assert.ok(bundle&&dir&&beforeFile&&afterFile,'usage: node correlate-native.cjs <evidence dir> chrome|edge <A-sample.json> <B-sample.json>');
const load=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const receipt=path.join(dir,family+'.json'),run=load(receipt);
assert.equal(run.family,family);assert.equal(run.phase,'done');assert.equal(run.status,'PASS');
assert.equal(run.routeChecks.length,2);
const boundary=run.firstWitnessBoundary;
const first=load(beforeFile),next=load(afterFile);
assert.equal(first.doc,boundary.originalDocument);assert.equal(next.doc,boundary.replacementDocument);
assert.notEqual(first.doc,next.doc);assert.equal(first.bundle,bundle);
const session=new RegExp('^'+family+'-kernel-v1:([1-9]\\d*):([1-9]\\d*):(\\d{1,6})$');
assert.match(first.sessionID,session);assert.match(first.windowID,/^[1-9]\d*$/);assert.match(first.tabID,/^[1-9]\d*$/);
for(const key of ['bundle','sessionID','windowID','tabID'])assert.equal(first[key],next[key]);
const utc=value=>{const t=Date.parse(value);assert.ok(Number.isFinite(t));return t;};
const barrier=utc(run.events.find(e=>e.kind==='barrier').utc);
assert.ok(utc(run.createdUTC)<=utc(first.observedUTC) && utc(first.observedUTC)<=barrier);
assert.ok(utc(next.observedUTC)>=barrier && utc(next.observedUTC)>utc(first.observedUTC));
function fields(s) {return {doc:s.doc,observedUTC:s.observedUTC,bundle:s.bundle,sessionID:s.sessionID,windowID:s.windowID,tabID:s.tabID};}
const result={family,status:'MATCH',scope:'join of independently collected original native target and page identity samples',
  sourceSHA256:run.sourceSHA256,
  browserReceiptSHA256:crypto.createHash('sha256').update(fs.readFileSync(receipt)).digest('hex'),
  A:fields(first),B:fields(next),firstWitnessBoundary:{...boundary,nativeCorrelation:'MATCH'}};
const out=path.join(dir,family+'-native.json');
fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n',{flag:'wx',mode:0o600});
console.log(out);
