/* Design-model regressions only: never imports or exercises Riftlet native code. */
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {Model,fit,slots}=require('./model.js');
const passed=[];
function test(name,fn){fn();passed.push(name);}
test('arrival preserves original aspect ratio and exposes a visible pad for extreme ratios',()=>{
  const a=fit(300,2400),b=fit(2400,300);assert.equal(a.width/a.height,1/8);assert.equal(b.width/b.height,8);assert.equal(a.pad,true);assert.equal(b.pad,true);
});
test('no target and no original authorization cannot create input',()=>{
  const m=new Model(),a=m.add();assert.equal(m.select(a.id,{validTarget:false}).ok,false);assert.equal(m.select(a.id,{ack:false}).ok,false);assert.equal(m.inputCount,0);assert.equal(a.visible,true);
});
test('start is not completion; visual exit alone keeps the operation uploading',()=>{
  const m=new Model(),a=m.add();m.select(a.id);assert.equal(m.swallow(a.id),false);m.start(a.id,m.token(a.id));m.swallow(a.id);assert.equal(a.status,'uploading');assert.equal(a.visible,false);assert.equal(m.inputCount,1);
});
test('stale selection token cannot start a later selection on the same asset',()=>{
  const m=new Model(),a=m.add();m.select(a.id);const old=m.token(a.id);m.cancel(a.id);m.select(a.id);assert.equal(m.start(a.id,old),false);assert.equal(a.status,'waiting');assert.equal(m.inputCount,0);
});
test('FIFO cancellation promotes the next original selection without creating input',()=>{
  const m=new Model(),a=m.add(),b=m.add();m.select(a.id);m.select(b.id);m.hide(a.id);assert.equal(m.active,b.id);assert.equal(m.inputCount,0);assert.equal(b.status,'waiting');assert.equal(m.start(b.id,m.token(b.id)),true);
});
test('UNKNOWN cannot rebirth, restore or unlock the same draft; another target remains independent',()=>{
  const m=new Model(),a=m.add(),b=m.add(),c=m.add();m.select(a.id,{target:'A'});m.start(a.id);m.finish(a.id,'unknown');assert.equal(m.finish(a.id,'failure'),false);assert.equal(m.restore(a.id),false);m.select(b.id,{target:'A'});assert.equal(m.start(b.id),false);m.cancel(b.id);m.select(c.id,{target:'B'});assert.equal(m.start(c.id),true);assert.equal(a.status,'unknown');
});
test('a stale completion token cannot finish a later synthetic attempt',()=>{
  const m=new Model(),a=m.add();m.select(a.id);m.start(a.id);const old=m.token(a.id);m.finish(a.id,'failure',old);m.select(a.id);m.start(a.id);assert.equal(m.finish(a.id,'success',old),false);assert.equal(a.status,'uploading');
});
test('slot identities are frozen in the returned session mapping',()=>{
  const windowSession=slots('window');slots('region');assert.deepEqual(windowSession,['window','region','full','more']);assert.deepEqual(slots('full'),['full','region','window','more']);
});
const result={scope:'synthetic-design-model-only',passed:passed.length,failed:0,checks:passed};
fs.writeFileSync(path.join(__dirname,'model-verification.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result,null,2));
