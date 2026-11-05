/* Directly inherited from design/final-system-20261028/prototype/windows.js at main b61fc46.
   Only product windows are supplemented below; original file is unchanged. */
  const escape = value => String(value == null ? '' : value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const attr = escape;
  const checked = value => value ? ' checked' : '';
  const selected = (a, b) => a === b ? ' selected' : '';
  const disabled = value => value ? ' disabled' : '';
  const icons = {
    general: '<path d="M3 6h14M3 14h14M7 3v6M13 11v6"/>',
    capture: '<path d="M3 6h4l2-2h4l2 2h2v11H3z"/><circle cx="10" cy="11" r="3"/>',
    display: '<path d="M4 2v16M7 4h10v11H7z"/>',
    privacy: '<path d="M10 2 3 5v5c0 4 7 8 7 8s7-4 7-8V5z"/><path d="m7 10 2 2 4-5"/>',
    about: '<circle cx="10" cy="10" r="8"/><path d="M10 9v6M10 5v1"/>',
    folder: '<path d="M2 5h6l2 2h8v10H2z"/>',
    chrome: '<circle cx="10" cy="10" r="8"/><circle cx="10" cy="10" r="3"/><path d="m10 7 7 0M7 10 4 4M12 13 8 18"/>',
    check: '<path d="m4 10 4 4 8-9"/>',
    history: '<path d="M3 6a8 8 0 1 1-1 7M2 2v5h5M10 6v5l3 2"/>',
    image: '<rect x="2" y="3" width="16" height="14" rx="2"/><circle cx="7" cy="8" r="1"/><path d="m3 15 5-4 3 2 3-5 3 7"/>',
    clock: '<circle cx="10" cy="10" r="8"/><path d="M10 5v6l4 2"/>',
    archive: '<path d="M3 6h14v12H3zM2 2h16v4H2zM8 10h4"/>',
    removed: '<path d="M3 5h14M8 2h4M5 5l1 13h8l1-13M8 8v7M12 8v7"/>',
    message: '<path d="M3 3h14v11H8l-5 4z"/>',
    arrow: '<path d="M4 10h12m-5-5 5 5-5 5"/>',
    chevron: '<path d="m8 5 5 5-5 5"/>',
    dot: '<circle cx="10" cy="10" r="3"/>'
  };
  function glyph(name) {
    return '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (icons[name] || icons.dot) + '</svg>';
  }
  function button(label, action, opts = {}) {
    return `<button class="button${opts.primary ? ' primary' : ''}${opts.quiet ? ' quiet' : ''}${opts.danger ? ' destructive' : ''}" data-action="${attr(action)}"${opts.id ? ` data-id="${attr(opts.id)}"` : ''}${disabled(opts.disabled)}>${escape(label)}</button>`;
  }
  function toggle(key, value, label) {
    return `<label class="native-switch"><input type="checkbox" data-setting="${attr(key)}" aria-label="${attr(label)}"${checked(value)}><span aria-hidden="true"></span></label>`;
  }
  function settingRow(title, description, control) {
    return `<div class="setting-row"><div class="setting-description"><div class="setting-name">${escape(title)}</div>${description ? `<p>${escape(description)}</p>` : ''}</div><div class="setting-control">${control}</div></div>`;
  }
  function titlebar(title, label) {
    return `<header class="native-titlebar"><div class="traffic"><button data-action="close-window" aria-label="关闭${attr(title)}" title="关闭"></button><i aria-hidden="true"></i><i aria-hidden="true"></i></div><span id="native-window-title">${escape(title)}</span><span class="native-build-label">${escape(label || 'Riftlet')}</span></header>`;
  }
  function frame(kind, title, body, label) {
    return `<section class="native-window ${attr(kind)}" role="dialog" aria-modal="false" aria-labelledby="native-window-title">${titlebar(title, label)}${body}</section>`;
  }
