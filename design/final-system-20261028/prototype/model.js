/* Synthetic design model only. No files, browser APIs, real adapters or persistence. */
(function(root){
  'use strict';
  const shapes={landscape:[1600,900],portrait:[900,1600],long:[300,2400],wide:[2400,300],square:[1000,1000]};
  function fit(width,height){const k=Math.min(72/width,56/height);const w=width*k,h=height*k;return{width:w,height:h,exposed:w*.75,pad:w*.75<24||h<20};}
  function capacity(height,count){const first=230,bottom=height-78;const base=Math.max(1,Math.floor((bottom-28-first)/60)+1);return count>base?Math.max(1,Math.floor((bottom-28-28-first)/60)+1):base;}
  function slots(defaultMode){return defaultMode==='full'?['full','region','window','more']:defaultMode==='region'?['region','window','full','more']:['window','region','full','more'];}
  function quint(t){t=Math.max(0,Math.min(1,t));return t*t*t*(t*(t*6-15)+10);}
  function outCubic(t){t=Math.max(0,Math.min(1,t));return 1-Math.pow(1-t,3);}
  class Model{
    constructor(){this.assets=[];this.next=1;this.revision=0;this.events=[];this.sequence=0;this.inputCount=0;this.active=null;this.pending=[];}
    log(type,id,detail){this.events.push({n:++this.sequence,type,id,detail:detail||'',time:Date.now()});}
    add(kind='landscape'){const wh=shapes[kind]||shapes.landscape;const a={id:'SIM-'+String(this.next).padStart(3,'0'),number:this.next++,kind,width:wh[0],height:wh[1],visible:true,status:'available',createdAt:Date.now(),attempts:0};this.assets.push(a);this.revision++;this.log('assetReady',a.id,'合成资产立即可点击');return a;}
    find(id){return this.assets.find(a=>a.id===id);}
    token(id){const a=this.find(id);return a?{id:a.id,selection:a.selection,attempts:a.attempts,target:a.target}:null;}
    matches(id,t){const a=this.find(id);return !!a&&!!t&&a.id===t.id&&a.selection===t.selection&&a.attempts===t.attempts&&a.target===t.target;}
    visible(){return this.assets.filter(a=>a.visible);}
    select(id,{validTarget=true,ack=true,outcome='success',target='SIM-DRAFT-1'}={}){const a=this.find(id);if(!a||!a.visible)return{ok:false,reason:'stale'};if(a.status==='unknown')return{ok:false,reason:'unknown'};if(a.status!=='available')return{ok:false,reason:'busy'};if(!validTarget){this.log('selectionRejected',id,'没有可用的当前草稿；未输入');return{ok:false,reason:'target'};}if(!ack){this.log('selectionRejected',id,'没有原点击授权；未输入');return{ok:false,reason:'ack'};}a.status='waiting';a.outcome=outcome;a.target=target;a.startScheduled=false;a.selection=++this.sequence;this.pending.push(id);this.log('prepared',id,'原选择已接受；尚未输入');if(!this.active)this.active=this.pending.shift();return{ok:true,active:this.active===id};}
    start(id,token){const a=this.find(id);if(!a||id!==this.active||a.status!=='waiting'||(token&&!this.matches(id,token))||this.assets.some(x=>x.status==='unknown'&&x.target===a.target))return false;a.status='uploading';a.attempts++;a.started=true;this.inputCount++;this.log('uploadStarted',id,'合成严格开始信号；唯一输入计数 +1');return true;}
    swallow(id){const a=this.find(id);if(!a||!a.started||!['uploading','unknown','succeeded'].includes(a.status))return false;a.visible=false;this.revision++;this.log('visualExit',id,'仅退出可见队列；尚不推导完成');return true;}
    finish(id,outcome,token){const a=this.find(id);if(!a||!a.started||!['uploading','unknown'].includes(a.status)||(token&&!this.matches(id,token))||(a.status==='unknown'&&outcome!=='success'))return false;if(outcome==='unknown'){a.status='unknown';a.visible=false;this.log('unknown',id,'只读观察原操作；不重生、不重传');}else if(outcome==='failure'){a.status='available';a.started=false;a.visible=true;this.log('admittedFailureDemo',id,'未来条件状态，仅合成；允许下一次用户新点击');}else{a.status='succeeded';a.visible=false;this.log('succeeded',id,'后台记录；无成功Toast');}this.revision++;if(id===this.active){this.active=null;this.active=this.pending.shift()||null;}return true;}
    cancel(id){const a=this.find(id);if(!a||a.status!=='waiting')return false;a.status='available';a.startScheduled=false;this.pending=this.pending.filter(x=>x!==id);if(this.active===id)this.active=this.pending.shift()||null;this.log('cancelledBeforeInput',id,'撤销原选择；未开始输入');return true;}
    hide(id,reason='removed'){const a=this.find(id);if(!a||!a.visible)return false;if(a.status==='waiting')this.cancel(id);a.visible=false;if(a.status==='available')a.status=reason;this.revision++;this.log(reason,id,'仅改变本地可见性，原图及草稿附件保留');return true;}
    clear(){for(const a of this.visible())this.hide(a.id);}
    restore(id){const a=this.find(id);if(!a||!['removed','archived'].includes(a.status)||a.started)return false;a.visible=true;a.status='available';this.revision++;this.log('restored',id,'未输入过的合成截图恢复可见');return true;}
  }
  const api={Model,fit,capacity,slots,quint,outCubic,shapes};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.RiftletModel=api;
})(typeof window!=='undefined'?window:this);
