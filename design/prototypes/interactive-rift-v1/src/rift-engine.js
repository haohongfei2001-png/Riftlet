/* Riftlet interface reconstruction, pinned to 485fa87.
 * Geometry and native UI transition logic: RiftConfiguration, RiftLayout,
 * RiftPanelController. The browser cannot prove macOS focus/Spaces/window hits.
 * The lower synthetic-transport section is a review tool, NOT a production
 * adapter, and makes no network calls. No credentials or private content.
 */
(function (global) {
  'use strict';
  const C = Object.freeze({fitWidth:72,fitHeight:56,hiddenFraction:.25,rowPitch:60,
    lineWidth:.7,lineExtension:8,emptyTraceLength:24,outerInset:8,
    firstCenterFromTop:180,screenPadding:12,numberFontSize:11,numberGap:6,
    leftPadding:4,minimumHitWidth:44,minimumHitHeight:44,
    arrivalDuration:220,pressDuration:80,inwardDistance:2.5,
    swallowDuration:240,shiftDuration:180,returnDuration:180,reducedMotionDuration:100});
  const STATUSES = {pending:'待附加',transferring:'附件处理中',unknown:'结果未知，保留',failed:'失败，保留',used:'已确认附件完成'};
  const OUTCOMES = ['success','failure','waiting','unknown','target-change','capture-during','native-disabled'];
  const point = (x,y,width,height) => ({x,y,width,height});
  function fit(width,height) {
    if (!(width>0&&height>0)) return {width:0,height:0};
    const ratio=Math.min(C.fitWidth/width,C.fitHeight/height);
    return {width:width*ratio,height:height*ratio};
  }
  // Literal geometry port; CSS y grows downwards, AppKit's y grows upwards.
  function layout(records,width,height,insets={top:25,bottom:76},firstVisibleIndex=0) {
    const active=records.filter(r=>r.status!=='used');
    const top=Number(insets.top)||0, bottom=height-(Number(insets.bottom)||0);
    const rowHeight=Math.max(C.fitHeight,C.minimumHitHeight);
    const pitch=Math.max(C.rowPitch,rowHeight+4);
    const available=Math.max(0,bottom-top-2*C.screenPadding);
    const capacity=available>=rowHeight?Math.max(1,Math.floor((available-rowHeight)/pitch)+1):0;
    const index=Math.min(Math.max(0,firstVisibleIndex),Math.max(0,active.length-capacity));
    const count=Math.min(capacity,Math.max(0,active.length-index));
    const metrics=active.slice(index,index+count).map((record,offset)=>{
      const ordinal=index+offset+1, fitted=fit(record.width,record.height);
      const exposed=fitted.width*(1-C.hiddenFraction);
      const numberWidth=String(ordinal).length*C.numberFontSize*.65;
      return {record,ordinal,fitted,exposed,numberWidth,
        width:Math.max(C.minimumHitWidth,exposed+C.numberGap+numberWidth+C.leftPadding),
        height:Math.max(C.minimumHitHeight,fitted.height)};
    });
    const edgeX=Math.max(Math.min(width,Math.max(0,...metrics.map(m=>m.width))),width-C.outerInset);
    const topLimit=top+C.screenPadding+rowHeight/2;
    const bottomLimit=bottom-C.screenPadding-rowHeight/2;
    const preferred=top+C.firstCenterFromTop;
    const firstCenter=Math.max(topLimit,Math.min(preferred,bottomLimit-Math.max(0,count-1)*pitch));
    const rows=metrics.map((m,offset)=>{
      const center=firstCenter+offset*pitch;
      const imageX=m.width-m.exposed,imageY=(m.height-m.fitted.height)/2;
      const numberFrame=point(imageX-C.numberGap-m.numberWidth,m.height/2-C.numberFontSize/2-1,m.numberWidth,C.numberFontSize+2);
      return {assetID:m.record.id,ordinal:m.ordinal,
        frame:point(edgeX-m.width,center-m.height/2,m.width,m.height),
        imageFrame:point(imageX,imageY,m.fitted.width,m.fitted.height),
        imageClipFrame:point(imageX,imageY,m.exposed,m.fitted.height),numberFrame,
        underlineFrame:point(numberFrame.x+numberFrame.width-Math.min(8,numberFrame.width),
          m.height-(numberFrame.y-2+.7),Math.min(8,numberFrame.width),.7)};
    });
    let lineTop,lineBottom;
    if(rows.length){lineTop=rows[0].frame.y-C.lineExtension;const f=rows[rows.length-1].frame;lineBottom=f.y+f.height+C.lineExtension;}
    else{const center=Math.max(topLimit,Math.min(bottomLimit,preferred));lineTop=center-C.emptyTraceLength/2;lineBottom=center+C.emptyTraceLength/2;}
    lineTop=Math.max(top,lineTop);lineBottom=Math.min(bottom,lineBottom);
    return {rows,lineFrame:point(edgeX-C.lineWidth/2,lineTop,C.lineWidth,Math.max(0,lineBottom-lineTop)),
      firstVisibleIndex:index,capacity,totalCount:active.length,hasEarlier:index>0,hasLater:index+rows.length<active.length};
  }
  function rectStyle(el,r) {
    el.style.left=r.x+'px';el.style.top=r.y+'px';el.style.width=r.width+'px';el.style.height=r.height+'px';
  }
  function publicAsset(record) {
    return {id:record.id,label:record.label,width:record.width,height:record.height,src:record.src};
  }

  class RiftEngine {
    constructor(options) {
      if(!options||!options.layer)throw new Error('RiftEngine requires a layer element');
      this.layer=options.layer;this.width=options.width||1440;this.height=options.height||900;
      this.insets={top:25,bottom:76,...options.insets};
      this.getTarget=options.getTarget||(()=> 'thread-1');
      this.onEvent=options.onEvent||(()=>{});this.onState=options.onState||(()=>{});
      this.records=[];this.views=new Map();this.operations=new Map();this.dispatchQueue=[];this.targetLocks=new Map();
      this.index=0;this.transitioning=false;this.held=null;this.previousPointer=null;this.deferred=false;
      this.followTail=false;this.scrollAccumulator=0;this.uiGeneration=0;this.generation=0;
      this.timers=new Set();this.outcome='success';this.latency=1350;this.reducedMotion=false;
      this.theme='light';this.hitAreas=false;this.counter=0;this.eventCounters={};this.dispatching=false;
      this.lastOperationID=null;this.activeDispatchID=null;this.phase='idle';this.lastEvent=null;
      this.layer.classList.add('rift-engine-layer');this.layer.dataset.theme='light';
      this.seam=document.createElement('div');this.seam.className='rift-seam';this.seam.setAttribute('aria-hidden','true');
      this.layer.appendChild(this.seam);this._apply(false);
    }
    static get configuration(){return C;}
    static fit(width,height){return fit(width,height);}
    static layout(records,width,height,insets,index){return layout(records,width,height,insets,index);}
    _duration(normal){return this.reducedMotion?Math.min(normal,C.reducedMotionDuration):normal;}
    _later(callback,ms,op=null,ui=false){
      const generation=this.generation,uiGeneration=this.uiGeneration;
      const id=setTimeout(()=>{
        this.timers.delete(id);if(op)op.timers.delete(id);
        if(this.generation!==generation||(ui&&this.uiGeneration!==uiGeneration))return;
        callback();
      },Math.max(0,ms));
      this.timers.add(id);if(op)op.timers.add(id);return id;
    }
    _clearTimers(op){for(const id of op.timers){clearTimeout(id);this.timers.delete(id);}op.timers.clear();}
    _emit(type,record,op,message,extra={}){
      this.eventCounters[type]=(this.eventCounters[type]||0)+1;
      const event={type,asset:record?publicAsset(record):null,target:op?op.target:null,
        operationID:op?op.id:null,status:record?record.status:null,message,
        time:Date.now(),elapsed:Math.round(performance.now()),...extra};
      this.lastEvent={...event,asset:event.asset?{id:event.asset.id,label:event.asset.label}:null};
      this.onEvent(event);return event;
    }
    _notify(){this.onState(this.snapshot());}
    _record(asset){
      if(!asset||!asset.id||!asset.src||!(asset.width>0)||!(asset.height>0))throw new Error('Invalid synthetic screenshot');
      return {...asset,status:'pending',operationID:null,progress:0,offset:0};
    }
    add(asset){
      if(this.records.some(r=>r.id===asset.id))return false;
      const hadRecords=this.records.length>0;
      this.records.push(this._record(asset));this.followTail=this.followTail||hadRecords;
      this._emit('capture',this.records[this.records.length-1],null,'合成截图已收录');this._render();return true;
    }
    populate(assets){
      this.clear(false);const seen=new Set();
      for(const asset of assets){if(!seen.has(asset.id)){this.records.push(this._record(asset));seen.add(asset.id);}}
      this._render();this._emit('populate',null,null,'已设置合成队列',{count:this.records.length});this._notify();
    }
    clear(notify=true){
      this.generation++;this.uiGeneration++;for(const timer of this.timers)clearTimeout(timer);this.timers.clear();
      this.records=[];this.operations.clear();this.dispatchQueue=[];this.targetLocks.clear();this.dispatching=false;this.activeDispatchID=null;
      this.views.forEach(v=>v.el.remove());this.views.clear();this.index=0;this.transitioning=false;
      this.held=null;this.previousPointer=null;this.deferred=false;this.followTail=false;this.scrollAccumulator=0;
      this.lastOperationID=null;this.phase='idle';this._apply(false);
      if(notify){this._emit('reset',null,null,'已清空原型状态');this._notify();}
    }
    resize(width,height,insets){
      this.width=Math.max(1,Number(width)||1440);this.height=Math.max(1,Number(height)||900);
      this.insets={...this.insets,...insets};this.uiGeneration++;this.transitioning=false;this.held=null;
      this.views.forEach(v=>v.el.remove());this.views.clear();this.deferred=false;this.phase='idle';this._apply(false);
    }
    setTheme(theme){this.theme=theme==='dark'?'dark':'light';this.layer.dataset.theme=this.theme;this._notify();}
    setOutcome(outcome){if(OUTCOMES.includes(outcome))this.outcome=outcome;this._notify();}
    setLatency(ms){this.latency=Math.max(300,Math.min(15000,Number(ms)||1350));this._notify();}
    setHitAreas(value){this.hitAreas=!!value;this.layer.dataset.hitAreas=String(this.hitAreas);this._notify();}
    setReducedMotion(value){this.reducedMotion=!!value;this._notify();}
    showOldest(){if(this.held||this.transitioning)return;this.index=0;this.followTail=false;this._apply(false);}
    showLatest(){if(this.held||this.transitioning)return;this.index=this.records.filter(r=>r.status!=='used').length;this.followTail=false;this._apply(false);}
    _render(){
      if(this.held||this.transitioning){this.deferred=true;this._notify();return;}
      const used=this.records.filter(r=>r.status==='used'&&this.views.has(r.id));
      if(used.length){this._swallow(used);return;}
      this._apply(false);
    }
    _swallow(records){
      this.transitioning=true;this.phase='swallow';this.deferred=true;
      for(const view of this.views.values())view.el.setAttribute('aria-disabled','true');
      const duration=this._duration(C.swallowDuration);
      for(const record of records){
        const view=this.views.get(record.id);if(!view)continue;
        this._offset(view,view.geometry.imageClipFrame.width+2,duration);
        view.el.style.transition='opacity '+duration+'ms ease';view.el.style.opacity='0';
      }
      this._emit('swallow',records[0],this.operations.get(records[0].operationID),'已确认完成，开始吞噬',{duration});
      this._notify();
      this._later(()=>{
        for(const record of records){const view=this.views.get(record.id);if(view)view.el.remove();this.views.delete(record.id);}
        this.transitioning=false;this.deferred=false;this._apply(true);
      },duration,null,true);
    }
    _apply(animateShift){
      let next=layout(this.records,this.width,this.height,this.insets,this.index);
      if(this.followTail&&next.totalCount>next.capacity){this.index=Math.max(0,next.totalCount-next.capacity);next=layout(this.records,this.width,this.height,this.insets,this.index);}
      this.followTail=false;this.index=next.firstVisibleIndex;this.currentLayout=next;
      const visibleIDs=new Set(next.rows.map(g=>g.assetID));
      for(const[id,view]of this.views){if(!visibleIDs.has(id)){view.el.remove();this.views.delete(id);}}
      const duration=animateShift?this._duration(C.shiftDuration):0;
      if(animateShift){this.transitioning=true;this.phase='shift';}
      for(const geometry of next.rows){
        const record=this.records.find(r=>r.id===geometry.assetID);
        let view=this.views.get(record.id);const isNew=!view;
        if(isNew){view=this._makeView(record);this.views.set(record.id,view);}
        const oldStatus=view.renderStatus;view.renderStatus=record.status;
        view.el.dataset.status=record.status;
        if(!animateShift||isNew)this._geometry(view,geometry);
        else{
          // As in AppKit, hold old image/number geometry until 180 ms reflow ends.
          const old=view.geometry.frame;
          view.el.style.transition='top '+duration+'ms cubic-bezier(0,0,.58,1),left '+duration+'ms cubic-bezier(0,0,.58,1)';
          view.el.style.left=(geometry.frame.x+geometry.frame.width-old.width)+'px';
          view.el.style.top=(geometry.frame.y+geometry.frame.height/2-old.height/2)+'px';
        }
        const expected=(record.status==='transferring'||record.status==='unknown')?C.inwardDistance:0;
        if(isNew){
          view.el.style.opacity='0';this._offset(view,expected,0);
          // A layout read commits opacity=0 so a real arrival fade is visible.
          void view.el.offsetWidth;
          view.el.style.transition='opacity '+this._duration(C.arrivalDuration)+'ms ease';view.el.style.opacity='1';
        }else if(oldStatus!==record.status||view.offset!==expected){
          this._offset(view,expected,this._duration(record.status==='failed'?C.returnDuration:C.pressDuration));
        }
        this._description(view,record);
      }
      rectStyle(this.seam,next.lineFrame);
      if(animateShift){
        this._emit('shift',null,null,'后续截图补位；结束后重新编号',{duration});
        this._later(()=>{
          this.transitioning=false;this.phase='idle';
          for(const geometry of next.rows){const view=this.views.get(geometry.assetID);if(view){view.el.style.transition='none';this._geometry(view,geometry);const record=this.records.find(r=>r.id===geometry.assetID);if(record)this._description(view,record);}}
          const deferred=this.deferred;this.deferred=false;
          this._emit('settled',null,null,'补位完成；编号已更新');
          if(deferred)this._render();else this._notify();
        },duration,null,true);
      }else this.phase='idle';
      this._notify();
    }
    _makeView(record){
      const el=document.createElement('div');el.className='rift-row';el.setAttribute('role','button');el.tabIndex=0;el.dataset.assetId=record.id;
      const clip=document.createElement('div');clip.className='rift-clip';
      const image=document.createElement('img');image.className='rift-image';image.src=record.src;image.alt='';image.draggable=false;clip.appendChild(image);
      const number=document.createElement('span');number.className='rift-number';number.setAttribute('aria-hidden','true');
      const underline=document.createElement('span');underline.className='rift-underline first';
      const second=document.createElement('span');second.className='rift-underline second';
      el.append(clip,number,underline,second);this.layer.appendChild(el);
      const view={el,clip,image,number,underline,second,offset:0,geometry:null,renderStatus:record.status};
      el.addEventListener('pointerdown',e=>this._down(record.id,e));
      el.addEventListener('pointerup',e=>this._up(record.id,e));
      el.addEventListener('pointercancel',()=>this._cancelPointer());
      el.addEventListener('lostpointercapture',()=>{if(this.held&&this.held.id===record.id)this._cancelPointer();});
      el.addEventListener('click',e=>e.preventDefault());
      el.addEventListener('dblclick',e=>{e.preventDefault();this._emit('blocked',record,null,'双击不触发第二次附加');});
      el.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();if(!this.transitioning&&!this.held)this._select(record.id);}});
      el.addEventListener('wheel',e=>{e.preventDefault();e.stopPropagation();this._scroll(e.deltaY);},{passive:false});
      return view;
    }
    _geometry(view,g){
      view.geometry=g;rectStyle(view.el,g.frame);rectStyle(view.clip,g.imageClipFrame);
      view.image.style.width=g.imageFrame.width+'px';view.image.style.height=g.imageFrame.height+'px';
      rectStyle(view.number,g.numberFrame);view.number.textContent=String(g.ordinal);
      rectStyle(view.underline,g.underlineFrame);rectStyle(view.second,{...g.underlineFrame,y:g.underlineFrame.y+3});
      view.el.dataset.ordinal=String(g.ordinal);
    }
    _description(view,record){
      const ordinal=view.geometry?view.geometry.ordinal:1;
      const text='截图 '+ordinal+' · '+(STATUSES[record.status]||record.status);
      view.el.setAttribute('aria-label',text);view.el.title=text+'。在微图上滚动查看前后截图。';
      view.el.setAttribute('aria-disabled',String(record.status==='transferring'||record.status==='used'||this.transitioning));
    }
    _offset(view,value,duration){
      view.offset=value;view.image.style.transition=duration?'transform '+duration+'ms cubic-bezier(0,0,.58,1)':'none';
      view.image.style.transform='translateX('+value+'px)';
    }
    _point(event){const r=this.layer.getBoundingClientRect();return{x:(event.clientX-r.left)*(this.width/r.width),y:(event.clientY-r.top)*(this.height/r.height)};}
    _down(id,event){
      if(event.button!==0)return;event.preventDefault();event.stopPropagation();
      const record=this.records.find(r=>r.id===id),view=this.views.get(id),p=this._point(event),now=performance.now();
      const nearPrevious=this.previousPointer&&now-this.previousPointer.time<=500&&Math.hypot(p.x-this.previousPointer.x,p.y-this.previousPointer.y)<=4;
      if(!record||!view||this.held||this.transitioning||['transferring','used','missing'].includes(record.status)||event.detail>1||nearPrevious){
        this._emit('blocked',record,null,this.transitioning?'吞噬／补位中，点击被忽略':'重复点击不会重复附加');this._notify();return;
      }
      this.held={id,point:p,time:now,pointerId:event.pointerId};
      if(view.el.setPointerCapture)view.el.setPointerCapture(event.pointerId);
      this._offset(view,C.inwardDistance,this._duration(C.pressDuration));this._notify();
    }
    _up(id,event){
      event.preventDefault();event.stopPropagation();if(!this.held||this.held.id!==id)return;
      const held=this.held,view=this.views.get(id);this.held=null;
      let inside=false;
      if(view){const r=view.el.getBoundingClientRect();inside=event.clientX>=r.left&&event.clientX<=r.right&&event.clientY>=r.top&&event.clientY<=r.bottom;}
      if(inside)this.previousPointer={...held.point,time:held.time};
      if(!inside&&view){const record=this.records.find(r=>r.id===id);this._offset(view,record&&record.status==='unknown'?C.inwardDistance:0,this._duration(C.returnDuration));}
      if(this.deferred){this.deferred=false;this._render();}
      if(inside)this._select(id);else this._notify();
      if(view&&view.el.hasPointerCapture&&view.el.hasPointerCapture(event.pointerId))view.el.releasePointerCapture(event.pointerId);
    }
    _cancelPointer(){
      if(!this.held)return;const id=this.held.id;this.held=null;
      const view=this.views.get(id),record=this.records.find(r=>r.id===id);
      if(view)this._offset(view,record&&record.status==='unknown'?C.inwardDistance:0,this._duration(C.returnDuration));
      if(this.deferred){this.deferred=false;this._render();}else this._notify();
    }
    _scroll(delta){
      if(this.held||this.transitioning)return;
      this.scrollAccumulator+=delta;if(Math.abs(this.scrollAccumulator)<8)return;
      this.index=Math.max(0,this.index+(this.scrollAccumulator>0?1:-1));this.scrollAccumulator=0;
      this.followTail=false;this._apply(false);
    }

    // SYNTHETIC REVIEW TRANSPORT. Core-inspired ordering/identity boundaries,
    // configurable outcomes and latency; not the native --simulate adapter.
    _select(id){
      const record=this.records.find(r=>r.id===id);if(!record)return;
      if(record.status==='unknown'){
        const op=this.operations.get(record.operationID);this.lastOperationID=record.operationID;
        this._emit('observation',record,op,'仅检查原操作；没有新上传、没有新 attempt');this._notify();return;
      }
      if(['used','transferring','missing'].includes(record.status)){this._emit('blocked',record,null,'该截图已有操作；不重复附加');this._notify();return;}
      if(this.outcome==='native-disabled'){
        this._emit('blocked',record,null,'普通工程模式的适配器未启用；只还原按压反馈，未建立上传操作');
        this._later(()=>{const view=this.views.get(id);if(view&&['pending','failed'].includes(record.status))this._offset(view,0,this._duration(C.returnDuration));this._notify();},this._duration(C.pressDuration)+50);
        this._notify();return;
      }
      const target=this.getTarget();
      const op={id:'synthetic-op-'+(++this.counter),assetID:id,target,outcome:this.outcome,
        state:'prepared',timers:new Set(),injected:false,targetChanged:false,latency:this.latency};
      this.operations.set(op.id,op);this.dispatchQueue.push(op.id);this.lastOperationID=op.id;
      record.operationID=op.id;record.status='transferring';record.progress=0;
      this._emit('accepted',record,op,'锁定点击时的对话与截图；按点击顺序排队');this._render();
      queueMicrotask(()=>this._drain());
    }
    _drain(){
      if(this.dispatching)return;
      while(this.dispatchQueue.length){
        const op=this.operations.get(this.dispatchQueue.shift());if(!op||op.state!=='prepared')continue;
        const record=this.records.find(r=>r.id===op.assetID);if(!record)continue;
        if(this.targetLocks.has(op.target)){
          op.state='failed';record.status='failed';
          this._emit('failed',record,op,'原对话仍有 UNKNOWN 操作；本次未输入，明确失败保留',{beforeInput:true});this._render();continue;
        }
        if(op.targetChanged||this.getTarget()!==op.target){
          op.state='failed';record.status='failed';
          this._emit('failed',record,op,'轮到本图之前目标对话已改变；没有向新对话输入',{beforeInput:true});this._render();continue;
        }
        this.dispatching=true;this.activeDispatchID=op.id;op.state='dispatching';this.targetLocks.set(op.target,op.id);
        this._later(()=>this._beginTransport(op),80,op);this._notify();return;
      }
      this._notify();
    }
    _beginTransport(op){
      const record=this.records.find(r=>r.id===op.assetID);if(!record)return;
      // Final target check before the synthetic input boundary.
      if(op.targetChanged||this.getTarget()!==op.target){this._finish(op,'failure','输入之前目标改变；未插入任何附件',{beforeInput:true});return;}
      op.injected=true;op.state='uploading';
      this._emit('placeholder',record,op,'附件占位出现；这还不是完成证明',{progress:0});
      if(op.outcome==='target-change')this._later(()=>{
        op.targetChanged=true;this._emit('target-changed',record,op,'测试情境：输入之后切换对话；原操作不会改绑');
      },100,op);
      if(op.outcome==='capture-during')this._later(()=>this._emit('capture-request',record,op,'测试情境：上传期间产生另一张合成截图'),Math.min(500,op.latency*.45),op);
      const steps=Math.max(4,Math.ceil(op.latency/120));
      for(let i=1;i<=steps;i++)this._later(()=>{
        if(op.state!=='uploading')return;
        if(this.getTarget()!==op.target)op.targetChanged=true;
        const maximum=op.outcome==='waiting'?64:(op.outcome==='failure'?76:100);
        record.progress=Math.round(maximum*i/steps);
        this._emit('progress',record,op,'合成附件上传进度',{progress:record.progress});this._notify();
        if(i===steps){
          if(op.outcome==='waiting'){op.state='waiting';this._emit('waiting',record,op,'保持等待；尚无完成或失败回执');this._notify();}
          else if(op.targetChanged||op.outcome==='target-change')this._finish(op,'unknown','输入之后对话改变；完成结果未知，保留原图与原目标');
          else if(op.outcome==='failure')this._finish(op,'failure','收到明确失败回执；未完成附加，截图回退保留');
          else if(op.outcome==='unknown')this._finish(op,'unknown','缺少可信完成回执；即使看到附件占位也不吞噬');
          else this._confirm(op);
        }
      },op.latency*i/steps,op);
    }
    _confirm(op){
      const record=this.records.find(r=>r.id===op.assetID);if(!record)return;
      op.state='confirming';record.progress=100;
      this._emit('progress',record,op,'上传达到 100%；继续等待独立完成确认',{progress:100,confirming:true});this._notify();
      this._later(()=>{
        if(this.getTarget()!==op.target)op.targetChanged=true;
        if(op.targetChanged)this._finish(op,'unknown','确认期间目标改变；保留原操作，不能据占位判断完成');
        else this._finish(op,'success','合成完成回执已确认原截图、原操作与原对话');
      },260,op);
    }
    _finish(op,result,message,extra={}){
      const record=this.records.find(r=>r.id===op.assetID);if(!record)return;
      this._clearTimers(op);
      if(result==='success'){
        op.state='verified';record.status='used';record.progress=100;this.targetLocks.delete(op.target);
        this._emit('verified',record,op,message,{progress:100,...extra});
      }else if(result==='failure'){
        op.state='failed';record.status='failed';record.progress=0;this.targetLocks.delete(op.target);
        this._emit('failed',record,op,message,extra);
      }else{
        op.state='unknown';record.status='unknown';
        this._emit('unknown',record,op,message,extra);
      }
      if(this.activeDispatchID===op.id){this.dispatching=false;this.activeDispatchID=null;}
      this._render();queueMicrotask(()=>this._drain());
    }
    resolve(result){
      if(!['success','failure','unknown'].includes(result))return false;
      let op=this.operations.get(this.lastOperationID);
      if(!op||!['uploading','waiting','confirming','unknown','dispatching'].includes(op.state))
        op=Array.from(this.operations.values()).find(o=>['uploading','waiting','confirming','unknown','dispatching'].includes(o.state));
      if(!op)return false;
      const record=this.records.find(r=>r.id===op.assetID);
      if(result==='success'&&!op.injected){
        this._emit('blocked',record,op,'尚未越过输入边界；评审工具不能为未输入的附件确认成功');this._notify();return false;
      }
      this._clearTimers(op);
      if(result==='success'){
        // The review control injects evidence for the ORIGINAL operation; it is
        // not a retry and does not append another attachment to the current chat.
        op.targetChanged=false;op.state='confirming';record.progress=100;
        this._emit('progress',record,op,'评审工具为原操作提供最终完成证据；不重新上传',{progress:100,confirming:true});
        this._later(()=>this._finish(op,'success','评审工具确认原操作完成；没有重放上传'),260,op);
      }else this._finish(op,result,result==='failure'?'评审工具注入明确失败回执':'评审工具注入 UNKNOWN 回执');
      this._notify();return true;
    }
    notifyTargetChanged(){
      // Navigation invalidates the captured lease even if the user returns to
      // the same thread before the next progress callback.
      const invalidated=[];
      for(const op of this.operations.values())if(['prepared','dispatching','uploading','waiting','confirming'].includes(op.state)&&this.getTarget()!==op.target){
        op.targetChanged=true;if(op.injected)invalidated.push(op);
      }
      for(const op of invalidated)this._finish(op,'unknown','输入之后对话改变；原租约失效，截图与原操作保留');
      this._notify();
    }
    snapshot(){
      const current=this.currentLayout||layout(this.records,this.width,this.height,this.insets,this.index);
      const active=this.records.filter(r=>r.status!=='used');
      return {width:this.width,height:this.height,insets:{...this.insets},configuration:{...C},
        outcome:this.outcome,latency:this.latency,theme:this.theme,reducedMotion:this.reducedMotion,
        hitAreas:this.hitAreas,transitioning:this.transitioning,phase:this.phase,isHolding:!!this.held,
        count:active.length,totalCount:active.length,usedCount:this.records.length-active.length,
        capacity:current.capacity,firstVisibleIndex:current.firstVisibleIndex,
        visibleRange:[current.firstVisibleIndex,current.firstVisibleIndex+current.rows.length],
        hasEarlier:current.hasEarlier,hasLater:current.hasLater,lineFrame:{...current.lineFrame},
        rows:current.rows.map(g=>{const view=this.views.get(g.assetID),record=this.records.find(r=>r.id===g.assetID);return{...g,status:record?record.status:null,offset:view?view.offset:0,displayedOrdinal:view&&view.geometry?view.geometry.ordinal:g.ordinal};}),
        queue:this.records.map((r,i)=>({id:r.id,label:r.label,width:r.width,height:r.height,status:r.status,
          ordinal:r.status==='used'?null:active.findIndex(a=>a.id===r.id)+1,progress:r.progress,
          operationID:r.operationID,target:r.operationID?this.operations.get(r.operationID)?.target:null})),
        operations:Array.from(this.operations.values()).map(o=>({id:o.id,assetID:o.assetID,target:o.target,state:o.state,injected:o.injected})),
        eventCounters:{...this.eventCounters},lastEvent:this.lastEvent};
    }
  }
  global.RiftEngine=RiftEngine;
  if(typeof module!=='undefined'&&module.exports)module.exports=RiftEngine;
})(typeof window!=='undefined'?window:globalThis);
