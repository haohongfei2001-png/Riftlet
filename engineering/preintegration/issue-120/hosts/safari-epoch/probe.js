(async () => {
  const post = (result) => fetch('/receipt' + location.search, {
    method: 'POST', body: JSON.stringify(result), cache: 'no-store',
  });
  const checkpoint = async stage => {
    const result = await fetch('/checkpoint/' + stage + location.search, {method: 'POST', cache: 'no-store'});
    if (!result.ok) throw new Error('native_checkpoint');
  };
  try {
    const witness = 'probe_ran|notReached';
    const storageKey = 'riftlet-local-epoch-' + location.search;
    // Give an ordinarily launched window time to become active. An unavailable
    // focus is a recorded prerequisite failure, never a synthetic focus event.
    for (let n = 0; n < 50 && !document.hasFocus(); n++)
      await new Promise(resolve => setTimeout(resolve, 100));
    const saved = sessionStorage.getItem(storageKey);
    if (saved) {
      const r = JSON.parse(saved);
      sessionStorage.removeItem(storageKey);
      r.oldFenceAfterReload = fence.reload.read();
      r.newGlobalAfterReload = !Object.hasOwn(window, '__riftletEpochFixtureOriginal');
      r.reloadNavigation = performance.getEntriesByType('navigation')[0]?.type === 'reload';
      r.newDocument = [fence.newDocument.bind(), fence.newDocument.read()];
      r.newDocumentPositive = r.newDocument[1] === witness;
      await checkpoint('reload');
      await post(r);
      return;
    }
    const r = {visible: document.visibilityState, focused: document.hasFocus(),
      original: [fence.original.bind(), fence.original.read()]};
    if (r.original[1] !== witness) { await post(r); return; }
    window.__riftletEpochFixtureOriginal = true;
    await checkpoint('original');
    // Mutate and restore the exact same editor before the observer's delivery.
    const editor = document.querySelector('textarea'), tmp = editor.cloneNode();
    r.editorBind = fence.editor.bind();
    editor.replaceWith(tmp);
    tmp.replaceWith(editor);
    r.editorRestored = document.querySelector('textarea') === editor;
    r.oldFenceAfterEditorABA = fence.editor.read();
    r.afterEditor = [fence.afterEditor.bind(), fence.afterEditor.read()];
    await checkpoint('editor');
    // Return to the same entry, URL, editor and document after history traversal.
    const originalEntry = navigation.currentEntry.id, originalURL = location.href;
    const start = performance.now();
    r.historyBind = fence.history.bind();
    history.pushState(null, '', originalURL);
    r.pushedSameURL = location.href === originalURL && navigation.currentEntry.id !== originalEntry;
    const returned = new Promise(resolve => addEventListener('popstate', resolve, {once: true}));
    history.back();
    await Promise.race([returned, new Promise((_, reject) =>
      setTimeout(() => reject(new Error('no_popstate')), 650))]);
    r.originalEntryRestored = navigation.currentEntry.id === originalEntry && location.href === originalURL;
    r.oldFenceAfterHistoryABA = fence.history.read();
    r.historyReadWithinLifetime = performance.now() - start < 1000;
    r.afterHistory = [fence.afterHistory.bind(), fence.afterHistory.read()];
    await checkpoint('history');
    r.reloadBind = fence.reload.bind();
    sessionStorage.setItem(storageKey, JSON.stringify(r));
    location.reload();
  } catch (error) { await post({error: error.name, phase: 'fixture_exception'}); }
})();
