(() => {
  if (window !== top || location.href !== globalThis.riftletLabURL) return;
  const diagnostic = stage => fetch(globalThis.riftletLabURL+"/report",{method:"POST",
    body:JSON.stringify({action:"diagnostic",stage})}).catch(()=>{});
  diagnostic("isolated_script_entered");
  // Fail closed if an on-demand injection or late restoration missed document_start.
  if (document.readyState !== "loading" || document.querySelector("[data-riftlet-draft]")) {
    diagnostic("late_document_start");return;
  }
  const port = chrome.runtime.connect({name:"riftlet-preclick"});
  const operations = new Set();
  let pin;
  let live = true;
  function original() {
    const forms = document.querySelectorAll("form[data-riftlet-draft]");
    if (forms.length !== 1) return null;
    const form = forms[0];
    const editors = form.querySelectorAll("textarea"), files = form.querySelectorAll('input[type=file]');
    const labels = form.querySelectorAll("label");
    if (editors.length !== 1 || files.length !== 1 || labels.length !== 1 ||
        labels[0].control !== files[0] || files[0].form !== form || files[0].disabled) return null;
    return {form, editor:editors[0], file:files[0], label:labels[0]};
  }
  function revoke() {
    if (!pin) return;
    const ticket = pin.ticket;
    pin = null;
    if (live) port.postMessage({kind:"revoke",ticket});
  }
  function changed(records) {
    if (!pin) return;
    const nodes = [pin.form,pin.editor,pin.file,pin.label];
    for (const r of records) {
      if (r.type === "attributes" && nodes.some(n => r.target === n || r.target.contains(n)) &&
          r.oldValue !== r.target.getAttribute(r.attributeName)) { revoke(); return; }
      if ([...r.removedNodes].some(n => nodes.some(bound => n === bound || n.contains(bound)))) {
        revoke(); return;
      }
    }
  }
  function current() {
    changed(observer.takeRecords());
    const same = original();
    return live && pin && same && location.href === globalThis.riftletLabURL &&
      navigation.currentEntry?.id === pin.entry && document.visibilityState === "visible" &&
      ["form","editor","file","label"].every(k => same[k] === pin[k]);
  }
  function offer() {
    if (pin || !live || location.href !== globalThis.riftletLabURL || document.visibilityState !== "visible") return;
    const now = original(), entry = navigation.currentEntry?.id;
    if (!now || !entry) return;
    pin = {...now,entry,ticket:crypto.randomUUID(),ack:null};
    port.postMessage({kind:"offer",ticket:pin.ticket});
  }
  const observer = new MutationObserver(records => { changed(records); if (pin && !current()) revoke(); offer(); });
  observer.observe(document,{subtree:true,childList:true,attributes:true,attributeOldValue:true,
    attributeFilter:["data-riftlet-draft","id","for","form","type","disabled","hidden","inert"]});
  if (!window.navigation) { port.disconnect();return; }
  navigation.addEventListener("navigate",revoke);
  navigation.addEventListener("currententrychange",() => { revoke(); offer(); });
  document.addEventListener("visibilitychange",() => { revoke(); offer(); });
  window.addEventListener("pagehide",() => { revoke(); live=false; observer.disconnect(); port.disconnect(); });
  port.onDisconnect.addListener(() => { diagnostic("content_port_closed");live=false;pin=null;observer.disconnect(); });
  port.onMessage.addListener(msg => {
    if(msg.kind==="diagnostic") diagnostic(msg.stage);
    if (msg.kind === "ack" && current() && pin.ticket === msg.ticket) {
      pin.ack = msg.ack;
      port.postMessage({kind:"ready",ticket:pin.ticket,ack:msg.ack});
    }
    if (msg.kind === "retire") revoke();
    if (msg.kind === "refresh") offer();
  });
  chrome.runtime.onMessage.addListener((msg,sender,respond) => {
    if (sender.id !== chrome.runtime.id || msg.kind !== "commit") return;
    if (!current() || !pin.ack || msg.ticket !== pin.ticket || msg.ack !== pin.ack ||
        !/^[a-f0-9-]{36}$/i.test(msg.op) || operations.has(msg.op)) {
      respond({state:"REFUSED"}); return;
    }
    // Experiment carries one fixed synthetic PNG. No page-supplied path or data.
    const bytes = Uint8Array.from(atob(msg.png),c=>c.charCodeAt(0));
    const dt = new DataTransfer();
    dt.items.add(new File([bytes], "riftlet-"+msg.op+".png", {type:"image/png"}));
    operations.add(msg.op);
    try {
      const input = pin.file;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,"files").set.call(input,dt.files);
      input.dispatchEvent(new Event("input",{bubbles:true,composed:true}));
      input.dispatchEvent(new Event("change",{bubbles:true}));
      // The fixture verifies the result separately. A setter is never a START receipt.
      respond({state:"INPUT_RETURNED"});
    } catch { respond({state:"UNKNOWN"}); }
  });
})();
