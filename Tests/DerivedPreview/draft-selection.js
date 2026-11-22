'use strict';

// Capture only the known, single-line QA draft in an already bound editor.
function captureDraftSelection(editor, expectedText, expectedSelection) {
  const doc = editor.ownerDocument;
  function read() {
    const selection = doc.getSelection();
    if (!editor.isConnected || !editor.isContentEditable || !expectedSelection ||
        !expectedText || editor.innerText !== expectedText || editor.textContent !== expectedText ||
        !selection || selection.rangeCount !== 1 || selection.isCollapsed ||
        !editor.contains(selection.anchorNode) || !editor.contains(selection.focusNode) ||
        selection.toString() !== expectedSelection) throw Error('original QA text or selection missing');
    function offset(node, localOffset) {
      const prefix = doc.createRange();
      prefix.selectNodeContents(editor);
      prefix.setEnd(node, localOffset);
      return prefix.toString().length;
    }
    const anchor = offset(selection.anchorNode, selection.anchorOffset);
    const focus = offset(selection.focusNode, selection.focusOffset);
    const start = Math.min(anchor, focus), end = Math.max(anchor, focus);
    if (expectedText.slice(start, end) !== expectedSelection) throw Error('selection endpoints disagree');
    return {text: expectedText, selectedText: expectedSelection, start, end, anchor, focus,
      direction: anchor < focus ? 'forward' : 'backward'};
  }
  const before = read(), original = doc.getSelection();
  const nodes = [original.anchorNode, original.focusNode];
  const offsets = [original.anchorOffset, original.focusOffset];
  return {before, after() {
    const current = read(), selected = doc.getSelection();
    if (selected.anchorNode !== nodes[0] || selected.focusNode !== nodes[1] ||
        selected.anchorOffset !== offsets[0] || selected.focusOffset !== offsets[1] ||
        current.anchor !== before.anchor || current.focus !== before.focus) throw Error('selection endpoints changed');
    return current;
  }};
}
