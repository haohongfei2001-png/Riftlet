// Optional attribution for one specifically named, post-input image in the
// original Edge temporary draft. The caller owns the card and progress checks.
function watchEdgeEncodedPreview(file, name) {
  const maxBytes = 8 * 1024 * 1024, maxPixels = 4194304;
  if (!(file instanceof File) || file.type !== 'image/png' || !file.size || file.size > maxBytes
      || file.name !== name || !/^riftlet-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.png$/.test(name)
      || top !== self || location.href !== 'https://chatgpt.com/?temporary-chat=true'
      || typeof OffscreenCanvas !== 'function' || typeof createImageBitmap !== 'function'
      || typeof crypto?.subtle?.digest !== 'function') return null;
  const root = document.documentElement, entry = navigation.currentEntry?.id;
  if (!entry) return null;
  let originalDigest, openViews = 0;
  const current = () => openViews > 0 && document.documentElement === root && navigation.currentEntry?.id === entry
    && location.href === 'https://chatgpt.com/?temporary-chat=true';

  async function encodeOriginal(original) {
    // Reject oversized decompression before decoding even when the PNG fits the byte budget.
    const header = new DataView(await original.slice(0, 24).arrayBuffer());
    if (!current() || header.byteLength < 24 || header.getUint32(0) !== 0x89504e47
        || header.getUint32(4) !== 0x0d0a1a0a || header.getUint32(8) !== 13
        || header.getUint32(12) !== 0x49484452) return false;
    const width = header.getUint32(16), height = header.getUint32(20);
    if (!width || !height || width * height > maxPixels) return false;
    const bitmap = await createImageBitmap(original);
    let png;
    try {
      if (!current() || bitmap.width !== width || bitmap.height !== height) return false;
      const canvas = new OffscreenCanvas(width, height);
      const context = canvas.getContext('2d', {colorSpace: 'srgb'});
      if (!context) return false;
      context.drawImage(bitmap, 0, 0);
      png = await canvas.convertToBlob({type:'image/png'});
    } finally { bitmap.close(); }
    if (!current() || png.type !== 'image/png' || !png.size || png.size > maxBytes) return null;
    return {size: png.size, bytes: new Uint8Array(await crypto.subtle.digest('SHA-256', await png.arrayBuffer()))};
  }

  async function compare(url) {
    if (!originalDigest) {
      originalDigest = encodeOriginal(file);
      file = null;
    }
    const expected = await originalDigest;
    const prefix = 'data:image/png;base64,';
    if (!current() || !expected || url.length !== prefix.length + 4 * Math.ceil(expected.size / 3)) return null;
    const decoded = atob(url.slice(prefix.length));
    if (decoded.length !== expected.size) return null;
    const preview = new Uint8Array(decoded.length);
    for (let i = 0; i < decoded.length; i++) preview[i] = decoded.charCodeAt(i);
    const actual = new Uint8Array(await crypto.subtle.digest('SHA-256', preview));
    if (!current() || actual.length !== 32 || expected.bytes.length !== 32
        || !actual.every((byte, i) => byte === expected.bytes[i])) return null;
    return {encodedByteCount: expected.size, encodedSHA256: [...actual].map(b => b.toString(16).padStart(2, '0')).join('')};
  }

  // Two separate view identities share only the immutable original's encoding.
  // Retiring the progress card cannot cancel a later original-form content check.
  function view() {
    openViews++;
    let image, source, identity, closed = false, state = 'unavailable';
    const timer = setTimeout(close, 60000);
    function close() {
      if (closed) return;
      clearTimeout(timer); closed = true;
      image = source = identity = null; state = 'unavailable';
      if (--openViews === 0) { file = null; originalDigest = null; }
    }
    function inspect(candidate, settled) {
      try {
        if (closed || !current()) { close(); return 'unavailable'; }
        if (!(candidate instanceof HTMLImageElement) || !candidate.isConnected
            || !candidate.complete || candidate.naturalWidth <= 0) return 'unavailable';
        const src = candidate.getAttribute('src');
        if (image && (candidate !== image || src !== source)) { close(); return 'mismatch'; }
        if (image) return candidate.currentSrc === source ? state : 'unavailable';
        if (!src || !src.startsWith('data:image/png;base64,') || candidate.currentSrc !== src
            || src.length > 22 + 4 * Math.ceil(maxBytes / 3)) return 'unavailable';
        image = candidate; source = src; state = 'encoding';
        compare(src).then(proof => {
          if (!closed) { identity = proof; state = proof ? 'matched' : 'mismatch'; }
        }).catch(() => { if (!closed) state = 'unavailable'; })
          .then(() => { if (!closed) settled?.(); });
        return state;
      } catch { close(); return 'unavailable'; }
    }
    return {inspect, close, get identity() { return identity; }};
  }
  const progress = view();
  progress.content = view();
  return progress;
}
