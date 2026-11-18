'use strict';
// Only loopback fixtures call this script. watchProbe supplies the product's
// exact function with synthetic route/entry values for this isolated page.
async function hash(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('');
}

async function runWatcher(file, preview) {
  const reader = new FileReader();
  const loaded = new Promise((resolve, reject) => {
    reader.onload = resolve;
    reader.onerror = reject;
  });
  reader.readAsDataURL(preview);
  await loaded;
  const image = new Image();
  image.src = reader.result;
  document.body.append(image);
  const watcher = watchProbe(file, file.name);
  if (!watcher) throw Error('missing observer');
  try {
    await image.decode();
    const deadline = performance.now() + 3000;
    while (performance.now() < deadline) {
      const state = watcher.inspect(image);
      if (state !== 'encoding') return state;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw Error('observer did not settle');
  } finally {
    watcher.close();
    image.remove();
  }
}

async function fingerprint(img) {
  const bytes = Uint8Array.from(atob(img.src.split(',')[1]), char => char.charCodeAt(0));
  const file = new File([bytes], 'riftlet-' + crypto.randomUUID() + '.png', {type:'image/png'});
  const variants = {};
  const sources = {
    htmlImage: img,
    bitmap: await createImageBitmap(file),
    rawBitmap: await createImageBitmap(file, {colorSpaceConversion: 'none'})
  };
  const checks = {};
  for (const [kind, source] of Object.entries(sources)) {
    for (const backend of ['html', 'offscreen']) {
      for (const frequent of [false, true]) {
        const canvas = backend === 'offscreen' ? new OffscreenCanvas(img.naturalWidth, img.naturalHeight)
                                             : document.createElement('canvas');
        canvas.width = img.naturalWidth;
        canvas.height = img.naturalHeight;
        const ctx = canvas.getContext('2d', {colorSpace:'srgb', willReadFrequently:frequent});
        ctx.drawImage(source, 0, 0);
        const png = backend === 'offscreen' ? await canvas.convertToBlob({type:'image/png'})
                          : await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
        variants[[kind, backend, frequent ? 'cpuRead' : 'normal'].join('/')] = [
          png.size, await hash(await png.arrayBuffer()),
          await hash(ctx.getImageData(0, 0, canvas.width, canvas.height).data)
        ];
        if (kind === 'htmlImage' && backend === 'html' && !frequent) {
          checks.samePNG = await runWatcher(file, png);
          // A PNG with identical displayed pixels but an extra trailing byte
          // must not acquire an identity from its appearance.
          checks.samePixelsDifferentPNG = await runWatcher(file, new Blob([png, 'x'], {type:'image/png'}));
        }
      }
    }
    if (kind !== 'htmlImage') source.close();
  }
  return {width:img.naturalWidth, height:img.naturalHeight, variants, checks};
}

window.addEventListener('load', async () => {
  let result = [];
  try {
    for (const image of Array.from(document.images)) result.push(await fingerprint(image));
  } catch (err) {
    result = {error: err.name};
  }
  await fetch('result', {method:'POST', body:JSON.stringify(result)});
});
