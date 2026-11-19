// Optional attribution for one specifically named, post-input image in the
// original Edge temporary draft. The caller owns the card and progress checks.
function watchEdgeEncodedPreview(file, name) {
  const maxBytes = 8 * 1024 * 1024, maxPixels = 4194304;
  if (!(file instanceof File) || file.type !== 'image/png' || !file.size || file.size > maxBytes
      || file.name !== name || !/^riftlet-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$/.test(name)
      || top !== self || location.href !== 'https://chatgpt.com/?temporary-chat=true'
      || typeof OffscreenCanvas !== 'function' || typeof createImageBitmap !== 'function'
      || typeof crypto?.subtle?.digest !== 'function') return null;
  const root = document.documentElement, entry = navigation.currentEntry?.id;
  if (!entry) return null;
  let image = null, source = null, state = 'unavailable', closed = false;
  const timer = setTimeout(close, 60000);
  const current = () => !closed && document.documentElement === root && navigation.currentEntry?.id === entry
    && location.href === 'https://chatgpt.com/?temporary-chat=true';
  function close() {
    clearTimeout(timer); closed = true;
    file = null; image = null; source = null; state = 'unavailable';
  }
  async function matches(original, url) {
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
    const prefix = 'data:image/png;base64,';
    if (!current() || png.type !== 'image/png' || !png.size || png.size > maxBytes
        || url.length !== prefix.length + 4 * Math.ceil(png.size / 3)) return false;
    const decoded = atob(url.slice(prefix.length));
    if (decoded.length !== png.size) return false;
    const preview = new Uint8Array(decoded.length);
    for (let i = 0; i < decoded.length; i++) preview[i] = decoded.charCodeAt(i);
    const [expected, actual] = await Promise.all([
      png.arrayBuffer().then(bytes => crypto.subtle.digest('SHA-256', bytes)),
      crypto.subtle.digest('SHA-256', preview)
    ]);
    const digest = new Uint8Array(expected), other = new Uint8Array(actual);
    return current() && digest.length === 32 && other.length === 32 && digest.every((byte, i) => byte === other[i]);
  }
  function inspect(candidate) {
    try {
      if (!current()) { close(); return 'unavailable'; }
      if (!(candidate instanceof HTMLImageElement) || !candidate.isConnected
          || !candidate.complete || candidate.naturalWidth <= 0) return 'unavailable';
      const src = candidate.getAttribute('src');
      if (image && (candidate !== image || src !== source)) { close(); return 'mismatch'; }
      if (image) return candidate.currentSrc === source ? state : 'unavailable';
      if (!src || !src.startsWith('data:image/png;base64,') || candidate.currentSrc !== src
          || src.length > 22 + 4 * Math.ceil(maxBytes / 3)) return 'unavailable';
      image = candidate; source = src; state = 'encoding';
      // Never re-read a changed/replaced card and never start another encode for this input.
      matches(file, src).then(ok => {
        if (!closed) state = ok ? 'matched' : 'mismatch';
      }).catch(() => { if (!closed) state = 'unavailable'; });
      return state;
    } catch { close(); return 'unavailable'; }
  }
  return {inspect, close};
}
