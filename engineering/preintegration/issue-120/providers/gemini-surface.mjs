// Observed on the anonymous /app landing page. No input, menu activation,
// history mutation, message-text read, or upload registry belongs here.
export function inspectGeminiSurface(doc) {
  const win=doc.defaultView;
  if (!win || win.location.href!=='https://gemini.google.com/app') return {state:'other_route'};
  return inspectLandingControls(doc);
}

export function inspectLandingControls(doc) {
  const visible=node=>node.checkVisibility({opacityProperty:true,visibilityProperty:true}) &&
    node.getClientRects().length>0 && !node.closest('[inert],[hidden],[aria-hidden="true"]');
  const editors=[...doc.querySelectorAll('rich-textarea > .ql-editor[role="textbox"][contenteditable="true"]')].filter(visible);
  if (editors.length!==1) return {state:'editor_unavailable'};
  const editor=editors[0], owner=editor.closest('fieldset');
  if (!owner || editor.closest('[role="dialog"],dialog')) return {state:'surface_unavailable'};
  const action=[...owner.querySelectorAll('simplified-input-menu gem-icon-button button')].filter(node=>
    node.closest('fieldset')===owner && node.form===editor.closest('form') &&
    !node.closest('[role="dialog"],dialog') && visible(node) && !node.matches(':disabled,[aria-disabled="true"]') &&
    /upload|上传/i.test(node.getAttribute('aria-label')||node.title||node.innerText));
  if (action.length!==1) return {state:'action_unavailable'};
  return {state:'editor_and_upload_action',editor,owner,action:action[0]};
}
