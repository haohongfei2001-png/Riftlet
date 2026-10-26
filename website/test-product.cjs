/* Unit tests against a minimal DOM double, NOT browser or real ChatGPT tests. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const code = fs.readFileSync(path.join(root, 'website-product.js'), 'utf8');
const decode = s => s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&amp;', '&');
class Element {
  constructor(tag = 'div') {
    this.tagName = tag.toLowerCase(); this.attrs = {}; this.dataset = {}; this.children = [];
    this.parentNode = null; this.listeners = {}; this.value = ''; this._text = ''; this._html = '';
    this.style = {setProperty: (k, v) => { this.style[k] = v; }};
    const owner = this;
    this.classList = {
      contains: c => owner.className.split(/\s+/).includes(c),
      add: c => { if (!owner.classList.contains(c)) owner.className = (owner.className + ' ' + c).trim(); },
      remove: c => { owner.className = owner.className.split(/\s+/).filter(x => x !== c).join(' '); },
      toggle: c => { owner.classList.contains(c) ? owner.classList.remove(c) : owner.classList.add(c); }
    };
  }
  get className() { return this.attrs.class || ''; }
  set className(v) { this.attrs.class = v; }
  setAttribute(k, v) { this.attrs[k] = String(v); if (k.startsWith('data-')) this.dataset[k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = String(v); if (k === 'value') this.value = String(v); }
  getAttribute(k) { return this.attrs[k] ?? null; }
  removeAttribute(k) { delete this.attrs[k]; }
  appendChild(n) { n.parentNode = this; this.children.push(n); return n; }
  replaceChildren() { for (const c of this.children) c.parentNode = null; this.children = []; this._text = ''; }
  remove() { if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(x => x !== this); this.parentNode = null; }
  contains(n) { return n === this || this.children.some(c => c.contains(n)); }
  get innerHTML() { return this._html || this._text || this.children.map(c => c.tagName === '#text' ? c._text : '<' + c.tagName + '>' + c.innerHTML + '</' + c.tagName + '>').join(''); }
  set innerHTML(v) { this.replaceChildren(); this._html = v; parse(v, this); }
  get textContent() { return this._text + this.children.map(c => c.textContent).join(''); }
  set textContent(v) { this.replaceChildren(); this._text = String(v); this._html = String(v); }
  addEventListener(k, fn) { (this.listeners[k] ||= []).push(fn); }
  dispatch(k, values = {}) { for (const fn of this.listeners[k] || []) fn({type:k, target:this, ...values}); }
  matches(selector) {
    if (selector[0] === '.') return this.classList.contains(selector.slice(1));
    if (selector[0] === '#') return this.attrs.id === selector.slice(1);
    const m = selector.match(/^([\w-]+)?\[([\w-]+)(?:="([^"]*)")?\]$/);
    if (m) return (!m[1] || this.tagName === m[1]) && this.attrs[m[2]] !== undefined && (m[3] === undefined || this.attrs[m[2]] === m[3]);
    return this.tagName === selector;
  }
  querySelectorAll(s) { const out = []; for (const c of this.children) { if (c.matches(s)) out.push(c); out.push(...c.querySelectorAll(s)); } return out; }
  querySelector(s) { return this.querySelectorAll(s)[0] || null; }
}
function parse(markup, parent) {
  const stack = [parent], voids = new Set(['meta', 'link', 'img', 'input', 'br', 'hr']);
  for (const token of markup.match(/<!--[\s\S]*?-->|<[^>]*>|[^<]+/g) || []) {
    if (token.startsWith('<!--') || /^<!/.test(token)) continue;
    if (token.startsWith('</')) {
      const name = token.slice(2).split(/[\s>]/)[0].toLowerCase();
      while (stack.length > 1) { if (stack.pop().tagName === name) break; }
    } else if (token.startsWith('<')) {
      const name = token.slice(1).split(/[\s/>]/)[0].toLowerCase(), el = new Element(name);
      const attrs = token.slice(name.length + 1).matchAll(/([\w:-]+)(?:="([^"]*)"|='([^']*)')/g);
      for (const a of attrs) el.setAttribute(a[1], decode(a[2] ?? a[3]));
      stack.at(-1).appendChild(el);
      if (!token.endsWith('/>') && !voids.has(name)) stack.push(el);
    } else {
      const n = new Element('#text'); n._text = decode(token); stack.at(-1).appendChild(n);
    }
  }
}
function fixture(lang = '') {
  const document = new Element('document'); parse(html, document);
  document.getElementById = id => document.querySelector('#' + id);
  document.documentElement = document.querySelector('html');
  document.createElement = tag => new Element(tag); document.activeElement = null;
  const $ = id => document.getElementById(id);
  $('outcome').value = 'success';
  let now = 0, serial = 0; const timers = [];
  const timeout = (fn, ms) => { timers.push({fn, at: now + ms, id: ++serial}); return serial; };
  const context = {document, URL, Promise, setTimeout:timeout, requestAnimationFrame:fn=>timeout(fn, 0),
    window:{location:{href:'https://riftlet.com/' + lang}, history:{replaceState(){}}}};
  vm.runInNewContext(code, context);
  const advance = async ms => {
    const end = now + ms;
    for (;;) {
      await new Promise(resolve => setImmediate(resolve));
      timers.sort((a,b)=>a.at-b.at || a.id-b.id);
      if (!timers.length || timers[0].at > end) break;
      const t = timers.shift(); now = t.at; t.fn();
    }
    now = end; await new Promise(resolve => setImmediate(resolve));
  };
  const item = id => $('edge-items').children.find(x => x.dataset.id === String(id));
  return {$, item, document, advance, click:id=>item(id).dispatch('click')};
}
const results = [];
async function test(name, fn) { await fn(); results.push(name); }
(async () => {
  await test('initial three items and screenshot-only demo', async()=>{const f=fixture();assert.equal(f.$('edge-items').children.length,3);assert.equal(f.item(1).dataset.state,'idle');assert.equal(f.$('attachments').children.length,0);});
  await test('ready only after pending placeholder; existing text untouched',async()=>{const f=fixture();f.$('draft').value='合成测试 / preserved';f.$('draft').dispatch('input');f.click(1);assert.equal(f.item(1).dataset.state,'pending');await f.advance(450);assert.equal(f.$('attachments').children[0].dataset.ready,'false');assert.equal(f.item(1).classList.contains('done'),false);await f.advance(550);assert.equal(f.item(1).dataset.state,'done');assert.equal(f.$('draft').value,'合成测试 / preserved');});
  await test('duplicate click does not duplicate attachment',async()=>{const f=fixture();f.click(1);f.click(1);await f.advance(1400);assert.equal(f.$('attachments').children.length,1);});
  await test('three clicks run in order',async()=>{const f=fixture();f.click(2);f.click(1);f.click(3);await f.advance(4000);assert.deepEqual(f.$('attachments').children.map(c=>c.dataset.id),['2','1','3']);});
  await test('failure returns to same slot and permits explicit retry',async()=>{const f=fixture();f.$('outcome').value='failure';const y=f.item(2).style['--y'];f.click(2);await f.advance(1100);assert.equal(f.item(2).dataset.state,'failed');assert.equal(f.item(2).style['--y'],y);f.$('outcome').value='success';f.click(2);await f.advance(1300);assert.equal(f.item(2).dataset.state,'done');});
  await test('unknown preserves item and blocks re-dispatch',async()=>{const f=fixture();f.$('outcome').value='unknown';f.click(1);await f.advance(1100);f.$('outcome').value='success';f.click(1);await f.advance(1400);assert.equal(f.item(1).dataset.state,'unknown');assert.equal(f.$('attachments').children.length,0);});
  await test('reset invalidates an in-flight operation',async()=>{const f=fixture();f.click(1);await f.advance(450);f.$('reset').dispatch('click');await f.advance(1000);assert.equal(f.$('attachments').children.length,0);assert.equal(f.item(1).dataset.state,'idle');f.click(2);await f.advance(1300);assert.equal(f.item(2).dataset.state,'done');});
  await test('position stays fixed under pointer, compacts on leave',async()=>{const f=fixture();f.$('edge').dispatch('pointerenter');f.click(1);await f.advance(1300);assert.equal(f.item(2).style['--y'],'55px');f.$('edge').dispatch('pointerleave');assert.equal(f.item(2).style['--y'],'0px');});
  await test('locale change during upload preserves draft and operation',async()=>{const f=fixture();f.$('draft').value='Keep exactly\n这些文字';f.$('draft').dispatch('input');f.click(1);await f.advance(450);f.$('language-toggle').dispatch('click');await f.advance(800);assert.equal(f.$('draft').value,'Keep exactly\n这些文字');assert.equal(f.$('attachments').children.length,1);assert.equal(f.$('attachments').querySelector('small').textContent,'Ready');f.$('reset').dispatch('click');assert.equal(f.$('draft').value,'Keep exactly\n这些文字');});
  await test('English entry point and theme toggle',async()=>{const f=fixture('?lang=en');assert.equal(f.document.documentElement.lang,'en');f.$('theme').dispatch('click');assert.equal(f.$('theme').getAttribute('aria-pressed'),'true');assert.equal(f.$('theme').textContent,'Light desktop');});
  await test('remove demo attachment never requeues',async()=>{const f=fixture();f.click(1);await f.advance(1300);f.$('attachments').querySelector('button').dispatch('click');assert.equal(f.$('attachments').children.length,0);assert.equal(f.item(1).dataset.state,'done');});
  console.log(JSON.stringify({suite:'DOM-double unit tests; not browser visual tests',passed:results.length,tests:results},null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
