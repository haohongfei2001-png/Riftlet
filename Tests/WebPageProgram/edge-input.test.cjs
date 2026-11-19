'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture,native,png}=require('./independent-input-fixture.cjs');

test('Edge appends two independent files on the shared program without borrowing preview START',async()=>{
 const f=fixture({nativeContext:{...native,applicationID:'com.microsoft.edgemac',sessionID:'edge-kernel-v1:7:10:1'}});
 const text=f.editor.textContent,anchor=f.selection.anchorNode,focus=f.selection.focusNode;
 const operations=[];
 for(let index=0;index<2;index++){
  const op=f.bind(); operations.push(op); f.stage(op);
  const result=(await f.commit(op)).observation;
  assert.equal(result.state,'inputTriggered');
  assert.equal(result.uploadStart,undefined);
  assert.equal(result.belongsToOriginalDraft,true);
  assert.equal(f.setters,index+1); assert.equal(f.changes,index+1);
  assert.deepEqual(Buffer.from(await f.input.files[0].arrayBuffer()),png);
  assert.equal(f.input.files[0].name,op.name);
 }
 assert.notEqual(operations[0].identity.operationID,operations[1].identity.operationID);
 assert.equal(f.form.querySelectorAll('[data-file-name]').length,3);
 for(const op of operations){
  assert.equal(f.observe(op).state,'inputTriggered');
  assert.equal(f.observe(op).uploadStart,undefined);
 }
 assert.equal(f.editor.textContent,text);assert.equal(f.selection.anchorNode,anchor);assert.equal(f.selection.focusNode,focus);
 assert.equal(f.selection.anchorOffset,2);assert.equal(f.selection.focusOffset,7);
 assert.ok(f.form.contains(f.oldCard));assert.equal(f.sends,0);assert.equal(f.chooserOpens,0);
});

test('a native host outside the exact Chrome and Edge set never captures a target',()=>{
 for(const applicationID of ['com.other.browser','com.microsoft.edgemac.beta']){
  const f=fixture({nativeContext:{...native,applicationID}});
  assert.throws(()=>f.bind());assert.equal(f.setters,0);assert.equal(f.changes,0);
 }
});
