'use strict';
(() => {
  const id = crypto.randomUUID();
  const field = document.querySelector('#owned');
  const journal = [];
  const current = () => document.querySelector('#owned');
  const calls = [];
  const origin = location.origin;
  const key = 'owned-write-counts';
  const counts = () => JSON.parse(localStorage.getItem(key) || '{"writes":0,"input":0,"change":0,"send":0}');
  function mark(k) { const c=counts(); c[k]++; localStorage.setItem(key,JSON.stringify(c)); }
  for (const kind of ['input','change','submit']) {
    document.addEventListener(kind, () => mark(kind==='submit'?'send':kind), true);
  }
  const qa = {
    inspect() {return {id,origin,phase:'loaded',value:current().value,active:document.hasFocus(),child:location.search==='?child',opener:!!window.opener,counts:counts()};},
    focus() { current().focus(); current().setSelectionRange(3,5); return this.inspect(); },
    open() { document.querySelector('#open').click();return 'clicked'; },
    bind(key) {
      const receiver = bindOriginalReceiver(current(),()=>true,true);
      const write = receiver.once(HTMLTextAreaElement.prototype.setRangeText);
      calls[key] = {receiver, write};
      return {id, eligible:receiver.current()};
    },
    deliver(key) { const f=calls[key]; const yes=f.write('q'); if(yes)mark('writes'); return {accepted:yes, counts:counts(), value:current().value}; },
    replaceEditor() { const next=current().cloneNode(true);next.value='QA-replaced';current().replaceWith(next);next.focus();return this.inspect(); },
    publish(key) {
      if (!opener || opener.location.origin!==origin) throw Error('dedicated same-origin fixture opener missing');
      const f=calls[key];
      // Keep the captured method and its original realm alive over a real top-level navigation.
      // Later calls cannot resolve a locator in the new document.
      opener.guestQA.receive(key, f.write, id);
      return id;
    },
    receive(key,write,documentID) { journal[key]={write,documentID}; },
    deliverHeld(key) {const f=journal[key];const yes=f.write('q');if(yes)mark('writes');return {accepted:yes, original:f.documentID, counts:counts()};},
  };
  window.guestQA = qa;
})();
