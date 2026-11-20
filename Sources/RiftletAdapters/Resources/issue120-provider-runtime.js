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
  // The host supplies an encoded definition. A site-wide prototype extension
  // must never add input capabilities to a read-only bundled profile.
  const recipe = Object.hasOwn(profile, "recipe") ? profile.recipe : null;
  function resolveDraft() {
    if (!allowedRoute()) return {state: "other_route"};
    const editor = one([...doc.querySelectorAll(profile.editor)].filter(active));
    if (!editor) return {state: "editor_unavailable"};
    const owner = semanticOwner(editor);
    if (!owner) return {state: "owner_unavailable"};
    return {editor,owner};
  }
  function resolve() {
    const draft = resolveDraft();
    const {editor,owner} = draft;
    if (!owner) return draft;
    const actions = [...owner.querySelectorAll(profile.action || 'label,button,[role="button"]')].filter(n =>
      semanticOwner(n) === owner && (!("form" in n) || n.form === editor.closest("form")) && active(n) && upload(n));
    const action = one(actions);
    if (!action) return {state: "upload_control_unavailable"};
    let picker = null;
    if (action instanceof HTMLLabelElement) {
      const id = action.htmlFor;
      if (id && !/\s/.test(id) && one([...doc.querySelectorAll("#"+CSS.escape(id))]) === action.control)
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

  // Inspect a menu already mounted by the website. These observations do
  // not feed the write resolver. Portals need an explicit, unique relationship
  // in both directions; proximity and matching labels cannot identify a menu.
  function inspectAttachmentEntry(surface) {
    const {state, owner, editor, action, picker} = surface;
    if (!action) return state;
    if (picker) return "direct_owned_input";
    const menuID = action.getAttribute("aria-controls");
    if (!menuID) return "menu_relation_unavailable";
    const nodesFor = id => id && !/\s/.test(id) ? [...doc.querySelectorAll("#"+CSS.escape(id))] : [];
    const menu = one(nodesFor(menuID));
    if (!menu || menu.role !== "menu" ||
        one([...doc.querySelectorAll('[aria-controls~="'+CSS.escape(menuID)+'"]')]) !== action)
      return "menu_relation_ambiguous";
    if (action.getAttribute("aria-expanded") !== "true" || !visible(menu)) return "menu_not_open";
    const localOwner = semanticOwner(menu);
    if (localOwner !== owner) {
      if (localOwner || !action.id || one(nodesFor(action.id)) !== action ||
          menu.getAttribute("aria-labelledby") !== action.id) return "menu_owner_unproven";
    }
    const items = [...menu.querySelectorAll('[role="menuitem"]')].filter(n =>
      n.closest('[role="menu"]') === menu && active(n) && upload(n));
    const item = one(items);
    if (!item) return items.length ? "menu_items_ambiguous" : "menu_upload_item_unavailable";
    if ((semanticOwner(item) && semanticOwner(item) !== owner) ||
        ("form" in item && item.form !== null && item.form !== editor.closest("form")))
      return "menu_item_owner_unproven";
    const inputID = item instanceof HTMLLabelElement ? item.htmlFor : item.getAttribute("aria-controls");
    const input = one(nodesFor(inputID));
    if (!(input instanceof HTMLInputElement) || input.type !== "file" || input.matches(":disabled") ||
        (item instanceof HTMLLabelElement && item.control !== input)) return "menu_input_unproven";
    const references = [...doc.querySelectorAll('[aria-controls~="'+CSS.escape(inputID)+'"],label[for="'+CSS.escape(inputID)+'"]')];
    if (one(references) !== item) return "menu_input_ambiguous";
    const form = editor.closest("form"), inputOwner = semanticOwner(input);
    if ((input.form && input.form !== form) || (inputOwner && inputOwner !== owner)) return "menu_input_owner_unproven";
    if (input.closest('[role="menu"]') !== menu &&
        !(inputOwner === owner && input.form === form)) return "menu_input_owner_unproven";
    return "menu_owned_input_observed";
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
    let ledger;
    if (recipe) {
      // Reserve the write-capable click before resolving or waiting. A stale
      // handle cannot reacquire the document after a focus or navigation ABA.
      const slot = Symbol.for("com.riftlet.issue120.spent.v1");
      if (!Object.hasOwn(doc,slot)) Object.defineProperty(doc,slot,{value:new Set()});
      ledger = doc[slot];
      if (ledger.size >= 3072 || ledger.has("c:"+click)) throw Error("input_fenced");
      ledger.add("c:"+click);
    }
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
    const foreground = () => doc.visibilityState === "visible" && doc.hasFocus();
    let mayWrite = foreground();
    const draftMembers = [editor,owner,lane].filter(Boolean);
    let surfaceRetired = false, draftRetired = false;
    const retire = () => { retired = true; surfaceRetired = true; draftRetired = true; };
    // Traversing back can restore the same entry ID and DOM object references.
    // Retirement records the transition itself, including same-URL replacements.
    const lifecycle = new AbortController();
    for (const name of ["navigate","currententrychange"]) {
      win.navigation.addEventListener(name,retire,{capture:true,signal:lifecycle.signal});
    }
    win.addEventListener("pagehide",retire,{capture:true,signal:lifecycle.signal});
    win.addEventListener("blur",event => {
      if (event.target === win && event.isTrusted) mayWrite = false;
    },{signal:lifecycle.signal});
    doc.addEventListener("visibilitychange",() => {
      if (!foreground()) mayWrite = false;
    },{signal:lifecycle.signal});
    function process(records) {
      for (const r of records) {
        if (r.type === "attributes") {
          if (draftMembers.some(n => r.target === n || r.target.contains(n))) draftRetired = true;
          if (watched.some(n => r.target === n || r.target.contains(n))) retired = true;
          if ([owner,editor,action].some(n => r.target === n || r.target.contains(n)) &&
              !(r.target === action && r.attributeName === "aria-controls")) surfaceRetired = true;
          if (lane && r.target.parentNode === lane) removedCards.add(r.target);
        }
        for (const n of r.removedNodes) {
          if (draftMembers.some(v => n === v || n.contains(v))) draftRetired = true;
          if (watched.some(v => n === v || n.contains(v))) retired = true;
          if ([owner,editor,action].some(v => n === v || n.contains(v))) surfaceRetired = true;
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
    // A site can rebuild its upload controls after input. Subsequent reads use
    // the pinned draft and lane and never obtain another input or open a picker.
    function originalDraftLane() {
      process(watcher.takeRecords());
      if (draftRetired || url !== location.href || entry !== win.navigation?.currentEntry?.id) return false;
      const draft = resolveDraft();
      return draft.editor === editor && draft.owner === owner && !!lane && findLane() === lane;
    }
    function inspectOriginalEntry() {
      process(watcher.takeRecords());
      if (surfaceRetired || url !== location.href || entry !== win.navigation?.currentEntry?.id)
        return "original_surface_changed";
      const surface = resolve();
      if (surface.owner !== owner || surface.editor !== editor || surface.action !== action)
        return "original_surface_changed";
      return inspectAttachmentEntry(surface);
    }
    function matches(ticket) {
      return original && ticket && Object.keys(original).every(key => original[key] === ticket[key]);
    }
    const commit = async (ticket, file) => {
      if (!recipe || recipe.events !== "input-change" || !lane) throw Error("unverified_event_recipe");
      if (!mayWrite || !foreground() || !originalTarget()) throw Error("target_or_payload_changed");
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
      const ids = ["o:"+ticket.operation,"i:"+ticket.invocation];
      if (spent || ledger.size >= 3072 || ids.some(id => ledger.has(id))) throw Error("input_fenced");
      spent = true;
      for (const id of ids) ledger.add(id);
      original = Object.freeze({click,operation:ticket.operation,invocation:ticket.invocation,
        originalSHA256:ticket.originalSHA256,payloadSHA256:ticket.payloadSHA256});
      if (await sha256(await file.arrayBuffer()) !== original.payloadSHA256 || !mayWrite || !foreground() || !originalTarget()) throw Error("target_or_payload_changed");
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
      if (!matches(ticket) || !originalDraftLane() || acceptedRetired) return "unavailable";
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
        if (!originalDraftLane() || acceptedRetired || unstable || check.takeRecords().length ||
            digest !== original.payloadSHA256 || before.image !== after?.image || before.src !== after?.src ||
            card !== one(candidates()) || errors().length) return "unknown";
        accepted = card;
        return "accepted_into_draft";
      } catch { return "unknown"; }
      finally { check.disconnect(); }
    };
    return Object.freeze({current:originalTarget,inspectAttachmentEntry:inspectOriginalEntry,commit,observe,close(){ retire(); watcher.disconnect(); lifecycle.abort(); }});
  }
  return Object.freeze({inspect(){ return resolve().state; },pin});
}
