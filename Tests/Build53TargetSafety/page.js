/* Controlled loopback composer. The build-53 page resource is served byte-for-byte.
 * Its location parameter maps this fixture's real navigation to the supported route.
 * All DOM, visibility, navigation, selection and file events belong to this renderer. */
'use strict';
(() => {
  const instance = crypto.randomUUID();
  const editor = document.querySelector('[contenteditable]');
  const prior = document.querySelector('[data-file-name]');
  const originalText = editor.textContent;
  const key = 'counts:' + location.pathname.split('/')[2];
  const zero = {setter:0, input:0, change:0, send:0};
  function totals() { return JSON.parse(localStorage.getItem(key) || JSON.stringify(zero)); }
  function record(name) {
    const c = totals();
    c[name]++;
    localStorage.setItem(key, JSON.stringify(c));
  }
  const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'files');
  Object.defineProperty(HTMLInputElement.prototype, 'files', {...desc, set(value) {
    record('setter'); return Reflect.apply(desc.set, this, [value]);
  }});
  for (const kind of ['input', 'change']) {
    document.addEventListener(kind, e => { if (e.target.matches('input[type=file]')) record(kind); }, true);
  }
  document.addEventListener('submit', e => { e.preventDefault(); record('send'); }, true);
  document.querySelector('button').addEventListener('click', () => record('send'));
  const events = [];
  for (const type of ['blur','focus','pagehide','pageshow']) {
    addEventListener(type, event => {
      if (event.isTrusted) events.push({type, persisted:event.persisted === true});
    });
  }
  document.addEventListener('visibilitychange', event => {
    if (event.isTrusted) events.push({type:'visibilitychange', value:document.visibilityState});
  });
  navigation.addEventListener('currententrychange', event => {
    if (event.isTrusted) events.push({type:'currententrychange'});
  });
  const source = fetch('/' + location.pathname.split('/')[1] + '/program').then(response => response.text());
  const supportedRoute = {get href() { return 'https://chatgpt.com/' + location.search + location.hash; }};
  let program;
  let pendingMenu, panel;
  const menu = {opener:0,choice:0,escape:0,selectionRestoration:0};
  let menuWasOpened = false;
  const commands = {
    setupMenu() {
      document.querySelector('input[type=file]').remove();
      const entry = document.createElement('button');
      entry.type = 'button';
      entry.setAttribute('aria-label', 'Add files and photos');
      entry.setAttribute('aria-controls', 'qa-file-choices');
      entry.setAttribute('aria-expanded','false');
      document.querySelector('form').append(entry);
      const set = Selection.prototype.setBaseAndExtent;
      Selection.prototype.setBaseAndExtent = function(...args) {
        if(menuWasOpened) menu.selectionRestoration++;
        return Reflect.apply(set,this,args);
      };
      entry.addEventListener('click', () => {
        menu.opener++; menuWasOpened=true;
        getSelection().collapse(editor.firstChild,0);
        entry.setAttribute('aria-expanded','true');
        panel = document.createElement('div'); panel.id='qa-file-choices';
        panel.setAttribute('role','menu'); panel.style.minHeight='10px';
        panel.addEventListener('keydown', e => { if (e.key==='Escape') menu.escape++; });
        document.body.append(panel);
      });
    },
    startMenu(operation,native) { pendingMenu = commands.commit(operation,native); return true; },
    menuOpened() { return menuWasOpened; },
    mountChoice() {
      const action=document.createElement('button'); action.type='button';
      action.setAttribute('role','menuitem');action.textContent='Upload file';
      action.addEventListener('click', () => { menu.choice++; });
      panel.append(action);
    },
    finishMenu() { return pendingMenu; },
    menuState() { return {...menu}; },
    async ready() {
      program ||= new Function('location', 'return (' + await source + ')')(supportedRoute);
      return {instance, href:location.href, active:document.hasFocus(), visible:document.visibilityState};
    },
    async stage(native) {
      editor.focus();
      getSelection().setBaseAndExtent(editor.firstChild, 2, editor.firstChild, 7);
      const clickWitnessID = crypto.randomUUID();
      if (program({action:'pinTarget',clickWitnessID,address:'https://chatgpt.com/'}, native) !== 'bound') throw Error('pin failed');
      const target = program({action:'captureTarget',clickWitnessID}, native);
      if (!target?.documentID || !target.clickBindingID) throw Error('missing original click identity');
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 2;
      const base64 = canvas.toDataURL('image/png').split(',')[1];
      const bytes = Uint8Array.from(atob(base64), s => s.charCodeAt(0));
      const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2,'0')).join('');
      const identity = {operationID:crypto.randomUUID(), assetID:crypto.randomUUID(), assetSHA256:digest, target, attempt:1};
      const operation = {target, identity, invocationID:crypto.randomUUID()};
      program({...operation,action:'begin',uploadName:'riftlet-' + identity.operationID + '.png',mediaType:'image/png',byteCount:bytes.length}, native);
      program({...operation,action:'chunk',chunkIndex:0,chunkBase64:base64}, native);
      return operation;
    },
    async commit(operation, native) {
      try {
        const result = await program({...operation,action:'commit',chunkIndex:1}, native);
        return result.observation.preInputRetirement?.reason || result.observation.state;
      } catch (err) { return err.message; }
    },
    read(operation, native) {
      const open = program({action:'validate',target:operation.target,requireLiveOriginal:true},native).valid;
      const write = program({action:'validate',target:operation.target},native).valid;
      const observation = program({...operation,action:'observe',requireLiveOriginal:true},native).observation.state;
      return {open,write,observation};
    },
    state() {
      const selection = getSelection();
      return {instance, href:location.href, visible:document.visibilityState, active:document.hasFocus(),
        textPreserved:editor.textContent === originalText,
        selectionPreserved:selection.anchorNode === editor.firstChild && selection.focusNode === editor.firstChild &&
          selection.anchorOffset === 2 && selection.focusOffset === 7,
        priorPreserved:document.querySelector('[data-file-name]') === prior,
        events:events.slice(), totals:totals()};
    },
    replaceEditor() { editor.replaceWith(editor.cloneNode(true)); },
    movePortalOnInput() {
      const input = document.querySelector('input[type=file]');
      const form = document.querySelector('form');
      form.id = 'qa-draft';
      input.setAttribute('form',form.id);
      const first = document.createElement('section'), second = document.createElement('section');
      const portal = document.createElement('div');
      document.body.append(first,second);
      first.append(portal); portal.append(input);
      input.addEventListener('input', () => second.append(portal), {once:true});
    },
    rebuildOnInput() {
      document.querySelector('input[type=file]').addEventListener('input', () => {
        editor.replaceWith(editor.cloneNode(true));
      }, {once:true});
    },
    returnBack() { history.back(); },
    pushSameDocument() { history.pushState({}, '', '?qa=history'); },
    observeOnPagehide(operation,native) {
      // A real departure dispatches pagehide. The witness was installed first.
      addEventListener('pagehide', event => {
        if (!event.isTrusted) return;
        try {
          const result = program({...operation, action:'commit',chunkIndex:1},native);
          sessionStorage.setItem('pagehide-receipt', result.observation?.preInputRetirement?.reason || result.observation?.state || 'unknown');
        } catch (err) { sessionStorage.setItem('pagehide-receipt', err.message); }
      }, {once:true});
    },
    pagehideReceipt() { return sessionStorage.getItem('pagehide-receipt'); }
  };
  window.qa = commands;
})();
