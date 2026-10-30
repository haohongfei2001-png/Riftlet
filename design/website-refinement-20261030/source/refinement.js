/* Local-only presentation. Synthetic signals below do not call a capture,
 * clipboard, upload, ChatGPT, analytics, storage, or message-sending API. */
(() => {
 'use strict';
 const $=id=>document.getElementById(id), scene=$('hero-scene'), rail=$('hero-edge');
 const motion=matchMedia('(prefers-reduced-motion: reduce)');
 const staticCopy=[...document.querySelectorAll('[data-en]')].map(node=>({node,zh:node.innerHTML,en:node.dataset.en}));
 const words={
 zh:{initial:'点一下右侧微图，试着放进草稿。',added:'新截图已在边缘，点一下就能取用。',request:'正在准备附加，截图仍在边缘。',start:'已模拟开始附加。微图收起，最终结果仍在核实。',ready:'图片已在示例草稿中。文字保留，没有发送。',failure:'已模拟明确失败。截图回到边缘，可以再次点击。',unknown:'开始后的结果未知：保留在示例历史，不自动重传。',blocked:'当前没有可用发言框。截图保留在边缘。',removed:'仅移除示例草稿中的附件，不重新上传。',stopped:'引导已停止。你可以直接点击边缘的微图。',full:'边缘已有三张示例。先点一张，再模拟新的截图。',empty:'还没有附加记录。',name:'截图',sample:'示例',original:'原有附件',preparing:'附加中',complete:'已就绪',unconfirmed:'待核实',failed:'失败，可再次点击',waiting:'仍在边缘',remove:'移除示例附件',attach:'将截图附加到示例草稿',history:'示例历史',dark:'深色桌面',light:'浅色桌面',draft:'帮我看看这个页面，还能如何改进？',tour:'01 照常截图，接着点一下微图。'},
 en:{initial:'Click a small image at the right edge.',added:'A new capture is at the edge. Click it to use it.',request:'Preparing to attach. The image stays at the edge.',start:'Simulated attachment has started. The image tucks away; completion is still pending.',ready:'The image is in the sample draft. Your words stay. Nothing was sent.',failure:'Confirmed failure simulated. The image is back and clickable.',unknown:'Unconfirmed after starting: kept in sample history, without another upload.',blocked:'No available composer. The image stays at the edge.',removed:'The sample attachment was removed. It will not be uploaded again.',stopped:'Walkthrough stopped. You can click an image yourself.',full:'Three samples are waiting. Use one before adding another.',empty:'No attachment history yet.',name:'Capture',sample:'Sample',original:'Existing attachment',preparing:'Attaching',complete:'Ready',unconfirmed:'Unconfirmed',failed:'Failed; click to retry',waiting:'At the edge',remove:'Remove sample attachment',attach:'Add image to the sample draft',history:'Sample history',dark:'Dark desktop',light:'Light desktop',draft:'How could I improve this page?',tour:'01 Capture as usual, then click the little image.'}
 };
 let language='zh',edited=false,lastKey='initial',held=false,keyboard=false,tourActive=false;
 let timers=new Set(),tourTimers=new Set(),buttons=new Map(),cards=new Map();
 const t=key=>words[language][key]||key;
 const svg=x=>`<svg viewBox="${x.view}" aria-hidden="true"><use href="#${x.symbol}"></use></svg>`;
 function say(key){lastKey=key;$('hero-status').textContent=t(key);$('hero-status').dataset.status=key;}
 function schedule(fn,delay,set=timers){const handle=setTimeout(()=>{set.delete(handle);fn();},delay);set.add(handle);return handle;}
 function clear(set){for(const id of set)clearTimeout(id);set.clear();}
 function stopTour(announce=false){clear(tourTimers);tourActive=false;$('hero-pause').hidden=true;if(announce)say('stopped');}
 function activeCount(){return model.items.filter(x=>x.visible).length;}
 function updateThemeText(){
  const dark=$('hero-desktop')?.classList.contains('dark')||document.querySelector('.hero-desktop').classList.contains('dark');
  $('desktop-theme').setAttribute('aria-pressed',String(dark));
  $('desktop-theme').querySelector('span:last-child').textContent=t(dark?'light':'dark');
 }
 function setLanguage(next){
  language=next==='en'?'en':'zh';document.documentElement.lang=language==='en'?'en':'zh-CN';
  staticCopy.forEach(x=>{x.node.innerHTML=x[language];});
  $('language-toggle').textContent=language==='en'?'中文':'EN';
  $('language-toggle').setAttribute('aria-label',language==='en'?'切换为中文':'Switch to English');
  document.title=language==='en'?'Riftlet — No searching. Right there.':'Riftlet — 不必找。就在那儿。';
  if(!edited)$('hero-draft').value=t('draft');
  $('hero-capture').setAttribute('aria-label',language==='en'?'Add a synthetic sample screenshot':'增加一张合成示例截图');
  if(document.body.classList.contains('candidate-b'))document.querySelector('.hero-demo-label').textContent=language==='en'?'Enlarged illustration':'边缘局部 · 放大示意';
  rail.setAttribute('aria-label',language==='en'?'Demo screenshot queue':'示例截图队列');
  scene.setAttribute('aria-label',language==='en'?'Local screenshot-to-draft illustration':'截图进入草稿的本地交互示意');
  $('hero-attachments').setAttribute('aria-label',language==='en'?'Sample draft attachments':'示例草稿附件');
  updateThemeText();render('locale');say(lastKey);
 }
 function focusAfterHide(item){
  const b=buttons.get(item.id);
  if(!item.visible && keyboard && document.activeElement===b){
   const next=model.items.find(x=>x.visible&&x.id!==item.id);
   (next?buttons.get(next.id):$('history-toggle'))?.focus({preventScroll:true});
  }
 }
 function layout(){
  if(held)return;
  model.items.filter(x=>x.visible).forEach((x,i)=>buttons.get(x.id)?.style.setProperty('--slot',String(i)));
 }
 function render(event,item){
  if(event==='reset'){
   $('shot-list').replaceChildren();buttons.clear();
   for(const card of cards.values())card.remove();cards.clear();held=false;
  }
  const visible=model.items.filter(x=>x.visible);
  for(const x of model.items){
   let b=buttons.get(x.id);
   if(!b){
    b=document.createElement('button');b.type='button';b.className='hero-shot';b.dataset.id=String(x.id);
    b.style.setProperty('--shot-width',x.w+'px');b.style.setProperty('--shot-height',x.h+'px');
    b.style.setProperty('--large-width',x.lw+'px');b.style.setProperty('--large-height',x.lh+'px');
    b.style.setProperty('--slot',String(Math.max(0,visible.indexOf(x))));
    b.innerHTML=`<span class="hero-shot-mask">${svg(x)}</span><span class="hero-shot-number">${x.id}</span>`;
    b.addEventListener('click',()=>{stopTour();request(x.id);});
    $('shot-list').append(b);buttons.set(x.id,b);
    if(event==='add'){b.classList.add('is-arriving');schedule(()=>b.classList.remove('is-arriving'),350);}
   }
   b.dataset.state=x.state;b.dataset.visible=String(x.visible);b.tabIndex=x.visible?0:-1;
   b.setAttribute('aria-label',`${t('attach')} ${x.id}${x.state==='failed'?' · '+t('failed'):''}`);
   b.setAttribute('aria-disabled',String(!x.visible||x.state==='pending'));
   if(x.state==='pending')b.setAttribute('aria-busy','true');else b.removeAttribute('aria-busy');
   if(!x.visible)b.classList.remove('is-arriving');
   let card=cards.get(x.id);
   if(x.card&&!x.cardRemoved){
    if(!card){
     card=document.createElement('div');card.className='demo-card';card.dataset.id=String(x.id);
     card.innerHTML=svg(x)+'<span><span class="card-name"></span><small></small></span><button type="button">×</button>';
     card.querySelector('button').addEventListener('click',()=>{model.removeCard(x.id);});
     $('hero-attachments').append(card);cards.set(x.id,card);
    }
    card.dataset.state=x.state;card.querySelector('.card-name').textContent=t('name')+' '+x.id;
    card.querySelector('small').textContent=t(x.state==='ready'?'complete':x.state==='unknown'?'unconfirmed':'preparing');
    card.querySelector('button').setAttribute('aria-label',t('remove')+' '+x.id);
   } else if(card){card.remove();cards.delete(x.id);}
  }
  rail.classList.toggle('is-empty',visible.length===0);
  $('hero-capture').disabled=visible.length>=3;
  const history=model.items.filter(x=>x.attempt>0);
  $('history-count').textContent=String(history.length);
  $('history-list').replaceChildren();
  if(!history.length){const li=document.createElement('li');li.textContent=t('empty');$('history-list').append(li);}
  for(const x of history){
   const li=document.createElement('li'),a=document.createElement('span'),b=document.createElement('span');
   a.textContent=t('name')+' '+x.id;
   b.textContent=t({ready:'complete',unknown:'unconfirmed',failed:'failed',pending:'waiting',started:'preparing',blocked:'waiting'}[x.state]||'waiting');
   li.dataset.state=x.state;li.append(a,b);$('history-list').append(li);
  }
  if(item)focusAfterHide(item);
  layout();
  const status={reset:'initial',add:'added',request:'request','positive-start':'start',ready:'ready',failure:'failure',unknown:'unknown','no-start':'blocked','remove-card':'removed'};
  if(status[event])say(status[event]);
  if(item)scene.dataset.phase=item.state;
  if(event==='reset')scene.dataset.phase='idle';
 }
 const model=new window.RiftletModel();model.onChange=render;
 function request(id,forced){
  const ticket=model.request(id,forced||$('scenario').value);
  if(!ticket)return false;
  // These are explicit synthetic evidence events, never real upload evidence.
  schedule(()=>{
   if(ticket.scenario==='no-start'){model.signal(ticket,'no-start');return;}
   if(!model.signal(ticket,'positive-start'))return;
   schedule(()=>{model.signal(ticket,ticket.scenario==='success'?'ready':ticket.scenario);},820);
  },240);
  return true;
 }
 function reset(count=3){stopTour();clear(timers);model.reset(count);}
 function play(){
  reset(2);tourActive=true;$('hero-pause').hidden=false;scene.dataset.phase='capture';say('tour');
  const epoch=model.epoch;
  schedule(()=>{if(epoch!==model.epoch)return;const x=model.add();if(!x)return;
   schedule(()=>{if(epoch!==model.epoch)return;request(x.id,'success');
    schedule(()=>{stopTour();},1150,tourTimers);
   },motion.matches?0:600,tourTimers);
  },motion.matches?0:400,tourTimers);
 }
 $('hero-play').addEventListener('click',play);
 $('hero-pause').addEventListener('click',()=>stopTour(true));
 $('hero-capture').addEventListener('click',()=>{stopTour();if(!model.add())say('full');});
 $('reset').addEventListener('click',()=>reset());
 $('desktop-theme').addEventListener('click',()=>{document.querySelector('.hero-desktop').classList.toggle('dark');updateThemeText();});
 $('history-toggle').addEventListener('click',()=>{const open=$('demo-history').hidden;$('demo-history').hidden=!open;$('history-toggle').setAttribute('aria-expanded',String(open));});
 $('hero-draft').addEventListener('input',()=>{edited=true;stopTour();});
 $('language-toggle').addEventListener('click',()=>setLanguage(language==='zh'?'en':'zh'));
 $('try-it').addEventListener('click',e=>{e.preventDefault();stopTour();scene.scrollIntoView({behavior:motion.matches?'instant':'smooth',block:'center'});const first=model.items.find(x=>x.visible);if(first){keyboard=true;buttons.get(first.id)?.focus({preventScroll:true});}});
 rail.addEventListener('pointerenter',e=>{if(e.pointerType==='mouse')held=true;});
 rail.addEventListener('pointerleave',()=>{held=false;layout();});
 rail.addEventListener('focusin',()=>{if(keyboard)held=true;});
 rail.addEventListener('focusout',()=>requestAnimationFrame(()=>{if(!rail.contains(document.activeElement)){held=false;layout();}}));
 document.addEventListener('pointerdown',()=>{keyboard=false;},true);
 document.addEventListener('keydown',e=>{if(['Tab','Enter',' '].includes(e.key))keyboard=true;if(e.key==='Escape')stopTour(true);},true);
 motion.addEventListener('change',()=>{if(motion.matches)stopTour(true);});
 document.addEventListener('visibilitychange',()=>{if(document.hidden)stopTour();});
 window.addEventListener('pagehide',()=>{stopTour();clear(timers);});
 window.addEventListener('pageshow',e=>{if(e.persisted){for(const x of model.items){if(['pending','started'].includes(x.state))model.signal({id:x.id,attempt:x.attempt,epoch:model.epoch,target:'synthetic-draft-only'},x.state==='started'?'unknown':'no-start');}}});
 // Intentionally no automatic loop or automatically initiated attachment.
 window.RiftletDemo={snapshot:()=>model.snapshot(),request,reset,add:()=>model.add(),signal:(...args)=>model.signal(...args),setLanguage,play,stopTour};
 render('reset');setLanguage(new URLSearchParams(location.search).get('lang')==='en'?'en':'zh');
})();
