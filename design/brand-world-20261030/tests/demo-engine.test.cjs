'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Model, timing } = require('../site/demo-engine.js');

function clock(options = {}) {
  let now = 0;
  let next = 1;
  const pending = new Map();
  return {
    now: () => now,
    setTimeout(fn, delay) {
      const id = next++;
      pending.set(id, { id, at: now + delay, fn });
      return id;
    },
    clearTimeout(id) {
      if (!options.ignoreCancellation) pending.delete(id);
    },
    tick(ms) {
      const destination = now + ms;
      let guard = 0;
      while (true) {
        const task = [...pending.values()].filter(t => t.at <= destination)
          .sort((a, b) => a.at - b.at || a.id - b.id)[0];
        if (!task) break;
        assert.ok(guard++ < 100, 'unexpected timer loop');
        now = task.at;
        pending.delete(task.id);
        task.fn();
      }
      now = destination;
    }
  };
}

function setup(clockOptions) {
  const scheduler = clock(clockOptions);
  const observations = [];
  const model = new Model({ scheduler, onChange: state => observations.push(state) });
  return { scheduler, model, observations };
}

const complete = timing.check + timing.swallow + timing.completion;

test('initial view contains one available sample, no new attachment and no automatic success', () => {
  const { model, scheduler } = setup();
  const initial = model.snapshot();
  assert.deepEqual(initial.items, [{ id: 'shot-1', status: 'available', visible: true }]);
  assert.deepEqual(initial.attachments, []);
  assert.equal(initial.phase, 'idle');
  assert.equal(initial.busy, false);
  scheduler.tick(20000);
  assert.deepEqual(model.snapshot(), initial);
  assert.equal(model.snapshot().events.some(event => event.type === 'positive_start' || event.type === 'ready'), false);
});

test('positive start permits a 120 ms swallow before final readiness', () => {
  const { scheduler, model, observations } = setup();
  assert.equal(model.attach('shot-1'), true);
  scheduler.tick(timing.check - 1);
  assert.deepEqual(model.snapshot().items[0], { id: 'shot-1', status: 'checking', visible: true });
  assert.equal(model.snapshot().attachments.length, 0);
  scheduler.tick(1);
  assert.equal(model.snapshot().items[0].visible, true);
  assert.equal(model.snapshot().items[0].status, 'swallowing');
  assert.equal(model.snapshot().attachments[0].status, 'uploading');
  assert.equal(observations.some(s => s.phase === 'started'), true);
  scheduler.tick(timing.swallow);
  assert.equal(model.snapshot().items[0].visible, false);
  assert.equal(model.snapshot().attachments[0].status, 'uploading');
  scheduler.tick(timing.completion - 1);
  assert.equal(model.snapshot().phase, 'uploading');
  scheduler.tick(1);
  assert.equal(model.snapshot().attachments[0].status, 'ready');
  const sequence = model.snapshot().events.filter(e => ['positive_start', 'swallowed', 'ready'].includes(e.type));
  assert.deepEqual(sequence.map(e => [e.type, e.at]), [['positive_start', 650], ['swallowed', 770], ['ready', 1770]]);
});

test('duplicate clicks and a second source cannot dispatch during an operation', () => {
  const { model, scheduler } = setup();
  const second = model.capture();
  assert.equal(model.attach('shot-1'), true);
  assert.equal(model.attach('shot-1'), false);
  assert.equal(model.attach(second), false);
  scheduler.tick(complete);
  assert.equal(model.attach('shot-1'), false);
  assert.equal(model.snapshot().events.filter(e => e.type === 'positive_start').length, 1);
  assert.equal(model.attach(second), true);
  scheduler.tick(complete);
  assert.equal(model.snapshot().attachments.length, 2);
});

test('a definitive failure restores the original item and requires another deliberate click', () => {
  const { model, scheduler } = setup();
  model.attach('shot-1', 'failure');
  scheduler.tick(timing.check + timing.swallow);
  assert.equal(model.snapshot().items[0].visible, false);
  scheduler.tick(timing.completion);
  assert.deepEqual(model.snapshot().items[0], { id: 'shot-1', status: 'available', visible: true });
  assert.equal(model.snapshot().attachments.length, 0);
  scheduler.tick(100000);
  assert.equal(model.snapshot().events.filter(e => e.type === 'positive_start').length, 1);
  assert.equal(model.attach('shot-1', 'success'), true);
  scheduler.tick(complete);
  assert.equal(model.snapshot().attachments[0].status, 'ready');
});

test('unknown after start remains hidden, is not success, and blocks redispatch', () => {
  const { model, scheduler } = setup();
  model.attach('shot-1', 'unknown');
  scheduler.tick(complete);
  assert.deepEqual(model.snapshot().items[0], { id: 'shot-1', status: 'unknown', visible: false });
  assert.equal(model.snapshot().attachments[0].status, 'unknown');
  assert.equal(model.snapshot().phase, 'unknown');
  assert.equal(model.attach('shot-1'), false);
  scheduler.tick(100000);
  assert.equal(model.snapshot().events.some(e => e.type === 'ready'), false);
  assert.equal(model.snapshot().events.filter(e => e.type === 'positive_start').length, 1);
  assert.equal(model.resolveUnknown('shot-1', 'ready'), true);
  assert.equal(model.snapshot().attachments[0].status, 'ready');
  assert.equal(model.snapshot().events.filter(e => e.type === 'positive_start').length, 1);
});

test('unknown before start remains visible but does not permit blind retry', () => {
  const { model, scheduler } = setup();
  model.attach('shot-1', 'unknown-before-start');
  scheduler.tick(complete);
  assert.deepEqual(model.snapshot().items[0], { id: 'shot-1', status: 'unknown', visible: true });
  assert.equal(model.snapshot().attachments.length, 0);
  assert.equal(model.attach('shot-1'), false);
  assert.equal(model.resolveUnknown('shot-1', 'failed'), true);
  assert.equal(model.snapshot().items[0].status, 'available');
  assert.equal(model.snapshot().events.some(e => e.type === 'positive_start'), false);
});

test('lack of a positive start never hides the source or fabricates an attachment', () => {
  const { model, scheduler } = setup();
  model.attach('shot-1', 'no-start');
  scheduler.tick(complete);
  assert.deepEqual(model.snapshot().items[0], { id: 'shot-1', status: 'available', visible: true });
  assert.equal(model.snapshot().attachments.length, 0);
  assert.equal(model.snapshot().phase, 'no-start');
  assert.equal(model.snapshot().events.some(e => e.type === 'swallow_start'), false);
});

test('reset invalidates already queued completion even when timer cancellation is ineffective', () => {
  const { model, scheduler } = setup({ ignoreCancellation: true });
  model.attach('shot-1');
  scheduler.tick(timing.check + timing.swallow);
  model.reset();
  const afterReset = model.snapshot();
  scheduler.tick(complete);
  assert.deepEqual(model.snapshot(), afterReset);
  model.attach('shot-1', 'success');
  scheduler.tick(complete);
  assert.equal(model.snapshot().attachments.length, 1);
  assert.equal(model.snapshot().attachments[0].status, 'ready');
});

test('capture keeps three stable unique source identities and cannot alter draft text', () => {
  const { model } = setup();
  assert.equal(model.capture(), 'shot-2');
  assert.equal(model.capture(), 'shot-3');
  assert.equal(model.capture(), null);
  assert.deepEqual(model.snapshot().items.map(item => item.id), ['shot-1', 'shot-2', 'shot-3']);
  assert.equal('draft' in model.snapshot(), false);
});

test('public snapshots are isolated and disposal prevents late changes', () => {
  const { model, scheduler, observations } = setup({ ignoreCancellation: true });
  const state = model.snapshot();
  state.items[0].status = 'ready';
  state.events[0].type = 'ready';
  assert.equal(model.snapshot().items[0].status, 'available');
  assert.equal(model.snapshot().events[0].type, 'initial');
  model.attach('shot-1');
  const count = observations.length;
  model.dispose();
  scheduler.tick(complete);
  assert.equal(observations.length, count);
  assert.equal(model.attach('shot-1'), false);
  assert.equal(model.capture(), null);
});
