/*
 * Riftlet — browser-local, synthetic product demonstration.
 * This state machine does not access a screen, clipboard, files, ChatGPT,
 * storage or a network. It demonstrates a contract, not native acceptance.
 * The UI owns its draft text; this model cannot replace or send that text.
 */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.RiftletDemo = factory();
})(typeof window !== 'undefined' ? window : this, function () {
  'use strict';

  var OUTCOMES = ['success', 'failure', 'unknown', 'no-start', 'unknown-before-start'];
  var TIMING = Object.freeze({ check: 650, swallow: 120, completion: 1000 });

  function Model(options) {
    options = options || {};
    var custom = options.scheduler;
    this._scheduler = custom || {
      setTimeout: function (fn, ms) { return setTimeout(fn, ms); },
      clearTimeout: function (id) { clearTimeout(id); },
      now: function () { return Date.now(); }
    };
    if (typeof this._scheduler.setTimeout !== 'function' ||
        typeof this._scheduler.clearTimeout !== 'function' ||
        typeof this._scheduler.now !== 'function') {
      throw new TypeError('scheduler requires setTimeout, clearTimeout and now functions');
    }
    this._onChange = typeof options.onChange === 'function' ? options.onChange : function () {};
    this._timers = new Set();
    this._generation = 0;
    this._disposed = false;
    this._init('initial');
  }

  Model.prototype._init = function (event) {
    this._nextId = 2;
    this._items = [{ id: 'shot-1', status: 'available', visible: true }];
    this._attachments = [];
    this._phase = 'idle';
    this._messageKey = 'idle';
    this._busy = false;
    this._events = [];
    this._record(event, null);
  };

  Model.prototype._record = function (type, id) {
    this._events.push({ type: type, id: id, at: this._scheduler.now() });
    if (this._events.length > 100) this._events.shift();
  };

  Model.prototype.snapshot = function () {
    return {
      items: this._items.map(function (item) { return Object.assign({}, item); }),
      attachments: this._attachments.map(function (item) { return Object.assign({}, item); }),
      phase: this._phase,
      messageKey: this._messageKey,
      events: this._events.map(function (event) { return Object.assign({}, event); }),
      busy: this._busy
    };
  };

  Model.prototype._notify = function () {
    if (!this._disposed) this._onChange(this.snapshot());
  };

  Model.prototype._later = function (delay, callback) {
    var self = this;
    var generation = this._generation;
    var handle = this._scheduler.setTimeout(function () {
      self._timers.delete(handle);
      if (self._disposed || generation !== self._generation) return;
      callback();
    }, delay);
    this._timers.add(handle);
  };

  Model.prototype._cancelTimers = function () {
    var self = this;
    this._generation += 1;
    this._timers.forEach(function (handle) { self._scheduler.clearTimeout(handle); });
    this._timers.clear();
  };

  Model.prototype.capture = function () {
    if (this._disposed || this._busy || this._items.length >= 3) return null;
    var id = 'shot-' + this._nextId++;
    this._items.push({ id: id, status: 'available', visible: true });
    this._phase = 'captured';
    this._messageKey = 'captured';
    this._record('captured', id);
    this._notify();
    return id;
  };

  Model.prototype.attach = function (id, outcome) {
    outcome = outcome || 'success';
    var item = this._items.find(function (candidate) { return candidate.id === id; });
    if (this._disposed || this._busy || !item || item.status !== 'available' ||
        !item.visible || OUTCOMES.indexOf(outcome) === -1) return false;

    var self = this;
    this._busy = true;
    item.status = 'checking';
    this._phase = 'checking';
    this._messageKey = 'checking';
    this._record('click', id);
    this._notify();

    this._later(TIMING.check, function () {
      if (outcome === 'no-start' || outcome === 'unknown-before-start') {
        item.status = outcome === 'no-start' ? 'available' : 'unknown';
        item.visible = true;
        self._phase = outcome === 'no-start' ? 'no-start' : 'unknown';
        self._messageKey = outcome;
        self._busy = false;
        self._record(outcome === 'no-start' ? 'no_start' : 'unknown_before_start', id);
        self._notify();
        return;
      }

      // A simulated positive start, not a click and not final readiness,
      // permits the source thumbnail to disappear into the edge.
      item.status = 'started';
      self._attachments.push({ id: id, status: 'uploading' });
      self._phase = 'started';
      self._messageKey = 'started';
      self._record('positive_start', id);
      self._notify();

      self._later(0, function () {
        item.status = 'swallowing';
        self._phase = 'swallowing';
        self._messageKey = 'started';
        self._record('swallow_start', id);
        self._notify();

        self._later(TIMING.swallow, function () {
          item.visible = false;
          item.status = 'uploading';
          self._phase = 'uploading';
          self._messageKey = 'uploading';
          self._record('swallowed', id);
          self._notify();

          self._later(TIMING.completion, function () {
            var attachment = self._attachments.find(function (candidate) { return candidate.id === id; });
            self._busy = false;
            if (outcome === 'success') {
              item.status = 'ready';
              attachment.status = 'ready';
              self._phase = 'ready';
              self._messageKey = 'ready';
              self._record('ready', id);
            } else if (outcome === 'failure') {
              // A deliberately simulated definitive failure restores access.
              // It is not a claim that native safe-retry admission is open.
              item.status = 'available';
              item.visible = true;
              self._attachments = self._attachments.filter(function (candidate) { return candidate.id !== id; });
              self._phase = 'failed';
              self._messageKey = 'failed';
              self._record('definitive_failure', id);
              self._record('restored', id);
            } else {
              // After a positive start, uncertainty does not resurrect the
              // edge thumbnail. History can expose its unresolved status.
              // Keep the uncertain attachment; do not assume it is absent.
              item.status = 'unknown';
              item.visible = false;
              attachment.status = 'unknown';
              self._phase = 'unknown';
              self._messageKey = 'unknown';
              self._record('unknown_after_start', id);
            }
            self._notify();
          });
        });
      });
    });
    return true;
  };

  Model.prototype.resolveUnknown = function (id, result) {
    if (this._disposed || this._busy || (result !== 'ready' && result !== 'failed')) return false;
    var item = this._items.find(function (candidate) { return candidate.id === id; });
    if (!item || item.status !== 'unknown') return false;
    var attachment = this._attachments.find(function (candidate) { return candidate.id === id; });
    if (result === 'ready') {
      item.status = 'ready';
      item.visible = false;
      if (attachment) attachment.status = 'ready';
      else this._attachments.push({ id: id, status: 'ready' });
      this._phase = 'ready';
      this._messageKey = 'resolved-ready';
      this._record('resolved_ready', id);
    } else {
      item.status = 'available';
      item.visible = true;
      this._attachments = this._attachments.filter(function (candidate) { return candidate.id !== id; });
      this._phase = 'failed';
      this._messageKey = 'resolved-failed';
      this._record('resolved_failed', id);
    }
    // This models a separate, conclusive check. It never dispatches an upload.
    this._notify();
    return true;
  };

  Model.prototype.reset = function () {
    if (this._disposed) return;
    this._cancelTimers();
    this._init('reset');
    this._notify();
  };

  Model.prototype.dispose = function () {
    this._cancelTimers();
    this._disposed = true;
    this._onChange = function () {};
  };

  return { Model: Model, timing: TIMING };
});
