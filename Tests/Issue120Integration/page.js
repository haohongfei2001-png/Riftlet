'use strict';
// Isolated fixture site. The JS resource under test is served separately,
// byte-for-byte from the program the Swift driver bound from its built bundle.
async function run(token, click) {
  const editor = document.querySelector('[contenteditable]'), lane = document.querySelector('section');
  const old = lane.firstElementChild, picker = document.querySelector('#picker');
  editor.focus();
  const text = editor.firstChild, sel = getSelection();
  sel.setBaseAndExtent(text,2,text,6);
  const expected = sel.toString();
  let inputs=0, changes=0, sends=0, foreign=0, card, digest, member, ticket, key, rendering;
  const syntheticDocument = crypto.randomUUID(), editorID = crypto.randomUUID(), epoch = navigation.currentEntry.id;
  const digestOf = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))]
    .map(b=>b.toString(16).padStart(2,'0')).join('');
  document.forms[0].onsubmit = e => {e.preventDefault();sends++};
  document.querySelector('#foreign').onchange = () => {foreign++};
  picker.addEventListener('input',()=>inputs++);
  picker.addEventListener('change',()=>{
    changes++;
    rendering = (async () => {
      const file = picker.files[0], bytes = await file.arrayBuffer();
      digest = await digestOf(bytes);
      card = document.createElement('article'); card.ariaLabel = file.name;
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
  const pin = fixtureProvider.pin(click);
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
          await reply({action:cmd.action,result,identity:key});
          break;
        }
        case 'observe':
          if (!key || key!==cmd.identity) throw Error('different invocation');
          await reply({action:cmd.action,result:await pin.observe(ticket),identity:key,card:member,digest});
          break;
        case 'fail': {
          const error=document.createElement('div');
          error.role='alert';error.ariaLabel='failed';error.textContent='Fixture upload failed';
          card.replaceChildren(error);
          await reply({action:cmd.action,result:'original-card-updated'});
          break;
        }
        case 'finish': {
          const preserved=old.parentElement===lane && sel.toString()===expected &&
            sel.anchorNode===text && sel.focusNode===text && editor.textContent==='original draft';
          if (!preserved || sends!==0 || foreign!==0 || changes!==1 || inputs!==1 ||
              card.parentElement!==lane || lane.children.length!==2) throw Error('independent counts or original changed');
          pin.close();
          await reply({action:'finish',result:'checked',inputs,changes,foreign,sends,
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
