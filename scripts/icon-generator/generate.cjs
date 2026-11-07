#!/usr/bin/env node
// Read the original SVG unchanged. Rasterize its full square viewBox at every
// required size; no padding, cropping, recoloring, shadow or replacement artwork.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const { Resvg } = require('@resvg/resvg-js');

const repo = path.resolve(__dirname, '../..');
const source = path.join(repo, 'website-assets/riftlet.svg');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const requireFact = (value, reason) => { if (!value) throw new Error(reason); };
requireFact(process.argv.length === 3 && process.platform === 'darwin', 'Usage on macOS: node generate.cjs NEW_ABSOLUTE_OUTPUT');
const output = process.argv[2];
requireFact(path.isAbsolute(output) && !fs.existsSync(output), 'Use a new absolute output directory');
requireFact(fs.realpathSync(path.dirname(output)) === path.dirname(output), 'Output parent must be a real directory');
fs.mkdirSync(output, { mode: 0o700 });
const iconset = path.join(output, 'Riftlet.iconset');
fs.mkdirSync(iconset);
const original = fs.readFileSync(source);
const slots = [];
for (const logicalSize of [16, 32, 128, 256, 512]) {
  for (const scale of [1, 2]) {
    const pixels = logicalSize * scale;
    const renderer = new Resvg(original, {
      fitTo: { mode: 'width', value: pixels },
      font: { loadSystemFonts: false },
    });
    requireFact(renderer.width === 112 && renderer.height === 112, 'Original SVG viewBox/size changed; review before regenerating');
    const image = renderer.render();
    requireFact(image.width === pixels && image.height === pixels, 'Raster dimensions differ');
    const filename = `icon_${logicalSize}x${logicalSize}${scale === 2 ? '@2x' : ''}.png`;
    const data = image.asPng();
    fs.writeFileSync(path.join(iconset, filename), data, { flag: 'wx' });
    slots.push({ filename, logicalSize, scale, pixels, sha256: sha(data) });
  }
}
const icon = path.join(output, 'Riftlet.icns');
const result = cp.spawnSync('/usr/bin/iconutil', ['--convert', 'icns', '--output', icon, iconset], { encoding: 'utf8' });
fs.writeFileSync(path.join(output, 'iconutil.stdout.log'), result.stdout || '', { flag: 'wx' });
fs.writeFileSync(path.join(output, 'iconutil.stderr.log'), result.stderr || '', { flag: 'wx' });
requireFact(result.status === 0 && fs.existsSync(icon), 'iconutil failed; retain output evidence');
requireFact(fs.readFileSync(source).equals(original), 'Source SVG changed during generation');
const manifest = {
  schema: 1,
  source: 'website-assets/riftlet.svg', sourceSHA256: sha(original),
  transformation: 'Unmodified full SVG rasterized at each required size; no crop, padding, color or shape edits',
  renderer: { package: '@resvg/resvg-js', version: require('@resvg/resvg-js/package.json').version,
    lockSHA256: sha(fs.readFileSync(path.join(__dirname, 'package-lock.json'))),
    generatorSHA256: sha(fs.readFileSync(__filename)) },
  container: { tool: '/usr/bin/iconutil', toolSHA256: sha(fs.readFileSync('/usr/bin/iconutil')),
    platform: process.platform, architecture: process.arch, node: process.version },
  slots, icon: { filename: 'Riftlet.icns', sha256: sha(fs.readFileSync(icon)), bytes: fs.statSync(icon).size },
  runtimeDependencyAdded: false,
};
fs.writeFileSync(path.join(output, 'icon-generation.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ result: 'ICON_GENERATED', sourceSHA256: manifest.sourceSHA256, iconSHA256: manifest.icon.sha256, slots: slots.length }));
