// Bind before the original click, after independently verifying the dedicated QA tab.
function observeNamedUploadError(editor) {
    const doc = editor.ownerDocument;
    const root = doc.documentElement;
    const entry = window.navigation?.currentEntry?.id;
    const qaPage = 'https://chatgpt.com/?temporary-chat=true';
    const ownerSelector = '[data-composer-placement],[data-chatgpt-composer],[data-testid="composer"]';
    const ownerOf = n => n.closest(ownerSelector) || n.closest('form');
    const owner = ownerOf(editor);
    const originalForm = editor.closest('form');
    const layoutOf = n => n.closest('[data-composer-layout]') || ownerOf(n);
    const layout = layoutOf(editor);
    const editors = '#prompt-textarea,[contenteditable],[role="textbox"],textarea';
    const visible = node => node.checkVisibility({opacityProperty: true, visibilityProperty: true}) &&
        node.getClientRects().length > 0;
    const originalDraft = () => {
        if (!layout || !owner || owner === doc.body || owner === doc.documentElement ||
            doc.visibilityState !== 'visible' || !visible(editor) || !editor.isConnected ||
            layoutOf(editor) !== layout || ownerOf(editor) !== owner || editor.closest('form') !== originalForm)
            return false;
        const liveEditors = [...doc.querySelectorAll(editors)].filter(e => visible(e) && ownerOf(e) &&
            (e.isContentEditable || e.tagName === 'TEXTAREA') &&
            !e.closest('article,nav,aside,[role="search"],[data-message-author-role]'));
        const leaves = liveEditors.filter(e => !liveEditors.some(n => n !== e && e.contains(n)));
        return leaves.length === 1 && leaves[0] === editor;
    };
    if (!entry || location.href !== qaPage || !originalDraft()) throw Error('G4_DRAFT_NOT_BOUND');

    // A baseline UUID also excludes a rebuilt predecessor. Node identities catch an
    // existing, previously unnamed card (or alert/control) relabelled for the operation.
    const nodes = () => [...layout.querySelectorAll('*')].filter(n => !editor.contains(n));
    const namedIDs = node => {
        const pattern = /\briftlet-([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\.(?:png|webp)\b/gi;
        const values = ['aria-label','data-file-name','alt','title'].map(attr => node.getAttribute(attr) || '');
        if (node.matches('span.truncate') || (!node.children.length && node.closest(
                '[class~="group/composer-attachment"],[data-file-name],figure[data-composer-image-attachment],[role="progressbar"]')))
            values.push(node.textContent || '');
        return values.flatMap(value => [...value.matchAll(pattern)].map(match => match[1].toLowerCase()));
    };
    const baselineNodes = nodes();
    const baseline = new WeakSet(baselineNodes);
    const baselineIDs = new Set(baselineNodes.flatMap(namedIDs));
    const cardRoots = '[class~="group/composer-attachment"],figure[data-composer-image-attachment],' +
        '[data-file-name],[role="button"][aria-haspopup="dialog"]';
    return operationID => {
        if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(operationID)) throw Error('BAD_OPERATION');
        const id = operationID.toLowerCase();
        const originalDocument = doc === document && root === doc.documentElement &&
            entry === window.navigation?.currentEntry?.id && location.href === qaPage;
        const originalEditor = originalDraft();
        const refused = {operationID, originalDocument, originalEditor, uniqueNamedCard: false};
        if (!originalDocument || !originalEditor || baselineIDs.has(id)) return refused;
        const names = ['riftlet-' + id + '.png', 'riftlet-' + id + '.webp'];
        const alerts = [...layout.querySelectorAll('[role="alert"][aria-label]')].filter(node =>
            names.includes(node.getAttribute('aria-label').toLowerCase()) && visible(node));
        if (alerts.length !== 1) return refused;
        const alert = alerts[0], shell = alert.closest(cardRoots);
        if (!shell || !layout.contains(shell) || !owner.contains(shell) || ownerOf(shell) !== owner || shell.closest('form') !== originalForm ||
            layoutOf(shell) !== layout || shell.contains(editor) || editor.contains(shell) ||
            baseline.has(shell) || baseline.has(alert) || shell.querySelectorAll('[role="alert"]').length !== 1)
            return refused;

        for (const node of nodes()) {
            const ids = namedIDs(node);
            if (shell.contains(node) && ids.some(other => other !== id)) return refused;
            if (ids.includes(id) && (baseline.has(node) || !shell.contains(node) || node.closest(cardRoots) !== shell))
                return refused;
        }
        // Remove may be transparent until hover. It must still belong to this exact tile.
        const removes = [...shell.querySelectorAll('button[aria-label]')].filter(button =>
            names.some(name => ['remove '+name,'移除 '+name,'移除“'+name+'”','remove “'+name+'”',
                                'remove "'+name+'"'].includes(button.getAttribute('aria-label').toLowerCase())));
        if (removes.length !== 1 || baseline.has(removes[0]) || removes[0].disabled) return refused;
        const message = alert.innerText.trim();
        if (!['Upload failed', '上传未成功', '上传失败', 'Failed to upload file.'].includes(message)) return refused;
        if ([...shell.querySelectorAll('[role="progressbar"],progress')].some(visible)) return refused;
        return {...refused, uniqueNamedCard: true, visibleAlertText: message,
            cardAlertFileName: alert.getAttribute('aria-label'), visibleProgressInCard: false};
    };
}
