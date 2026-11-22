'use strict';
const input = document.querySelector('input');
const form = document.querySelector('form');
const card = document.querySelector('output');
const counts = {input: 0, change: 0, sendButton: 0, submit: 0};
const events = [];
const before = document.querySelector('textarea').value;

form.addEventListener('submit', event => { counts.submit++; event.preventDefault(); });
form.querySelector('button').addEventListener('click', () => counts.sendButton++);
input.addEventListener('input', event => {
  counts.input++;
  events.push({event: 'input', trusted: event.isTrusted});
});
input.addEventListener('change', async event => {
  counts.change++;
  events.push({event: 'change', trusted: event.isTrusted});
  const [file] = input.files;
  if (counts.change !== 1 || input.files.length !== 1 || file.type !== 'image/png') {
    throw Error('Expected one selected PNG');
  }

  card.value = 'pending';
  let target = location.pathname + '/png';
  let grant;
  if (form.dataset.grant) {
    const response = await fetch(location.pathname + '/grant', {method: 'POST'});
    if (response.status !== 201) throw Error('Expected one original grant');
    const issued = await response.json();
    if (issued.route !== target) throw Error('Unexpected loopback route');
    grant = {issuedAt: issued.issuedAt, expiresAt: issued.expiresAt, receivedAt: Date.now()};
    target = issued.route;
    if (form.dataset.grant === 'wait') {
      await new Promise(resolve => setTimeout(resolve, Math.max(0, issued.expiresAt - Date.now()) + 30));
    }
  }
  const request = new XMLHttpRequest();
  for (const type of ['readystatechange', 'loadstart', 'load', 'error', 'abort', 'timeout', 'loadend']) {
    request.addEventListener(type, e => {
      events.push({event: type, trusted: e.isTrusted, readyState: request.readyState, status: request.status});
      if (type === 'load') card.value = request.status >= 400 ? 'refused' : 'accepted';
      if (type === 'loadend') {
        window.control = {counts, events, grant, card: card.value, response: request.responseText,
          fileCount: input.files.length, textUnchanged: before === form.querySelector('textarea').value};
      }
    });
  }
  request.open('PUT', target);
  if (grant) grant.sentAt = Date.now();
  request.send(file);
});
window.ready = true;
