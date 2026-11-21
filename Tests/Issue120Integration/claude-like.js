'use strict';
// Runs only on the synthetic loopback page. Each case gets its own real document,
// original editor and bound copy of the generic program exported by Swift.
function refusesPin(provider) {
  try { provider.pin(crypto.randomUUID()); } catch (error) { return error.message === 'target_unavailable'; }
  return false;
}

async function claudeCounterexamples(otherOrigin, reportCase) {
  const results = [];
  const route = '/fixture-claude-like';
  const frame = document.createElement('iframe');
  document.body.append(frame);
  const load = url => new Promise((resolve,reject) => {
    const timer = setTimeout(()=>reject(Error('fixture frame did not load '+url)), 4000);
    frame.onload = () => {clearTimeout(timer); resolve();};
    frame.src = url;
  });
  const check = (ok, label) => { if (!ok) throw Error(label); };
  async function refused(action, reason) {
    try { await action(); } catch (error) { check(error.message === reason, error.message); return; }
    throw Error('expected ' + reason);
  }
  const otherReport = new Promise((resolve,reject) => {
    const timer = setTimeout(()=>reject(Error('missing cross-origin refusal')), 4000);
    function receive(event) {
      if (event.source !== frame.contentWindow || event.origin !== otherOrigin) return;
      window.removeEventListener('message', receive);
      clearTimeout(timer);
      resolve(event.data);
    }
    window.addEventListener('message', receive);
  });
  try {
    const [,cross] = await Promise.all([load(otherOrigin + route),otherReport]);
    check(cross.state === 'other_route' && cross.refused, 'same path on another loopback port');
    results.push('cross-origin');
    await load('/wrong-path');
    const other = frame.contentWindow.localProvider;
    check(other.inspect() === 'other_route' && refusesPin(other), 'same origin on another path');
    results.push('wrong-path');

    const body = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZsAAAAASUVORK5CYII='), c=>c.charCodeAt(0));
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',body)), b=>b.toString(16).padStart(2,'0')).join('');
    const encoded = 'data:image/png;base64,'+btoa(String.fromCharCode(...body));

    async function runCase(name, writes, exercise) {
      reportCase(name);
      await load(route);
      const win = frame.contentWindow, doc = win.document, api = win.localProvider;
      const editor = doc.querySelector('[data-fixture-editor]'), lane = doc.querySelector('[data-fixture-lane]');
      const picker = doc.querySelector('#picker'), trigger = doc.querySelector('[data-fixture-upload]');
      win.focus(); editor.focus();
      const audit = auditFixture(win);
      const ticket = {click:crypto.randomUUID(), operation:crypto.randomUUID(), invocation:crypto.randomUUID(),
        payloadSHA256:digest, originalSHA256:digest};
      const file = new win.File([body],'riftlet-'+ticket.operation+'.png',{type:'image/png'});
      let handle;
      const pin = () => { handle = pinFixtureDraft(api,ticket.click,editor); return handle; };
      const commit = () => handle.commit(ticket,file);
      const observe = () => handle.observe(ticket);
      async function preview(parent=lane, src=encoded, srcset, filename=file.name) {
        const card = doc.createElement('li'), image = new win.Image();
        card.ariaLabel = image.alt = filename;
        if (srcset) image.srcset = srcset+' 1x';
        image.src = src;
        card.append(image); parent.append(card); await image.decode();
        check(image.currentSrc === (srcset || src), name+' effective preview');
      }
      try {
        if (writes) {
          pin();
          check(await commit() === 'input_returned',name+' dispatch');
        }
        await exercise({doc,win,editor,trigger,lane,api,ticket,pin,commit,observe,preview,handle});
        check(audit.assignments.length === writes && audit.assignments.every(a =>
          a.input === picker && a.files.length === 1 && a.files[0] === file), name+' assignments');
        check(audit.events.every(e=>e.input === picker) && audit.events.map(e=>e.name).join(',') ===
          (writes ? 'input,change' : '') && audit.sends === 0, name+' events');
        results.push(name);
      } finally { handle?.close(); }
    }

    await runCase('ambiguous-action',0,({trigger,api})=>{
      trigger.after(trigger.cloneNode(true));
      check(api.inspect() === 'upload_control_unavailable' && refusesPin(api),'two upload actions');
    });
    await runCase('foreign-picker',0,async ({trigger,pin,commit})=>{
      trigger.setAttribute('aria-controls','foreign'); pin();
      await refused(commit,'owned_input_unavailable');
    });
    await runCase('wrong-editor',0,async ({editor,pin,commit})=>{
      pin(); editor.replaceWith(editor.cloneNode(true));
      await refused(commit,'target_or_payload_changed');
    });
    await runCase('wrong-invocation',1,async ({preview,handle,ticket,observe})=>{
      await preview();
      check(await handle.observe({...ticket,invocation:crypto.randomUUID()}) === 'unavailable','foreign invocation');
      check(await observe() === 'accepted_into_draft','original invocation with identical preview');
    });

    async function noStart(name, arrange) {
      await runCase(name,1,async ctx=>{
        await arrange(ctx);
        const state = await ctx.observe();
        check(state === 'unknown' || state === 'unavailable',name+' '+state);
        check(await ctx.observe() === state,name+' repeat observation');
        await refused(ctx.commit,ctx.handle.current() ? 'input_fenced' : 'target_or_payload_changed');
      });
    }
    await noStart('foreign-draft-card',({doc,preview})=>preview(doc.forms[1]));
    await noStart('adjacent-card',async ({doc,lane,preview})=>{
      await preview(lane,doc.createElement('canvas').toDataURL());
      await preview(lane,encoded,undefined,'adjacent.png');
    });
    await noStart('duplicate-card',async ({preview})=>{await preview(); await preview();});
    await noStart('wrong-bytes',({doc,lane,preview})=>preview(lane,doc.createElement('canvas').toDataURL()));
    await noStart('responsive-source',({doc,lane,preview})=>preview(lane,encoded,doc.createElement('canvas').toDataURL()));
    await noStart('prior-card-removed',async ({lane,preview})=>{
      await preview(); lane.firstElementChild.remove();
    });
    await noStart('navigation',async ({win,preview})=>{
      await preview();
      win.history.pushState({},'', '/elsewhere');
      win.history.replaceState({},'',route);
    });
    await runCase('same-url-new-document',1,async ({doc,preview,handle,ticket})=>{
      await preview();
      await load(route);
      check(frame.contentDocument !== doc && frame.contentWindow.location.pathname === route,'new document at original URL');
      // A discarded document cannot deliver an asynchronous reply. Check the
      // old handle synchronously and exercise the replacement's reader too.
      check(!handle.current(),'stale writer survived reload');
      const replacement = frame.contentWindow.localProvider.pin(crypto.randomUUID());
      try {
        check(await replacement.observe(ticket) === 'unavailable','replacement inherited invocation');
        check(frame.contentDocument.querySelector('#picker').files.length === 0,'replacement picker changed');
      } finally { replacement.close(); }
    });
    await runCase('draft-edit-before-input',0,async ({editor,pin,commit})=>{
      pin(); editor.firstChild.data += ' edited';
      await refused(commit,'target_or_payload_changed');
    });
    await noStart('draft-edit-before-receipt',async ({editor,preview})=>{
      await preview();
      const original = editor.firstChild.data;
      editor.firstChild.data += ' edited';
      editor.firstChild.data = original;
    });
    return results;
  } finally { frame.remove(); }
}
