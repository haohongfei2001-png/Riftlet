// Both accepted forms have a separately named Remove button and a single
// loaded image. The caller verifies newness, original draft, and encoded bytes.
(filename, labels, scope, visual, image, remove) => {
  const nested = labels.filter(node => node !== scope && node.tagName === 'DIV' &&
    visual.contains(node) && node.contains(image));
  if (nested.length) return nested;
  const namedRoot = labels.length === 3 && labels.includes(scope) && labels.includes(image) &&
    labels.includes(remove) && filename.test(scope.getAttribute('aria-label') || '');
  return namedRoot && visual.tagName === 'SPAN' && visual.contains(image) ? [scope] : [];
}
