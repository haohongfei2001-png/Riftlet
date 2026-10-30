/* Site UI. All demo content is synthetic and ephemeral. No network or storage. */
(function(){
'use strict';
var zh=document.body.dataset.locale==='zh', assets=document.body.dataset.assets;
var $=function(id){return document.getElementById(id);};
var text=zh?{
 idle:'点一下右侧边缘的小图。',captured:'新截图已在边缘等候。选择一张，放进草稿。',checking:'正在检查目标草稿；图片仍在原位。',started:'模拟确认：已经开始附加，小图现在离场。',uploading:'小图已进入边界，附件仍在草稿中处理中。',ready:'图片已在示例草稿中。原文字与附件保留，未发送。',failed:'模拟明确失败：同一张图已回到原位。你可以再次点击。',unknown:'结果尚不确定。记录留在历史中，不重复附加。','no-start':'没有取得开始信号。图片留在原位。','unknown-before-start':'结果待核实；图片保留，禁止盲目重复附加。','resolved-ready':'模拟核对：图片已就绪，没有重新附加。','resolved-failed':'模拟核对：明确失败，原图恢复。',existing:'原有附件',shot:'截图',wait:'处理中',unconfirmed:'待核实',done:'已附加',available:'边缘待用',historyNone:'尚无历史。',phase1:'01 / 截图在边缘',phase2:'02 / 交接进行中',phase3:'03 / 留在草稿',events:'模拟事件'
}:{idle:'Click the small image at the right edge.',captured:'A new screenshot is waiting. Choose one to add to the draft.',checking:'Checking the target draft. The image stays at the edge.',started:'Simulated start confirmed. The thumbnail can now leave.',uploading:'The thumbnail has left. The attachment is still processing in the draft.',ready:'The image is in the sample draft. Your words and existing attachment stay. Nothing is sent.',failed:'Simulated confirmed failure. The same image is back and can be clicked again.',unknown:'The result is uncertain. It stays in history, without another upload.','no-start':'No attachment start was confirmed. The image stays at the edge.','unknown-before-start':'Unconfirmed before start. Kept at the edge, with repeat uploads blocked.','resolved-ready':'Simulated check: ready, without another upload.','resolved-failed':'Simulated check: confirmed failure. The original image is available.',existing:'Existing attachment',shot:'Screenshot',wait:'Processing',unconfirmed:'Unconfirmed',done:'Attached',available:'Waiting at edge',historyNone:'No history yet.',phase1:'01 / At the edge',phase2:'02 / Handoff',phase3:'03 / In the draft',events:'Simulated event'};
var sample={ 'shot-1':'sample-landscape.svg','shot-2':'sample-portrait.svg','shot-3':'sample-wide.svg'};
var previous={},lastStatus='',announcerTimer=0,scriptedTimer=0,flashTimer=0;
var model=new RiftletDemo.Model({onChange:render});
function name(id){return text.shot+' '+id.split('-')[1];}
function setStatus(value,key){
 if(key===lastStatus)return;
 lastStatus=key;clearTimeout(announcerTimer);
 // Compress intermediate announcements so assistive technology receives the outcome.
 if(key==='started'||key==='uploading')announcerTimer=setTimeout(function(){$('demo-status').textContent=value;},100);
 else $('demo-status').textContent=value;
}
function render(state){
 $('demo-stage').dataset.phase=state.phase;
 var shown=0,focusLeaves=state.busy&&document.activeElement===$('test-scenario');
 ['shot-1','shot-2','shot-3'].forEach(function(id){
  var el=$(id),item=state.items.find(function(i){return i.id===id;});
  if(!item){el.hidden=true;delete previous[id];return;}
  var before=previous[id];if((!item.visible||state.busy)&&document.activeElement===el)focusLeaves=true;el.dataset.state=item.status;el.hidden=!item.visible;
  el.disabled=state.busy||item.status!=='available';el.setAttribute('aria-label',(zh?'附加示例截图 ':'Attach sample screenshot ')+id.split('-')[1]+(item.status==='unknown'?' — '+text.unconfirmed:''));
  if(item.visible){el.style.setProperty('--slot',(shown*61)+'px');shown++;}
  if(!before&&state.messageKey==='captured'&&$('arrival-mode').value==='magnetic'&&!document.body.classList.contains('motion-off')){el.classList.remove('arriving');void el.offsetWidth;el.classList.add('arriving');}
  if(before&&before.status==='swallowing'&&item.status==='uploading')el.classList.remove('arriving');
  previous[id]={status:item.status,visible:item.visible};
 });
 if(focusLeaves)$('history-toggle').focus({preventScroll:true});
 $('rift-rail').dataset.empty=shown===0?'true':'false';$('edge-hint').hidden=shown!==1||state.busy;
 // Preserve the existing attachment and the editable textarea. Only synthetic additions change.
 var list=$('attachments');
 Array.from(list.querySelectorAll('.attachment')).forEach(function(el){if(!state.attachments.some(function(a){return a.id===el.dataset.id;}))el.remove();});
 state.attachments.forEach(function(a){
  var el=list.querySelector('[data-id="'+a.id+'"]');
  if(!el){el=document.createElement('span');el.className='attachment';el.dataset.id=a.id;var img=document.createElement('img');img.src=assets+sample[a.id];img.alt='';img.width=29;img.height=22;el.appendChild(img);var label=document.createElement('span');label.className='att-name';label.textContent=name(a.id);el.appendChild(label);var status=document.createElement('span');status.className='att-state';el.appendChild(status);list.appendChild(el);}
  el.dataset.state=a.status;el.querySelector('.att-state').textContent=a.status==='ready'?'✓':a.status==='unknown'?'?':'';
  el.setAttribute('aria-label',name(a.id)+' — '+(a.status==='ready'?text.done:a.status==='unknown'?text.unconfirmed:text.wait));
 });
 $('capture').disabled=state.busy||state.items.length>=3;
 $('capture').title=state.items.length>=3?(zh?'本次示例最多三张，重新体验可清空示例。':'This example holds three samples. Restart to clear sample images.'):'';
 $('try-demo').disabled=state.busy;$('test-scenario').disabled=state.busy;
 setStatus(text[state.messageKey]||text.idle,state.messageKey);
 $('demo-step').textContent=state.busy?text.phase2:state.phase==='unknown'?(zh?'待核实':'Awaiting confirmation'):state.phase==='ready'?text.phase3:text.phase1;
 var history=$('history-items');history.replaceChildren();
 state.items.forEach(function(item){var li=document.createElement('li');li.textContent=name(item.id)+' — '+(item.status==='unknown'?text.unconfirmed:item.status==='ready'?text.done:item.status==='available'?text.available:text.wait);history.appendChild(li);});
 var log=$('event-log');log.replaceChildren();state.events.forEach(function(event){var li=document.createElement('li');li.textContent=event.type+(event.id?' · '+event.id:'');log.appendChild(li);});
}
function clearScripted(){clearTimeout(scriptedTimer);clearTimeout(flashTimer);$('source-window').classList.remove('is-capturing');}
function scrollDemo(){var el=$('experience');el.scrollIntoView({behavior:document.body.classList.contains('motion-off')||window.matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth',block:'center'});}
function capture(){var id=model.capture();if(!id)return;$('source-window').classList.add('is-capturing');clearTimeout(flashTimer);flashTimer=setTimeout(function(){$('source-window').classList.remove('is-capturing');},600);}
['shot-1','shot-2','shot-3'].forEach(function(id){$(id).addEventListener('click',function(){clearScripted();model.attach(id,$('scenario').value);});$(id).addEventListener('animationend',function(){$(id).classList.remove('arriving');});});
$('capture').addEventListener('click',capture);
$('reset').addEventListener('click',function(){clearScripted();model.reset();});
$('try-demo').addEventListener('click',function(){
 clearScripted();model.reset();$('scenario').value='success';scrollDemo();
 // Invite the user's own click; no fabricated cursor and no automatic transfer.
 scriptedTimer=setTimeout(function(){$('shot-1').focus({preventScroll:true});},window.matchMedia('(prefers-reduced-motion: reduce)').matches?0:450);
});
$('test-scenario').addEventListener('click',function(){clearScripted();model.reset();scrollDemo();scriptedTimer=setTimeout(function(){model.attach('shot-1',$('scenario').value);},350);});
$('page-theme').addEventListener('click',function(){var dark=document.body.classList.toggle('dark');this.setAttribute('aria-pressed',String(dark));});
$('desktop-theme').addEventListener('click',function(){var dark=$('demo-stage').dataset.desktop!=='dark';$('demo-stage').dataset.desktop=dark?'dark':'light';this.setAttribute('aria-pressed',String(dark));});
$('history-toggle').addEventListener('click',function(){var open=this.getAttribute('aria-expanded')!=='true';this.setAttribute('aria-expanded',String(open));$('history-panel').hidden=!open;});
$('privacy-link').addEventListener('click',function(){$('privacy').open=true;});
document.querySelectorAll('a[href="#experience"]').forEach(function(a){a.addEventListener('click',function(){setTimeout(function(){$('shot-1').focus({preventScroll:true});},400);});});
// A visible QA preference can be applied by the review harness; the normal page follows the OS.
if(new URLSearchParams(location.search).get('motion')==='reduced')document.body.classList.add('motion-off');
render(model.snapshot());
window.addEventListener('pagehide',function(){clearScripted();clearTimeout(announcerTimer);$('demo-draft').value=$('demo-draft').defaultValue;model.dispose();});
window.addEventListener('pageshow',function(event){if(event.persisted){previous={};lastStatus='';model=new RiftletDemo.Model({onChange:render});render(model.snapshot());}});
})();
