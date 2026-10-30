'use strict';
const assert=require('node:assert/strict');
const Model=require('../source/model.js');
const results=[];
function test(name, fn){try{fn();results.push({name,pass:true});}catch(error){results.push({name,pass:false,error:error.message});}}
function begin(m,scenario='success',id=1){const t=m.request(id,scenario);assert.ok(t);return t;}
test('request is not upload start',()=>{const m=new Model();begin(m);assert.equal(m.items[0].visible,true);assert.equal(m.items[0].state,'pending');assert.equal(m.items[0].card,false);});
test('duplicate clicks dispatch once',()=>{const m=new Model();begin(m);assert.equal(m.request(1),null);assert.equal(m.items[0].inputs,1);});
test('positive start hides before final readiness',()=>{const m=new Model();const t=begin(m);m.signal(t,'positive-start');assert.equal(m.items[0].visible,false);assert.equal(m.items[0].state,'started');assert.equal(m.items[0].card,true);m.signal(t,'ready');assert.equal(m.items[0].state,'ready');assert.equal(m.request(1),null);});
test('explicit failure returns ordinary clickable image',()=>{const m=new Model();const t=begin(m,'failure');m.signal(t,'positive-start');m.signal(t,'failure');assert.equal(m.items[0].visible,true);assert.equal(m.items[0].card,false);assert.ok(m.request(1));assert.equal(m.items[0].inputs,2);});
test('unknown stays hidden and cannot be retried',()=>{const m=new Model();const t=begin(m,'unknown');m.signal(t,'positive-start');m.signal(t,'unknown');assert.equal(m.items[0].visible,false);assert.equal(m.items[0].state,'unknown');assert.equal(m.request(1),null);assert.equal(m.items[0].inputs,1);});
test('no start keeps image and adds no card',()=>{const m=new Model();const t=begin(m,'no-start');m.signal(t,'no-start');assert.equal(m.items[0].state,'blocked');assert.equal(m.items[0].visible,true);assert.equal(m.items[0].card,false);assert.ok(m.request(1));});
test('reset invalidates stale callback',()=>{const m=new Model();const t=begin(m);m.reset();assert.equal(m.signal(t,'positive-start'),false);assert.equal(m.items[0].state,'available');});
test('wrong synthetic target is rejected',()=>{const m=new Model();const t=begin(m);assert.equal(m.signal({...t,target:'another-draft'},'positive-start'),false);assert.equal(m.items[0].visible,true);});
test('old attempt cannot complete a new attempt',()=>{const m=new Model();const t=begin(m);m.signal(t,'positive-start');m.signal(t,'failure');begin(m);assert.equal(m.signal(t,'ready'),false);assert.equal(m.items[0].state,'pending');});
test('completion without positive start is rejected',()=>{const m=new Model();const t=begin(m);assert.equal(m.signal(t,'ready'),false);assert.equal(m.items[0].visible,true);});
test('user removal is not an upload failure',()=>{const m=new Model();const t=begin(m);m.signal(t,'positive-start');m.removeCard(1);m.signal(t,'ready');assert.equal(m.items[0].card,false);assert.equal(m.items[0].visible,false);assert.equal(m.request(1),null);});
test('late failure does not reverse explicit removal',()=>{const m=new Model();const t=begin(m);m.signal(t,'positive-start');m.removeCard(1);m.signal(t,'failure');assert.equal(m.items[0].visible,false);});
test('unknown image does not block other image',()=>{const m=new Model();const t=begin(m,'unknown');m.signal(t,'positive-start');m.signal(t,'unknown');const other=begin(m,'success',2);m.signal(other,'positive-start');m.signal(other,'ready');assert.equal(m.items[1].state,'ready');assert.equal(m.items[0].state,'unknown');});
test('visible queue cap does not count hidden history',()=>{const m=new Model();assert.equal(m.add(),null);const t=begin(m);m.signal(t,'positive-start');assert.ok(m.add());assert.equal(m.items.filter(x=>x.visible).length,3);});
test('each thumbnail preserves source aspect ratio',()=>{const m=new Model();for(const x of m.items){const parts=x.view.split(' ').map(Number);assert.ok(Math.abs(x.w/x.h-parts[2]/parts[3])<1e-8);assert.ok(Math.abs(x.lw/x.lh-parts[2]/parts[3])<1e-8);}});
console.log(JSON.stringify({tests:results.length,passed:results.filter(x=>x.pass).length,results},null,2));
if(results.some(x=>!x.pass))process.exitCode=1;
