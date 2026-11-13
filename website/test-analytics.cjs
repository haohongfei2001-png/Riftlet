'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const boot = fs.readFileSync(path.join(root, 'website-analytics.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const validId = '12345678-abcd-4cde-8123-123456789abc';

function run({ id = '', host = 'riftlet.com', protocol = 'https:', dnt = '0', gpc = false, optedOut = false, storageBlocked = false, preloaded = false } = {}) {
  const scripts = [];
  const document = {
    querySelector: name => name === 'meta[name="riftlet-umami-website-id"]'
      ? { getAttribute: key => key === 'content' ? id : null } : null,
    getElementById: name => preloaded && name === 'riftlet-umami-tracker' ? {} : null,
    createElement: name => {
      assert.equal(name, 'script');
      return { attributes: {}, setAttribute(key, value) { this.attributes[key] = value; } };
    },
    head: { appendChild(script) { scripts.push(script); } }
  };
  const window = {
    location: { hostname: host, protocol },
    doNotTrack: dnt,
    localStorage: { getItem() {
      if (storageBlocked) throw new Error('storage blocked');
      return optedOut ? '1' : null;
    }}
  };
  const navigator = { doNotTrack: dnt, globalPrivacyControl: gpc };
  vm.runInNewContext(boot, { document, window, navigator }, { timeout: 1000 });
  return scripts;
}

test('inactive without a real site ID: no tracker or network bootstrap', () => {
  assert.equal(run().length, 0);
  assert.equal(run({ id: 'YOUR_WEBSITE_ID' }).length, 0);
  assert.equal(run({ id: '<placeholder>' }).length, 0);
});
test('only configured production https host loads Umami', () => {
  assert.equal(run({ id: validId }).length, 1);
  assert.equal(run({ id: validId, host: 'www.riftlet.com' }).length, 1);
  for (const host of ['localhost', 'example.com', 'riftlet.com.evil.example', 'github.io']) {
    assert.equal(run({ id: validId, host }).length, 0, host);
  }
  assert.equal(run({ id: validId, protocol: 'http:' }).length, 0);
});
test('Do Not Track, GPC, explicit opt-out and duplicate bootstrap block tracking', () => {
  for (const options of [{ dnt: '1' }, { gpc: true }, { optedOut: true }, { preloaded: true }]) {
    assert.equal(run({ id: validId, ...options }).length, 0, JSON.stringify(options));
  }
  assert.equal(run({ id: validId, storageBlocked: true }).length, 1);
});
test('real ID loads only official Umami cloud script, confined to Riftlet domain', () => {
  const [script] = run({ id: validId });
  assert.equal(script.id, 'riftlet-umami-tracker');
  assert.equal(script.src, 'https://cloud.umami.is/script.js');
  assert.equal(script.async, true);
  assert.equal(script.attributes['data-website-id'], validId);
  assert.equal(script.attributes['data-domains'], 'riftlet.com,www.riftlet.com');
  assert.equal(script.attributes['data-do-not-track'], 'true');
  assert.equal(script.attributes['data-exclude-hash'], 'true');
});
test('exactly two official DMG links record distinct placements without URL changes', () => {
  const anchors = Array.from(html.matchAll(/<a\b[^>]*>/g), m => m[0]);
  const downloads = anchors.filter(s => s.includes('data-umami-event="download_dmg"'));
  assert.equal(downloads.length, 2);
  assert.deepEqual(downloads.map(a => /data-umami-event-placement="([^"]+)"/.exec(a)?.[1]).sort(), ['header', 'primary']);
  for (const a of downloads) {
    assert.match(a, /data-umami-event-version="1\.0\.0"/);
    assert.match(a, /href="https:\/\/github\.com\/haohongfei2001-png\/Riftlet\/releases\/download\/v1\.0\.0\/Riftlet-1\.0\.0\.dmg"/);
  }
  assert.equal(anchors.filter(s => s.includes('Riftlet-1.0.0.dmg')).length, 2);
});
test('website includes a single optional analytics loader and initially empty website ID', () => {
  assert.equal((html.match(/src="website-analytics\.js"/g) || []).length, 1);
  assert.equal((html.match(/name="riftlet-umami-website-id" content=""/g) || []).length, 1);
  assert.equal((html.match(/src="website-v2\.js"/g) || []).length, 1);
  assert.doesNotMatch(boot, /\.track\(|\/api\/send|fetch\(|XMLHttpRequest|document\.cookie/);
});
