'use strict';

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const stamp = seconds => new Date(Date.UTC(2026, 0, 1) + seconds * 1000).toISOString();

function fixture() {
  const native = {
    bundle: 'com.microsoft.edgemac', sessionID: 'edge-kernel-v1:10:20:30',
    windowID: '44', tabID: '55', exactLocalMarker: true, systemForeground: true
  };
  return {
    A: { ...native, doc: 'A', observedUTC: stamp(1) },
    B: { ...native, doc: 'B', observedUTC: stamp(4) },
    page: {
      family: 'edge', phase: 'done', status: 'PASS', routeChecks: [{}, {}],
      createdUTC: stamp(0),
      firstWitnessBoundary: { originalDocument: 'A', replacementDocument: 'B' },
      events: [
        { kind: 'original', utc: stamp(2) },
        { kind: 'barrier', utc: stamp(3) },
        { kind: 'complete', utc: stamp(5) }
      ]
    }
  };
}

function correlate(t, { A, B, page }) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'riftlet-native-receipt-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const [name, receipt] of Object.entries({ A, B, edge: page })) {
    fs.writeFileSync(path.join(dir, name + '.json'), JSON.stringify(receipt));
  }
  const command = spawnSync(process.execPath, [
    path.join(__dirname, 'correlate-native.cjs'), dir, 'edge',
    path.join(dir, 'A.json'), path.join(dir, 'B.json')
  ], { encoding: 'utf8' });
  if (command.error) throw command.error;
  const output = path.join(dir, 'edge-native.json');
  return { status: command.status, error: command.stderr,
    receipt: fs.existsSync(output) ? JSON.parse(fs.readFileSync(output, 'utf8')) : null };
}

test('joins only foreground QA samples obtained before their corresponding page receipts', t => {
  const result = correlate(t, fixture());
  assert.equal(result.status, 0, result.error);
  assert.equal(result.receipt.status, 'MATCH');

  const invalid = [
    [run => { delete run.A.exactLocalMarker; }, /private QA page/],
    [run => { run.B.systemForeground = false; }, /foreground browser/],
    [run => { run.A.observedUTC = stamp(2); }, /precede the original/],
    [run => { run.A.observedUTC = stamp(2.5); }, /precede the original/],
    [run => { run.B.observedUTC = stamp(3); }, /between the barrier/],
    [run => { run.B.observedUTC = stamp(6); }, /between the barrier/]
  ];
  for (const [change, message] of invalid) {
    const run = fixture();
    change(run);
    const rejected = correlate(t, run);
    assert.equal(rejected.status, 1, rejected.error);
    assert.match(rejected.error, message);
    assert.equal(rejected.receipt, null);
  }
});
