'use strict';
// Synthetic controlled DOM only. No browser, account, network, or private image.
// Usage: node attachment-foreign-picker-repro.cjs /absolute/path/to/Riftlet
const assert = require('node:assert/strict');
const path = require('node:path');
const repo = path.resolve(process.argv[2] || process.cwd());
const {fixture} = require(path.join(repo, 'Tests/WebPageProgram/independent-input-fixture.cjs'));
(async () => {
  const f = fixture({accept: false});
  f.input.remove();
  const entry = f.form.append(new f.Node('button', {type: 'button', 'aria-label': 'Add files'}));
  let entryClicks = 0;
  entry.addEventListener('click', () => { entryClicks++; });
  const external = f.body.append(new f.Node('section'));
  const foreign = external.append(new f.context.HTMLInputElement());
  foreign.applicationAccept = false;
  // Independent asynchronous page work starts before Riftlet commit. The real
  // composer entry is inert and never calls, creates or references this picker.
  const pending = new Promise(resolve => setTimeout(() => { foreign.click(); resolve(); }, 10));
  const op = f.bind();
  f.stage(op);
  const started = performance.now();
  const result = await f.commit(op);
  await pending;
  const evidence = {
    scope: 'synthetic DOM fixture, current production JS; not live ChatGPT',
    scenario: 'inert composer entry plus sole unrelated asynchronous picker invocation',
    elapsedMS: Math.round(performance.now() - started),
    entryClicks,
    foreignSetters: foreign.setterCount,
    foreignChanges: foreign.changeCount,
    foreignReceivedCurrentFile: foreign.files[0]?.name === op.name,
    state: result.observation.state,
    diagnostics: result.entryDiagnostics
  };
  console.log(JSON.stringify(evidence, null, 2));
  // This script succeeds only while the audited defect exists. A regression
  // test for the fix must invert these assertions and require zero writes.
  assert.equal(entryClicks, 1);
  assert.equal(foreign.setterCount, 1);
  assert.equal(foreign.changeCount, 1);
  assert.equal(foreign.files[0]?.name, op.name);
  assert.equal(result.observation.state, 'inputTriggered');
})().catch(error => { console.error(error); process.exitCode = 1; });
