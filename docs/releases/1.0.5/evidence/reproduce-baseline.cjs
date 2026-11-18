'use strict';
// Read-only probes of the exact production page program through its existing controlled DOM fixture.
// This does not run real Chrome, macOS, Apple Events or ChatGPT.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {createHash} = require('node:crypto');
const {execFileSync} = require('node:child_process');
const baseline = 'f3153b10dac4445720f1c20c8836ddbbea625c49';
const root = process.argv[2];
if (!root) throw Error('Usage: node attachment-controlled-probes.cjs /absolute/path/to/Riftlet-1.0.4');
assert.equal(execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), baseline, 'Use the frozen audited checkout, not the implementation candidate');
const relativeSource = 'Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js';
const sourcePath = path.resolve(root, relativeSource);
// Explicitly bind the existing fixture to this source, regardless of caller environment.
process.env.RIFTLET_PAGE_PROGRAM_SOURCE = sourcePath;
const {fixture} = require(path.resolve(root, 'Tests/WebPageProgram/independent-input-fixture.cjs'));
(async () => {
  console.log(JSON.stringify({kind: 'scope', scope: 'controlled DOM; not real Chrome/macOS/ChatGPT',
    node: process.version, baseline, sourcePath: relativeSource,
    sourceSHA256: createHash('sha256').update(fs.readFileSync(sourcePath)).digest('hex')}));
  const f = fixture(), op = f.bind();
  f.stage(op);
  const before = (await f.commit(op)).observation;
  const card = f.document.querySelectorAll('[data-file-name]')
    .find(n => n.getAttribute('data-file-name') === op.name);
  assert.ok(card, 'the exact operation attachment card exists');
  card.setAttribute('data-state', 'failed');
  card.append(new f.Node('div', {role: 'alert'}));
  const after = f.observe(op);
  assert.equal(before.state, 'uploadStarted');
  assert.equal(after.state, 'uploadStarted');
  assert.equal(after.hasError, false);
  assert.equal(after.exactImageIdentity, true);
  assert.equal(f.setters, 1);
  assert.equal(f.sends, 0);
  console.log(JSON.stringify({case: 'same-attachment-error-after-START', before: before.state,
    after: after.state, hasError: after.hasError, exactImageIdentity: after.exactImageIdentity,
    setters: f.setters, sends: f.sends}));
  for (let i = 0; i < 100; i++) {
    const next = f.bind(); f.stage(next); await f.commit(next);
  }
  const registry = vm.runInContext('globalThis.__riftletIndependentFileInput20261104', f.context);
  const operations = [...registry.operations.values()];
  const bindings = operations.filter(x => x.binding && x.binding.editor && x.binding.form).length;
  const chunks = operations.reduce((n, x) => n + x.chunks.length, 0);
  assert.equal(operations.length, 101);
  assert.equal(operations.filter(x => x.start).length, 101);
  assert.equal(bindings, 101);
  assert.equal(chunks, 0);
  assert.equal(f.setters, 101);
  assert.equal(f.sends, 0);
  console.log(JSON.stringify({case: 'lifetime-retention-after-101-successful-STARTs',
    operations: operations.length, started: operations.filter(x => x.start).length,
    bindings, retainedChunks: chunks, setters: f.setters, sends: f.sends}));
})().catch(error => { console.error(error); process.exitCode = 1; });
