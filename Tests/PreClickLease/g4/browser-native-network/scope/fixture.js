(() => {
  'use strict';
  const role = location.pathname === '/scope/target' ? 'target' : 'peer';
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1' ||
      location.pathname !== '/scope/' + role || location.search || location.hash || top !== self) return;
  const phases = ['baseline', 'in-flight', 'offline-new', 'restored', 'blocked-new', 'unblocked'];
  const issued = new Set();
  const documentID = crypto.randomUUID();
  const original = document;
  window.qa = Object.freeze({
    identity() { return {documentID, timeOrigin: performance.timeOrigin, original: original === document, role}; },
    async request(phase) {
      if (!phases.includes(phase) || issued.has(phase) || original !== document) throw Error('fixed case refused');
      issued.add(phase);
      const value = 1 + phases.indexOf(phase) + (role === 'peer' ? phases.length : 0);
      const size = phase === 'in-flight' ? 6 * 1024 * 1024 : 64;
      const body = new Uint8Array(size).fill(value);
      try {
        const reply = await fetch(phases.indexOf(phase) >= 4 ? '/fixed/exact-resource' : '/fixed/' + role + '/' + phase, {
          method: 'POST', body, headers: {'X-Owned-Case':role + '/' + phase}, credentials: 'omit', redirect: 'error', cache: 'no-store'
        });
        return {kind: 'response', status: reply.status, responseBytes: (await reply.arrayBuffer()).byteLength};
      } catch (error) {
        return {kind: 'rejected', errorName: error.name === 'TypeError' ? 'TypeError' : 'other'};
      }
    }
  });
})();
