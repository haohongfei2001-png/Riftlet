const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
for (const version of [13]) test('v'+version+' probe preserves batch history, redacts source, logs only original image and cleans own listeners',()=>{
 const events=new Map();let callback,visible=false,value=null,detached=false,disconnected=0,cleared=0;
 const secret='PRIVATE_DATA_NEVER_EXPORT',id='11111111-2222-4333-8444-555555555555';
 const progress={getAttribute:k=>k==='aria-valuenow'?value:k==='aria-label'?'正在上传 '+secret:'progressbar'};
 const image={alt:secret,complete:true,naturalWidth:2,naturalHeight:1,src:'data:image/png;base64,'+secret};
 const card={getAttribute:()=>secret,querySelectorAll:k=>k==='img'?[image]:detached?[]:[progress],contains:n=>n===image||n===progress&&!detached};
 const form={querySelectorAll:()=>visible?[card]:[]},input={files:[{name:secret,size:10,type:'image/png'}]};
 const op={identity:{assetID:id},name:secret,bytes:10,inputCount:0,inputSequence:0,committed:false};
 const context=vm.createContext({['__riftletWebAcceptance20261027v'+version]:{head:{form,input,operations:new Map([['op',op]])}},performance:{now:()=>12},
 document:{addEventListener:(k,fn)=>events.set(k,fn),removeEventListener:(k,fn)=>{assert.equal(events.get(k),fn);events.delete(k);}},
 MutationObserver:class{constructor(fn){callback=fn;}observe(){}disconnect(){disconnected++;}},setTimeout:()=>1,clearTimeout:()=>cleared++});
 const install=vm.runInContext('('+fs.readFileSync(require('node:path').join(__dirname,'v'+version+'-progress-diagnostic-probe.js'),'utf8')+')',context);
 assert.equal(install({assetID:id}).installed,true);op.committed=true;op.inputCount=1;op.inputSequence=2;events.get('change')({target:input});
 visible=true;callback([{type:'childList',target:form,addedNodes:[card],removedNodes:[]}]);
 value='100';detached=true;callback([{type:'attributes',target:progress,attributeName:'aria-valuenow',oldValue:null},{type:'childList',target:card,removedNodes:[progress],addedNodes:[]}]);
 events.get('load')({type:'load',target:image});events.get('error')({type:'error',target:{}});
 const api=context['__riftletSC2V'+version+'ProgressProbe'],q=api.query(),records=q.events.filter(e=>e.batchID===2);
 assert.ok(records.some(e=>e.event==='progress_attribute'&&e.oldValueKind==='missing'&&e.value===100&&!e.underOriginalCard));
 assert.ok(records.some(e=>e.event==='original_progress_membership'&&e.removed));
 const load=q.events.find(e=>e.event==='original_image_load');assert.equal(load.sourceKind,'data-png');assert.equal(load.complete,true);assert.equal(load.batchID,null);
 assert.equal(JSON.stringify(q).includes(secret),false);assert.equal(q.events.some(e=>e.event==='original_image_error'),false);
 api.stop();assert.equal(events.size,0);assert.equal(disconnected,1);assert.equal(cleared,1);
});
