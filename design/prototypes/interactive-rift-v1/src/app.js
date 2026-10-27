(function () {
  'use strict';
  const $=id=>document.getElementById(id);
  const ui={preset:'current',scaleMode:'actual',scale:1,width:1440,height:900,theme:'light',immersive:false,events:[],assets:new Map(),ready:false};
  let engine,desktop,renderQueued=false,previousCount=-1,lastSize='';
  const sceneNames={chrome:'Chrome / ChatGPT',desktop:'macOS 桌面',workspace:'多窗口工作台'};
  const statusNames={pending:'待附加',transferring:'等待回执',unknown:'UNKNOWN',failed:'失败 · 保留',used:'已吞噬'};
  const attachmentOps=new Set();
  function eventLog(e){
    if(e.type==='progress'&&!e.confirming)return;
    const entry={time:Date.now(),type:e.type,message:e.message||e.type,asset:e.asset?.label||null};
    ui.events.push(entry);if(ui.events.length>100)ui.events.shift();
    $('eventSummary').textContent=entry.message;
    if(!$('reviewPanel').hidden)renderEvents();
  }
  function handleEngineEvent(e){
    eventLog(e);
    if(!desktop)return;
    if(e.type==='placeholder'){
      attachmentOps.add(e.operationID);
      desktop.setAttachment({operationID:e.operationID,asset:e.asset,target:e.target,status:'uploading',progress:0});
    }else if(e.type==='progress'&&attachmentOps.has(e.operationID)){
      desktop.setAttachment({operationID:e.operationID,asset:e.asset,target:e.target,status:e.confirming?'confirming':'uploading',progress:e.progress});
    }else if(['verified','failed','unknown'].includes(e.type)&&attachmentOps.has(e.operationID)){
      desktop.setAttachment({operationID:e.operationID,asset:e.asset,target:e.target,status:({verified:'ready',failed:'failed',unknown:'unknown'})[e.type],progress:e.type==='verified'?100:e.progress});
    }else if(e.type==='target-changed'){
      desktop.setThread(e.target==='thread-a'?'thread-b':'thread-a');
    }else if(e.type==='capture-request'){
      addCapture();
    }
  }
  function handleState(snapshot){
    const count=snapshot.count;
    $('queueSummary').textContent=count+' 张待处理'+(snapshot.totalCount>snapshot.capacity?' · 可见 '+(snapshot.visibleRange[0]+1)+'–'+snapshot.visibleRange[1]:'');
    if(previousCount!==count){document.querySelectorAll('[data-count]').forEach(b=>b.classList.toggle('is-selected',Number(b.dataset.count)===count));previousCount=count;}
    const resolvable=snapshot.operations.some(o=>['uploading','confirming','waiting','unknown'].includes(o.state));
    document.querySelectorAll('[data-resolve]').forEach(b=>b.disabled=!resolvable);
    $('oldest').disabled=!snapshot.hasEarlier;$('latest').disabled=!snapshot.hasLater;
    if(!$('reviewPanel').hidden&&!renderQueued){renderQueued=true;requestAnimationFrame(()=>{renderQueued=false;renderQueue(engine?engine.snapshot():snapshot);});}
  }
  function handleDesktopEvent(e){
    if(e.type==='scene-changed'){$('scene').value=e.scene;$('sceneLabel').textContent=sceneNames[e.scene];}
    if(e.type==='window-changed'&&desktop)$('windowMode').value=desktop.windowMode;
  }
  function addCapture(){const asset=RiftAssets.create();ui.assets.set(asset.id,asset);engine.add(asset);return asset;}
  function populate(count){
    desktop.clearAttachments();attachmentOps.clear();ui.assets.clear();RiftAssets.reset();
    const assets=RiftAssets.batch(count);for(const a of assets)ui.assets.set(a.id,a);engine.populate(assets);return assets;
  }
  function screenDimensions(){
    if(ui.preset==='current')return{width:Math.max(760,$('viewport').clientWidth),height:Math.max(520,$('viewport').clientHeight)};
    const [width,height]=ui.preset.split('x').map(Number);return{width,height};
  }
  function updateGeometry(pan=false){
    const d=screenDimensions();ui.width=d.width;ui.height=d.height;
    const availableW=$('viewport').clientWidth,availableH=$('viewport').clientHeight;
    ui.scale=ui.scaleMode==='fit'?Math.min(1,availableW/d.width,availableH/d.height):1;
    const screen=$('screen'),holder=$('canvasHolder');
    Object.assign(screen.style,{width:d.width+'px',height:d.height+'px',transform:'scale('+ui.scale+')'});
    Object.assign(holder.style,{width:(d.width*ui.scale)+'px',height:(d.height*ui.scale)+'px'});
    const key=d.width+'x'+d.height;
    if(key!==lastSize){desktop.setSize(d.width,d.height);engine.resize(d.width,d.height,desktop.insets);lastSize=key;}
    $('geometryLabel').textContent=d.width+' × '+d.height+' pt';
    const percent=Math.round(ui.scale*100);
    $('scaleLabel').textContent=ui.scale<.999?'缩小总览 '+percent+'% · 此视图不用于判断实际尺寸':'1 CSS px = 1 逻辑点 · 请保持浏览器缩放 100%';
    $('scaleLabel').classList.toggle('is-scaled',ui.scale<.999);
    if(pan)requestAnimationFrame(()=>{$('viewport').scrollLeft=$('viewport').scrollWidth;$('viewport').scrollTop=0;});
  }
  function renderEvents(){
    $('eventLog').replaceChildren();
    for(const e of ui.events.slice(-45).reverse()){
      const li=document.createElement('li'),time=document.createElement('time'),span=document.createElement('span');
      const d=new Date(e.time);time.textContent=d.toLocaleTimeString('zh-CN',{hour12:false})+'.'+String(d.getMilliseconds()).padStart(3,'0');
      span.textContent=e.message;li.append(time,span);$('eventLog').append(li);
    }
  }
  function renderQueue(s){
    const el=$('queueTable');el.replaceChildren();
    const active=s.queue.filter(r=>r.status!=='used');
    if(!active.length){const p=document.createElement('p');p.className='review-small';p.textContent='队列为空。右缘只剩 24 pt 长的细线。';el.append(p);return;}
    for(const r of active){
      const row=document.createElement('div');row.className='review-qrow';
      const order=document.createElement('span');order.textContent=r.ordinal;
      const im=document.createElement('img');im.src=ui.assets.get(r.id)?.src||'';im.alt='';
      const name=document.createElement('button');name.textContent=r.label;name.title='在评审工具中查看合成原图';name.addEventListener('click',()=>showAsset(r.id));
      const state=document.createElement('span');state.className='q-status';state.textContent=statusNames[r.status]||r.status;
      const fit=RiftEngine.fit(r.width,r.height),size=document.createElement('span');size.textContent=(fit.width*.75).toFixed(1)+' × '+fit.height.toFixed(1)+' pt';size.title='可见图片尺寸，未计编号与透明点击区域';
      row.append(order,im,name,state,size);el.append(row);
    }
  }
  function showAsset(id){const a=ui.assets.get(id);if(!a)return;$('assetTitle').textContent=a.label;$('assetDimensions').textContent=a.width+' × '+a.height+' px · 原始比例';$('assetImage').src=a.src;$('assetDialog').showModal();}
  function setImmersive(value){
    ui.immersive=!!value;$('reviewApp').classList.toggle('is-immersive',ui.immersive);
    if(ui.immersive){$('immersiveHint').hidden=false;setTimeout(()=>{$('immersiveHint').hidden=true;},3200);}else $('immersiveHint').hidden=true;
    requestAnimationFrame(()=>updateGeometry(true));
  }
  function init(){
    desktop=new RiftDesktop({element:$('desktopRoot'),width:1440,height:900,onThreadChange:()=>{if(engine)engine.notifyTargetChanged();},onEvent:handleDesktopEvent});
    engine=new RiftEngine({layer:$('riftLayer'),width:1440,height:900,insets:desktop.insets,getTarget:()=>desktop.getThread(),onEvent:handleEngineEvent,onState:handleState});
    engine.setLatency(1200);desktop.setScene('chrome');desktop.setTheme('light');
    $('addCapture').addEventListener('click',addCapture);
    document.querySelectorAll('[data-count]').forEach(b=>b.addEventListener('click',()=>populate(Number(b.dataset.count))));
    $('outcome').addEventListener('change',e=>{engine.setOutcome(e.target.value);$('latency').disabled=e.target.value==='native-disabled';eventLog({type:'mode',message:e.target.value==='native-disabled'?'当前普通工程模式：点击反馈后回退，不会上传。':'已切换测试结果；只影响之后的新操作。'});});
    $('latency').addEventListener('change',e=>engine.setLatency(Number(e.target.value)));
    document.querySelectorAll('[data-resolve]').forEach(b=>b.addEventListener('click',()=>engine.resolve(b.dataset.resolve)));
    $('screenSize').addEventListener('change',e=>{ui.preset=e.target.value;updateGeometry(true);});
    $('scene').addEventListener('change',e=>desktop.setScene(e.target.value));
    document.querySelectorAll('.review-segment button[data-theme]').forEach(b=>b.addEventListener('click',()=>{ui.theme=b.dataset.theme;desktop.setTheme(ui.theme);engine.setTheme(ui.theme);document.querySelectorAll('.review-segment button[data-theme]').forEach(t=>t.classList.toggle('is-selected',t.dataset.theme===ui.theme));}));
    $('windowMode').addEventListener('change',e=>desktop.setWindowMode(e.target.value));
    $('windowWidth').addEventListener('input',e=>desktop.setWindowWidth(Number(e.target.value)));
    document.querySelectorAll('[data-scale]').forEach(b=>b.addEventListener('click',()=>{ui.scaleMode=b.dataset.scale;document.querySelectorAll('[data-scale]').forEach(t=>t.classList.toggle('is-selected',t.dataset.scale===ui.scaleMode));updateGeometry(true);}));
    $('panRight').addEventListener('click',()=>{$('viewport').scrollLeft=$('viewport').scrollWidth;$('viewport').scrollTop=0;});
    $('oldest').addEventListener('click',()=>engine.showOldest());$('latest').addEventListener('click',()=>engine.showLatest());
    $('reviewToggle').addEventListener('click',()=>{const panel=$('reviewPanel');panel.hidden=!panel.hidden;$('reviewToggle').setAttribute('aria-expanded',String(!panel.hidden));if(!panel.hidden){renderQueue(engine.snapshot());renderEvents();panel.scrollIntoView({behavior:'smooth',block:'nearest'});}});
    $('detailsToggle').addEventListener('click',()=>{const d=$('explanation');d.hidden=!d.hidden;$('detailsToggle').setAttribute('aria-expanded',String(!d.hidden));if(!d.hidden)d.scrollIntoView({behavior:'smooth',block:'nearest'});});
    $('hitAreas').addEventListener('change',e=>engine.setHitAreas(e.target.checked));$('reducedMotion').addEventListener('change',e=>engine.setReducedMotion(e.target.checked));
    $('clearEvents').addEventListener('click',()=>{ui.events=[];renderEvents();});
    $('closeAsset').addEventListener('click',()=>$('assetDialog').close());
    $('assetDialog').addEventListener('click',e=>{if(e.target===$('assetDialog'))$('assetDialog').close();});
    $('immersive').addEventListener('click',async()=>{setImmersive(true);try{if(!document.fullscreenElement&&document.documentElement.requestFullscreen)await document.documentElement.requestFullscreen();}catch(e){/* CSS immersion remains fully functional when the iframe disallows fullscreen. */}});
    document.addEventListener('fullscreenchange',()=>{if(!document.fullscreenElement&&ui.immersive)setImmersive(false);});
    window.addEventListener('keydown',e=>{if(e.key==='Escape'&&ui.immersive){setImmersive(false);if(document.fullscreenElement)document.exitFullscreen().catch(()=>{});}if(e.altKey&&e.shiftKey&&e.code==='KeyN'&&!e.repeat){e.preventDefault();addCapture();}});
    let resizeFrame;new ResizeObserver(()=>{cancelAnimationFrame(resizeFrame);resizeFrame=requestAnimationFrame(()=>{if(ui.ready)updateGeometry(false);});}).observe($('viewport'));
    populate(3);ui.ready=true;updateGeometry(true);$('eventSummary').textContent='点击屏幕右缘的微型截图，开始体验。';
    // Debug inspection only; all user behavior is also available through visible UI.
    window.RiftletPrototype={engine,desktop,addCapture,populate,setImmersive,snapshot:()=>({ui:{preset:ui.preset,scaleMode:ui.scaleMode,scale:ui.scale,width:ui.width,height:ui.height,theme:ui.theme,immersive:ui.immersive},engine:engine.snapshot(),desktop:desktop.snapshot(),events:ui.events.slice()}),source:'485fa87a31140f9d2e428db69ec5e0599b1f96ae'};
    // Opening this file locally is already the complete offline deliverable.
    // Hide hosted downloads rather than serialize a runtime DOM with stale rows.
    if(location.protocol==='file:'){$('downloadHTML').hidden=true;$('downloadSource').hidden=true;}
  }
  init();
})();
