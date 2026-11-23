'use strict';
(() => {
  if (location.protocol !== 'file:' || window !== top ||
      document.title !== 'Riftlet local world ownership fixture') throw Error('Owned local fixture required');
  const node = document.querySelector('#shared');
  const nonce = crypto.randomUUID();
  const prototype = XMLHttpRequest.prototype;
  const request = new XMLHttpRequest();
  const other = new XMLHttpRequest();
  const methods = [window.fetch, prototype.open, prototype.send, prototype.abort];
  if (Object.hasOwn(window, 'ownedIsolatedFixture') || Object.hasOwn(prototype, 'isolatedPrototypeTag') ||
      Object.hasOwn(node, 'isolatedWrapperTag')) throw Error('An earlier isolated fixture is present');
  request.isolatedInstanceTag = nonce;
  prototype.isolatedPrototypeTag = nonce;
  node.isolatedWrapperTag = nonce;
  node.setAttribute('data-isolated-tag', nonce);
  window.ownedIsolatedFixture = Object.freeze({node, nonce, request, other});
  window.readOwnedIsolatedFixture = () => ({
    isolatedGlobal: window.ownedIsolatedFixture.nonce === nonce,
    mainGlobalAbsent: !Object.hasOwn(window, 'ownedMainFixture'),
    mainReaderAbsent: !Object.hasOwn(window, 'readOwnedMainFixture'),
    mainAttribute: node.getAttribute('data-main-tag'),
    isolatedAttributeMatches: node.getAttribute('data-isolated-tag') === nonce,
    mainWrapperAbsent: !Object.hasOwn(node, 'mainWrapperTag'),
    isolatedWrapperMatches: Object.hasOwn(node, 'isolatedWrapperTag') && node.isolatedWrapperTag === nonce,
    mainPrototypeAbsent: !Object.hasOwn(prototype, 'mainPrototypeTag'),
    isolatedPrototype: Object.hasOwn(prototype, 'isolatedPrototypeTag') && prototype.isolatedPrototypeTag === nonce,
    originalInstance: request === window.ownedIsolatedFixture.request && request.isolatedInstanceTag === nonce && !Object.hasOwn(request,'mainInstanceTag'),
    distinctSecondInstance: other !== request && !Object.hasOwn(other, 'isolatedInstanceTag') && !Object.hasOwn(other, 'mainInstanceTag'),
    ownPrototype: Object.getPrototypeOf(request) === prototype && Object.getPrototypeOf(other) === prototype,
    unopened: request.readyState === 0 && other.readyState === 0 && request.responseURL === '' && other.responseURL === '',
    methodsUnchanged: [window.fetch, prototype.open, prototype.send, prototype.abort].every((m,i)=>m === methods[i])
  });
})();
