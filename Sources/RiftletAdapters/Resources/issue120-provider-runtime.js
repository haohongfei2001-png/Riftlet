function createProvider(profile) {
  "use strict";
  // A backend nominates a route at the native click boundary. This resource
  // verifies the document and DOM members within that already addressed tab.
  const doc = document, win = doc.defaultView;
  const one = items => items.length === 1 ? items[0] : null;
  const allowedRoute = () => location.origin === profile.origin &&
    !location.username && !location.password && !location.search && !location.hash &&
    profile.paths.includes(location.pathname);
  const visible = n => n.isConnected && n.getClientRects().length > 0 &&
    !n.closest('[hidden],[inert],[aria-hidden="true"],dialog,[role="dialog"]') &&
    n.checkVisibility({opacityProperty: true, visibilityProperty: true});
  const active = n => visible(n) && !n.matches(':disabled,[aria-disabled="true"]');
  const upload = n => /upload|attach|上传|附件/i.test(n.getAttribute("aria-label") || n.title || n.textContent);
  const semanticOwner = n => n.closest("fieldset,form");
  const recipe = profile.recipe;
  function resolve() {
    if (!allowedRoute()) return {state: "other_route"};
    const editor = one([...doc.querySelectorAll(profile.editor)].filter(active));
    if (!editor) return {state: "editor_unavailable"};
    const owner = semanticOwner(editor);
    if (!owner) return {state: "owner_unavailable"};
    const actions = [...owner.querySelectorAll(profile.action || 'label,button,[role="button"]')].filter(n =>
      semanticOwner(n) === owner && (!("form" in n) || n.form === editor.closest("form")) && active(n) && upload(n));
    const action = one(actions);
    if (!action) return {state: "upload_control_unavailable"};
    let picker = null;
    if (action instanceof HTMLLabelElement) {
      picker = action.control;
    } else {
      const id = action.getAttribute("aria-controls");
      if (id && !/\s/.test(id)) picker = one([...doc.querySelectorAll("#" + CSS.escape(id))]);
    }
    // An existing hidden file input is usable only by an explicit control
    // relationship. An input elsewhere in the same form never wins a search.
    if (!(picker instanceof HTMLInputElement) || picker.type !== "file" ||
        picker.matches(":disabled") || picker.form !== editor.closest("form") ||
        (semanticOwner(picker) && semanticOwner(picker) !== owner)) picker = null;
    return {state: picker ? "owned_input" : "editor_and_upload_action", editor, owner, action, picker};
  }

  const hashPattern = /^[a-f0-9]{64}$/;
  const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
  function visibleOriginalImage(card, name, oldImages) {
    if (!visible(card) || card.getAttribute("aria-label") !== name) return null;
    const image = one([...card.querySelectorAll("img")]);
    if (!image || oldImages.has(image) || image.closest(recipe.card) !== card ||
        !visible(image) || image.alt !== name || !image.complete || image.naturalWidth < 1) return null;
    const src = image.getAttribute("src");
    return src && src.startsWith("data:image/png;base64,") && src === image.currentSrc &&
      src.length <= recipe.maxBytes * 2 + 32 ? {image,src} : null;
  }

  async function sha256(data) {
    return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",data)),
      n => n.toString(16).padStart(2,"0")).join("");
  }

  function pin(click) {
    if (!uuid.test(click)) throw Error("invalid_click");
    const url = location.href, entry = win.navigation?.currentEntry?.id;
    const {editor,owner,action,picker:capturedInput} = resolve();
    let picker = capturedInput;
    if (!entry || !editor || !owner || !action) throw Error("target_unavailable");
    const findLane = () => recipe ? one([...owner.querySelectorAll(recipe.lane)].filter(n =>
      semanticOwner(n) === owner && !n.closest('dialog,[role="dialog"]'))) : null;
    const lane = findLane();
    const watched = [editor,owner,action,picker,lane].filter(Boolean);
    let retired = false, spent = false, original = null, accepted = null, acceptedRetired = false, changed = false;
    const old = new WeakSet(), oldImages = new WeakSet(), removedCards = new WeakSet();
    function process(records) {
      for (const r of records) {
        if (r.type === "attributes") {
          if (watched.some(n => r.target === n || r.target.contains(n))) retired = true;
          if (lane && r.target.parentNode === lane) removedCards.add(r.target);
        }
        for (const n of r.removedNodes) {
          if (watched.some(v => n === v || n.contains(v))) retired = true;
          if (r.target === lane) removedCards.add(n);
          if (accepted && (n === accepted || n.contains(accepted))) acceptedRetired = true;
        }
      }
    }
    const watcher = new MutationObserver(process);
    watcher.observe(doc.documentElement,{childList:true,subtree:true,attributes:true,
      attributeFilter:["aria-label","aria-controls","for","id","form","type","disabled","contenteditable","role","inert","hidden"]});
    const originalTarget = () => {
      process(watcher.takeRecords());
      const current = resolve();
      return !retired && url === location.href && entry === win.navigation?.currentEntry?.id &&
        current.editor === editor && current.owner === owner && current.action === action && (!picker || current.picker === picker) && (!lane || findLane() === lane);
    };
    function matches(ticket) {
      return original && ticket && Object.keys(original).every(key => original[key] === ticket[key]);
    }
    const commit = async (ticket, file) => {
      if (!recipe || recipe.events !== "input-change" || !lane) throw Error("unverified_event_recipe");
      if (!originalTarget()) throw Error("target_or_payload_changed");
      if (!picker) {
        // The original action may acquire its declared control asynchronously.
        // Never open a chooser or switch away from a previously captured input.
        picker = resolve().picker;
        if (!picker) throw Error("owned_input_unavailable");
        watched.push(picker);
      }
      if (!ticket || ticket.click !== click || !uuid.test(ticket.operation) || !uuid.test(ticket.invocation) ||
          !(file instanceof File) || file.type !== "image/png" || file.name !== "riftlet-"+ticket.operation+".png" ||
          file.size === 0 || file.size > recipe.maxBytes || !hashPattern.test(ticket.payloadSHA256) ||
          !hashPattern.test(ticket.originalSHA256) || !originalTarget()) throw Error("target_or_payload_changed");
      // Re-evaluating this resource in the same document must not mint another attempt.
      const slot = Symbol.for("com.riftlet.issue120.spent.v1");
      if (!Object.hasOwn(doc,slot)) Object.defineProperty(doc,slot,{value:new Set()});
      const ledger = doc[slot], ids = ["c:"+click,"o:"+ticket.operation,"i:"+ticket.invocation];
      if (spent || ledger.size >= 3072 || ids.some(id => ledger.has(id))) throw Error("input_fenced");
      spent = true;
      for (const id of ids) ledger.add(id);
      original = Object.freeze({click,operation:ticket.operation,invocation:ticket.invocation,
        originalSHA256:ticket.originalSHA256,payloadSHA256:ticket.payloadSHA256});
      if (await sha256(await file.arrayBuffer()) !== original.payloadSHA256 || !originalTarget()) throw Error("target_or_payload_changed");
      for (const child of lane.children) old.add(child);
      for (const img of lane.querySelectorAll("img")) oldImages.add(img);
      const data = new DataTransfer();
      data.items.add(file);
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,"files").set.call(picker,data.files);
      picker.dispatchEvent(new Event("input",{bubbles:true,composed:true}));
      picker.dispatchEvent(new Event("change",{bubbles:true}));
      changed = true;
      return "input_returned";
    };
    const observe = async ticket => {
      if (!matches(ticket) || !originalTarget() || acceptedRetired) return "unavailable";
      if (!changed) return "unknown";
      const name = "riftlet-"+original.operation+".png";
      const candidates = () => [...lane.children].filter(n =>
        !old.has(n) && !removedCards.has(n) && n.matches(recipe.card) && n.getAttribute("aria-label") === name);
      const card = one(candidates());
      if (!card || (accepted && card !== accepted)) return "unknown";
      const errors = () => [...card.querySelectorAll('[role="alert"]')].filter(n => visible(n));
      if (accepted && errors().length === 1 && recipe.explicitFailure &&
          errors()[0].matches(recipe.explicitFailure) && errors()[0].closest(recipe.card) === card && !card.querySelector("img")) return "original_card_failed";
      const before = visibleOriginalImage(card,name,oldImages);
      if (!before || errors().length) return "unknown";
      let unstable = false;
      const check = new MutationObserver(() => { unstable=true; });
      check.observe(card,{subtree:true,childList:true,attributes:true,characterData:true});
      try {
        const bytes = Uint8Array.from(atob(before.src.split(",")[1]),c => c.charCodeAt(0));
        const digest = await sha256(bytes);
        const after = visibleOriginalImage(card,name,oldImages);
        if (!originalTarget() || acceptedRetired || unstable || check.takeRecords().length ||
            digest !== original.payloadSHA256 || before.image !== after?.image || before.src !== after?.src ||
            card !== one(candidates()) || errors().length) return "unknown";
        accepted = card;
        return "accepted_into_draft";
      } catch { return "unknown"; }
      finally { check.disconnect(); }
    };
    return Object.freeze({current:originalTarget,commit,observe,close(){ retired=true; watcher.disconnect(); }});
  }
  return Object.freeze({inspect(){ return resolve().state; },pin});
}
