/* A bounded, browser-local story. No capture APIs, files, network or message send. */
(() => {
  'use strict';
  const scene = document.getElementById('hero-scene');
  if (!scene) return;
  const $ = id => document.getElementById(id);
  const buttons = [...scene.querySelectorAll('[data-shot]')];
  const draft = $('hero-draft'), cards = $('hero-attachments');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const copy = {
    zh: {play:'看一次完整操作', replay:'再看一次', capture:'模拟截图', collected:'已收录', pause:'暂停演示', idle:'两次操作，回到你的思路。', captureStatus:'01  照常截下这一块。', captured:'02  新截图在边缘。点一下它。', pending:'正在准备示例附件…', started:'已模拟开始附加，微图已收起。', ready:'图片留在草稿，你继续写。', paused:'演示已暂停，也可以直接点边缘的截图。', hint:'你的截图，在这里', draft:'帮我看看这个页面，还能如何改进？', item:'把截图 {id} 放入演示草稿', name:'截图 {id}', preparing:'准备中…', done:'已就绪 · 未发送'},
    en: {play:'See it in action', replay:'Watch again', capture:'Try a capture', collected:'Captured', pause:'Pause demo', idle:'Two actions. Back to your thought.', captureStatus:'01  Capture something as usual.', captured:'02  It is at the edge. Click it.', pending:'Preparing the example attachment…', started:'Attachment start simulated. Thumbnail tucked away.', ready:'The image stays. Keep writing.', paused:'Paused. You can click the edge yourself.', hint:'Your captures, here', draft:'How could I improve this page?', item:'Add screenshot {id} to the demo draft', name:'Capture {id}', preparing:'Preparing…', done:'Ready · Not sent'}
  };
  let lang = document.documentElement.lang === 'en' ? 'en' : 'zh';
  let story = null, transfer = null, played = false, edited = false;
  let queue = [], active = false, epoch = 0, statusKey = 'idle';
  let pointerInside = false, keyboardInside = false, keyboardMode = false, needsCompact = false;
  const text = (key,id='') => copy[lang][key].replace('{id}',String(id));
  const setPhase = phase => { scene.dataset.phase = phase; };
  function say(key) { statusKey=key; $('hero-status').textContent=text(key); }
  function refresh() {
    lang=document.documentElement.lang === 'en' ? 'en' : 'zh';
    scene.querySelectorAll('[data-hero-copy]').forEach(n => {
      if(n.id !== 'hero-status') n.textContent=text(n.dataset.heroCopy);
    });
    $('hero-play').querySelector('[data-hero-copy]').textContent=text(played?'replay':'play');
    $('hero-capture').setAttribute('aria-label',text('capture'));
    $('hero-capture').querySelector('[data-hero-copy]').textContent=text(buttons[2].dataset.state==='absent'?'capture':'collected');
    scene.querySelector('.hero-source-art').setAttribute('aria-label',lang==='en'?'Synthetic homepage layout and revision notes':'合成的页面排版与修改笔记');
    scene.setAttribute('aria-label',lang==='en'?'Screenshot-to-draft web demonstration':'截图进入草稿的网页演示');
    $('hero-edge').setAttribute('aria-label',lang==='en'?'Demo screenshot queue':'首屏截图队列');
    cards.setAttribute('aria-label',lang==='en'?'Hero demo attachments':'首屏演示附件');
    buttons.forEach(b=>b.setAttribute('aria-label',text('item',b.dataset.shot)));
    cards.querySelectorAll('.hero-attachment').forEach(card => {
      card.querySelector('span').textContent=text('name',card.dataset.id);
      card.querySelector('small').textContent=text(card.dataset.ready==='true'?'done':'preparing');
    });
    if(!edited)draft.value=text('draft');
    say(statusKey);
  }
  function wait(ms,signal) {
    return new Promise((resolve,reject)=>{
      if(signal.aborted){reject(new DOMException('Aborted','AbortError'));return;}
      const finish=()=>{signal.removeEventListener('abort',abort);resolve();};
      const timer=setTimeout(finish,ms);
      const abort=()=>{clearTimeout(timer);reject(new DOMException('Aborted','AbortError'));};
      signal.addEventListener('abort',abort,{once:true});
    });
  }
  function pause(announce=false) {
    if(story){story.abort();story=null;}
    $('hero-pause').hidden=true;
    if(scene.dataset.phase==='point')setPhase('captured');
    // Stopping the walkthrough must not cancel an attachment already being illustrated.
    if(announce) say('paused');
  }
  function compact() {
    if(!needsCompact||pointerInside||keyboardInside)return;
    buttons.filter(b=>!['done','absent'].includes(b.dataset.state)).forEach((b,i)=>b.style.setProperty('--slot',i));
    needsCompact=false;
    $('hero-edge').classList.toggle('empty', buttons.every(b=>['done','absent'].includes(b.dataset.state)));
  }
  function reset() {
    pause();if(transfer)transfer.abort();epoch++;active=false;queue=[];needsCompact=false;cards.replaceChildren();
    buttons.forEach((b,i)=>{b.dataset.state=i===2?'absent':'available';b.disabled=i===2;b.tabIndex=i===2?-1:0;b.style.setProperty('--slot',i);b.classList.remove('is-arriving');b.removeAttribute('aria-busy');});
    $('hero-capture').disabled=false;$('hero-edge').classList.remove('empty');setPhase('idle');say('idle');
  }
  function reveal() {
    const b=buttons[2];
    if(b.dataset.state==='absent') {
      b.dataset.state='available';b.disabled=false;b.tabIndex=0;b.classList.add('is-arriving');
    }
    $('hero-capture').disabled=true;$('hero-edge').classList.remove('empty');refresh();setPhase('captured');say('captured');
  }
  function append(button) {
    if(button.dataset.state!=='available')return;
    button.classList.remove('is-arriving'); // Release entrance animation before pending/exit transitions.
    button.dataset.state='queued';button.setAttribute('aria-busy','true');queue.push(button);void drain();
  }
  async function drain() {
    if(active||!queue.length)return;
    active=true;const button=queue.shift(),ticket=epoch;
    const controller=new AbortController();transfer=controller;
    button.dataset.state='pending';setPhase('pending');say('pending');
    try {
      await wait(320,controller.signal);if(ticket!==epoch)return;
      const card=document.createElement('div');card.className='hero-attachment';card.dataset.id=button.dataset.shot;card.dataset.ready='false';
      card.append(button.querySelector('svg').cloneNode(true));
      const label=document.createElement('div'),name=document.createElement('span'),state=document.createElement('small');
      name.textContent=text('name',button.dataset.shot);state.textContent=text('preparing');label.append(name,state);card.append(label);cards.append(card);
      // Synthetic positive start signal: visual exit is intentionally earlier than final ready.
      button.dataset.state='done';button.removeAttribute('aria-busy');button.tabIndex=-1;
      $('hero-edge').classList.toggle('empty',buttons.every(b=>['done','absent'].includes(b.dataset.state)));
      setPhase('started');say('started');needsCompact=true;
      await wait(180,controller.signal);if(ticket!==epoch)return;
      compact();
      await wait(340,controller.signal);if(ticket!==epoch)return;
      card.dataset.ready='true';state.textContent=text('done');
      setPhase('ready');say('ready');
    } catch(error) {if(error.name!=='AbortError')throw error;}
    finally {if(ticket===epoch){active=false;void drain();}}
  }
  async function play() {
    played=true;reset();refresh();
    const controller=new AbortController();story=controller;$('hero-pause').hidden=false;
    try {
      setPhase('capture');say('captureStatus');await wait(motion.matches?0:720,controller.signal);
      reveal();await wait(motion.matches?0:850,controller.signal);
      setPhase('point');await wait(motion.matches?0:600,controller.signal);
      append(buttons[2]);await wait(1150,controller.signal);
    } catch(error) {if(error.name!=='AbortError')throw error;}
    finally {if(story===controller){story=null;$('hero-pause').hidden=true;}}
  }
  $('hero-play').addEventListener('click',()=>void play());
  $('hero-pause').addEventListener('click',()=>pause(true));
  $('hero-capture').addEventListener('click',()=>{played=true;pause();reveal();refresh();});
  buttons.forEach(b=>b.addEventListener('click',()=>{played=true;pause();refresh();append(b);}));
  const edge=$('hero-edge');
  edge.addEventListener('pointerenter',()=>{pointerInside=true;pause();});
  edge.addEventListener('pointerleave',()=>{pointerInside=false;compact();});
  document.addEventListener('keydown',e=>{if(['Tab','Enter',' '].includes(e.key))keyboardMode=true;},true);
  document.addEventListener('pointerdown',()=>{keyboardMode=false;keyboardInside=false;},true);
  edge.addEventListener('focusin',()=>{keyboardInside=keyboardMode;pause();});
  edge.addEventListener('focusout',()=>requestAnimationFrame(()=>{keyboardInside=keyboardMode&&edge.contains(document.activeElement);compact();}));
  draft.addEventListener('input',()=>{edited=true;pause();});
  new MutationObserver(refresh).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
  motion.addEventListener('change',()=>{if(motion.matches)pause(true);});
  document.addEventListener('visibilitychange',()=>{if(document.hidden)pause();});
  // One finite introduction only; never a looping decoration. User input takes over.
  if('IntersectionObserver' in window) {
    const observer=new IntersectionObserver(entries=>{
      if(entries[0].isIntersecting&&!played&&!motion.matches&&!document.hidden){played=true;void play();}
      else if(!entries[0].isIntersecting)pause();
    },{threshold:.55});observer.observe(scene);
  }
  refresh();
})();
