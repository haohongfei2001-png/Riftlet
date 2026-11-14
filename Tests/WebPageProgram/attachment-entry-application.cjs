'use strict';

// Executed in the application's own realm by both fixtures. The application owns
// the input, menu handlers, and receipt of the File. Only the product may supply it.
function mountAttachmentEntryCase(name, form, input) {
  const counts = {entry: 0, menus: 0, submenus: 0, pickerCalls: 0, pickerClicks: 0,
    chooserDefaultAllowed: 0, linkDefaultAllowed: 0, cloudClicks: 0, closeClicks: 0, entryEvents: []};
  const element = (tag, attrs = {}, label = '') => {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
    node.textContent = label;
    return node;
  };
  const append = (parent, child) => { parent.appendChild(child); return child; };
  const invoke = () => { counts.pickerCalls++; input.click(); };
  input.addEventListener('click', event => {
    counts.pickerClicks++;
    if (!event.defaultPrevented) counts.chooserDefaultAllowed++;
  });
  const app = {input, counts};
  if (name === 'direct') return app;

  const entryAttrs = {'aria-label': 'Add files and photos', 'data-testid': 'composer-plus-button'};
  if (name !== 'implicit-submit') entryAttrs.type = 'button';
  if (name === 'localized-opener') {
    delete entryAttrs['data-testid'];
    entryAttrs['aria-label'] = 'Adjuntar archivos';
    entryAttrs['aria-haspopup'] = 'menu';
    entryAttrs['aria-controls'] = 'files-panel';
  }
  const entry = append(form, element('button', entryAttrs, name === 'localized-opener' ? 'Opciones' : '+'));
  if (name === 'ready-direct') {
    // Its ordinary composer input is ready. This inert sibling must never
    // disqualify the input or consume a discovery timeout.
    entry.addEventListener('click', () => { counts.entry++; });
    return app;
  }
  if (name === 'inert-entry') {
    entry.addEventListener('click', () => { counts.entry++; });
    append(append(document.body, element('section')), input);
    return app;
  }
  if (name.startsWith('detached') || name === 'await-detached-with-rival') input.remove();
  if (name === 'await-detached-with-rival') {
    // The independent connected picker only exists; the application never
    // invokes it. Its presence cannot disqualify the actual detached object.
    app.rival = append(document.body, element('input', {type: 'file'}));
  }
  if (name === 'detached-stop') {
    // Capture-phase listener installed by the application BEFORE the bridge.
    // Even this listener must observe chooser cancellation with Chrome's real
    // default semantics; it is entitled to stop later listeners on the object.
    input.addEventListener('click', event => {
      counts.pickerClicks++;
      if (!event.defaultPrevented) counts.chooserDefaultAllowed++;
      event.stopImmediatePropagation();
    }, true);
  }
  // This picker existed before entry activation. There is no static link
  // between the trigger and this object, even for the native await scenario.
  if (['await-existing', 'implicit-submit', 'forced-noun', 'forced-no-role', 'reused-open', 'reused-content', 'nested',
       'short-label', 'plain-action', 'pointer-open', 'renamed-action', 'label-default',
       'focusable-menu', 'anchor-action', 'localized-opener'].includes(name)) {
    append(document.body, input);
    input.hidden = true;
  }
  if (['connected', 'detached', 'detached-showPicker', 'detached-stop', 'implicit-submit', 'await-existing', 'await-detached-with-rival'].includes(name)) {
    entry.addEventListener('click', async () => {
      counts.entry++;
      if (name === 'await-existing' || name === 'await-detached-with-rival') {
        await Promise.resolve();
        await new Promise(resolve => setTimeout(resolve, 5));
      }
      if (name === 'detached-showPicker') { counts.pickerCalls++; input.showPicker(); }
      else invoke();
    });
    return app;
  }
  if (name === 'owned-async-mount' || name === 'visible-empty-panel') {
    input.remove();
    const initiallyEmpty = name === 'visible-empty-panel';
    const panel = append(document.body, element(initiallyEmpty ? 'form' : 'section', {id: 'attachment-portal'}));
    if (!initiallyEmpty) append(panel, element('span', {}, 'Files'));
    entry.setAttribute('aria-controls', panel.id);
    panel.hidden = !initiallyEmpty;
    entry.addEventListener('click', () => {
      counts.entry++; panel.hidden = false;
      // The application owns this specific panel. Only mounting is required.
      setTimeout(() => append(panel, input), 25);
    });
    input.addEventListener('change', () => { input.remove(); panel.hidden = !initiallyEmpty; });
    return app;
  }
  if (name === 'reused-content') {
    // Existing visible portal and existing DOM action. The application only
    // changes its text and callback state when this particular trigger runs.
    const popup = append(document.body, element('div'));
    const action = append(popup, element('button', {type: 'button'}, 'Filter'));
    let active = false;
    entry.addEventListener('click', () => {
      counts.entry++; active = true; action.textContent = '照片和文件';
    });
    action.addEventListener('click', () => {
      if (!active) { counts.closeClicks++; return; }
      counts.menus++; invoke(); active = false; action.textContent = 'Filter';
    });
    return app;
  }
  let menu = null;
  const close = () => {
    if (menu) menu.remove();
    menu = null;
    entry.setAttribute('aria-expanded', 'false');
  };
  const appendChoice = (parent, action, label) => {
    const node = append(parent, name === 'short-label'
      ? element('div', {tabindex: '0'}, label)
      : element('button', {type: 'button', role: 'menuitem'}, label));
    node.addEventListener('click', action);
    return node;
  };
  const open = () => {
    const role = ['verb-menu', 'noun-menu', 'forced-noun', 'pointer-open', 'focusable-menu',
      'anchor-action', 'localized-opener'].includes(name) ? {role: 'menu'} : {};
    if (name === 'focusable-menu') role.tabindex = '-1';
    const id = name === 'localized-opener' ? 'files-panel' : 'current-attachment-popover';
    menu = append(document.body, element('div', {...role, id}));
    entry.setAttribute('aria-expanded', 'true');
    menu.addEventListener('keydown', event => { if (event.key === 'Escape') close(); });
    if (name === 'anchor-action') {
      const action = append(menu, element('a', {href: '#', role: 'menuitem'}, '照片和文件'));
      action.addEventListener('click', event => {
        if (!event.defaultPrevented) counts.linkDefaultAllowed++;
        counts.menus++; invoke();
      });
      return;
    }
    if (name === 'nested') {
      let nested;
      const opener = appendChoice(menu, () => {
        counts.submenus++;
        nested = append(document.body, element('div', {id: 'device-files-submenu'}));
        opener.setAttribute('aria-expanded', 'true');
        appendChoice(nested, () => { counts.menus++; invoke(); nested.remove(); }, '文件');
      }, 'Files');
      opener.setAttribute('aria-haspopup', 'menu');
      opener.setAttribute('aria-controls', 'device-files-submenu');
      opener.setAttribute('aria-expanded', 'false');
      appendChoice(menu, () => counts.cloudClicks++, 'Google Drive');
      return;
    }
    if (name === 'renamed-action' || name === 'label-default') {
      // The real DOM relation of this label identifies local upload even if
      // the accessible text is outside the product's dictionaries.
      input.setAttribute('id', 'local-draft-upload');
      const label = append(menu, element('label', {for: input.id},
        name === 'renamed-action' ? 'Datei auswählen' : 'Upload from computer'));
      label.addEventListener('click', () => counts.menus++);
      return;
    }
    if (name === 'plain-action') {
      const closeButton = append(menu, element('button', {type: 'button'}, 'Close'));
      closeButton.addEventListener('click', () => { counts.closeClicks++; close(); });
      const wrapper = append(menu, element('div'));
      const action = append(wrapper, element('div'));
      append(action, element('span', {}, '照片和文件'));
      action.addEventListener('click', () => { counts.menus++; invoke(); });
      appendChoice(menu, () => counts.cloudClicks++, 'Google Drive');
      return;
    }
    const labels = {'noun-menu': '照片和文件', 'forced-noun': '照片和文件',
      'reused-open': '照片和文件', 'short-label': '文件'};
    appendChoice(menu, () => { counts.menus++; invoke(); }, labels[name] || 'Upload from computer');
    appendChoice(menu, () => counts.cloudClicks++, 'Google Drive');
  };
  if (name === 'reused-open') {
    entry.setAttribute('aria-controls', 'current-attachment-popover');
    open();
  }
  if (name === 'pointer-open') {
    entry.addEventListener('pointerdown', event => {
      counts.entryEvents.push(event.type);
      if (event.button !== 0 || menu) return;
      counts.entry++;
      open();
    });
    entry.addEventListener('click', event => {
      counts.entryEvents.push(event.type);
      if (menu) close(); else { counts.entry++; open(); }
    });
  } else {
    entry.addEventListener('click', () => {
      counts.entry++;
      if (menu) close(); else open();
    });
  }
  return app;
}

// Run the exact historical product bytes retained in this PR. Formal and CI
// checkouts have full history; no user installation or network is consulted.
function readResidentV15Source() {
  const {execFileSync} = require('node:child_process');
  const {createHash} = require('node:crypto');
  const {strictEqual} = require('node:assert');
  const path = require('node:path');
  const source = execFileSync('git', ['show',
    '79994009d3c00f9286a43a8891ac59fe55c5d84e:Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'],
    {cwd: path.resolve(__dirname, '../..'), encoding: 'utf8'});
  strictEqual(createHash('sha256').update(source).digest('hex'),
    'c3780ef2de327f3c98068c5d46b4eef818462822cd1d42257c41a72d16269dca');
  return source;
}

module.exports = {mountAttachmentEntryCase, readResidentV15Source};
