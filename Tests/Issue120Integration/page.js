'use strict';
// Isolated fixture site. The JS resource under test is served separately,
// byte-for-byte from the program the Swift driver bound from its built bundle.
function auditFixture(win) {
  const assignments = [], events = [];
  let sends = 0;
  const proto = win.HTMLInputElement.prototype;
  const files = Object.getOwnPropertyDescriptor(proto,'files');
  Object.defineProperty(proto,'files',{...files,set(value) {
    assignments.push({input:this,files:Array.from(value)});
    files.set.call(this,value);
  }});
  for (const name of ['input','change']) win.document.addEventListener(name,event=>{
    if (event.target.type === 'file') events.push({name,input:event.target});
  },true);
  win.document.addEventListener('click',event=>{if (event.target.closest('button[type=submit]')) sends++;},true);
  win.document.addEventListener('submit',event=>{event.preventDefault();sends++;},true);
  win.HTMLFormElement.prototype.submit = () => {sends++;};
  return {assignments,events,get sends(){return sends;}};
}

// The fixture transport owns the draft generation. A text edit can keep both
// the navigation entry and the editor element alive. Retire this one page pin
// on the first edit, including edit-and-restore before the next observation.
function pinFixtureDraft(provider, click, editor) {
  const handle = provider.pin(click);
  const edits = new MutationObserver(close);
  edits.observe(editor,{subtree:true,childList:true,characterData:true});
  function close() { edits.disconnect(); handle.close(); }
  function original() {
    if (edits.takeRecords().length) close();
    return handle;
  }
  return {
    current:() => original().current(),
    commit:(ticket,file) => original().commit(ticket,file),
    observe:ticket => original().observe(ticket),
    close
  };
}

async function run(token, click, otherOrigin, dropReply) {
  const editor = document.querySelector('[contenteditable]'), lane = document.querySelector('[data-fixture-lane]');
  const old = lane.firstElementChild, picker = document.querySelector('#picker');
  editor.focus();
  const text = editor.firstChild, sel = getSelection();
  sel.setBaseAndExtent(text,2,text,6);
  const expected = sel.toString();
  const audit = auditFixture(window);
  let card, digest, member, ticket, key, rendering;
  const syntheticDocument = crypto.randomUUID(), editorID = crypto.randomUUID(), epoch = navigation.currentEntry.id;
  const digestOf = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))]
    .map(b=>b.toString(16).padStart(2,'0')).join('');
  picker.addEventListener('change',()=>{
    if (dropReply) return; // The fixture renders no correlated card for this input.
    rendering = (async () => {
      const file = picker.files[0], bytes = await file.arrayBuffer();
      card = document.createElement(old.localName); card.ariaLabel = file.name;
      member = crypto.randomUUID();
      const image = new Image(); image.alt = file.name;
      image.src = 'data:image/png;base64,'+btoa(String.fromCharCode(...new Uint8Array(bytes)));
      card.append(image);lane.append(card);await image.decode();
    })();
  });
  const compiled = await (await fetch('/'+token+'/program.js')).text();
  const prefix='const fixtureProvider = ', suffix=';\n';
  if (!compiled.startsWith(prefix) || !compiled.endsWith(suffix)) throw Error('program envelope');
  const programDigest=await digestOf(new TextEncoder().encode(compiled.slice(prefix.length,-suffix.length)));
  const pin = pinFixtureDraft(fixtureProvider,click,editor);
  const identities = {document:syntheticDocument,editor:editorID,epoch};
  async function reply(data) {
    const result=await fetch('/'+token+'/reply',{method:'POST',body:JSON.stringify(data)});
    if (!result.ok) throw Error('exchange rejected');
  }
  await reply({action:'pin',result:'pinned',digest:programDigest,...identities});
  for (;;) {
    const cmd=await (await fetch('/'+token+'/next')).json();
    try {
      switch(cmd.action) {
        case 'validate':
          await reply({action:cmd.action,result:pin.current() ? 'current':'unavailable',...identities});
          break;
        case 'commit': {
          if (key) throw Error('second bridge commit');
          key=cmd.identity;
          ticket=JSON.parse(key);
          if (ticket.click!==click || ticket.profileDigest!==programDigest ||
              Object.entries(identities).some(([k,v])=>ticket[k]!==v)) throw Error('different click');
          const body=Uint8Array.from(atob(cmd.body),c=>c.charCodeAt(0));
          const file=new File([body],'riftlet-'+ticket.operation+'.png',{type:'image/png'});
          const result=await pin.commit(ticket,file);
          await rendering;
          if (picker.files.length !== 1 || picker.files[0] !== file ||
              audit.assignments.length !== 1 || audit.assignments[0].files[0] !== file) throw Error('file assignment');
          if (typeof claudeCounterexamples === 'function') {
            const replacement = document.createElement('input');
            replacement.type='file'; replacement.id=picker.id; replacement.hidden=true;
            picker.replaceWith(replacement);
            if (pin.current()) throw Error('old writer remained current');
            let refused=false;
            try {await pin.commit(ticket,file);} catch {refused=true;}
            if (!refused || replacement.files.length) throw Error('rebuilt picker was written');
          }
          await reply({action:cmd.action,result,identity:key});
          break;
        }
        case 'observe': {
          if (!key || key!==cmd.identity) throw Error('different invocation');
          const result=await pin.observe(ticket);
          if (result==='accepted_into_draft') {
            const image=card.querySelector('img');
            const payload=Uint8Array.from(atob(image.currentSrc.split(',')[1]),c=>c.charCodeAt(0));
            digest=await digestOf(payload);
            if (digest!==ticket.payloadSHA256) throw Error('observed preview digest mismatch');
          }
          await reply({action:cmd.action,result,identity:key,card:member,digest});
          break;
        }
        case 'fail': {
          const error=document.createElement('div');
          error.role='alert';error.ariaLabel='failed';error.textContent='Fixture upload failed';
          card.replaceChildren(error);
          await reply({action:cmd.action,result:'original-card-updated'});
          break;
        }
        case 'finish': {
          const preserved=old.parentElement===lane && sel.toString()===expected &&
            sel.anchorNode===text && sel.focusNode===text && sel.anchorOffset===2 && sel.focusOffset===6 &&
            editor.textContent==='original draft' && old.textContent==='prior test attachment';
          const setters=audit.assignments.length, sends=audit.sends;
          const foreign=audit.events.filter(e=>e.input!==picker).length;
          const inputs=audit.events.filter(e=>e.name==='input').length, changes=audit.events.length-inputs;
          if (!preserved || sends!==0 || foreign!==0 || changes!==1 || inputs!==1 ||
              setters!==1 || audit.assignments[0].input!==picker || audit.events[0].name!=='input' ||
              (dropReply ? lane.children.length!==1 : card.parentElement!==lane || lane.children.length!==2))
            throw Error('independent counts or original changed');
          pin.close();
          let counterexamples;
          if (typeof claudeCounterexamples === 'function' && !dropReply) {
            let scenario='cross-origin', timer;
            const deadline=new Promise((_,reject)=>{
              timer=setTimeout(()=>reject(Error('unfinished fixture case '+scenario)),10000);
            });
            try {
              counterexamples=await Promise.race([deadline,claudeCounterexamples(otherOrigin,name=>{scenario=name;})]);
            } finally {clearTimeout(timer);}
          }
          await reply({action:'finish',result:'checked',setters,inputs,changes,foreign,sends,counterexamples,
            oldAttachmentsPreserved:true,textAndSelectionPreserved:true});
          return;
        }
        default: throw Error('unknown command');
      }
    } catch(e) {
      await reply({action:cmd.action,result:'error',reason:String(e.message)});
      return;
    }
  }
}
