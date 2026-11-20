'use strict';

// The official inspectors read installation state. Never expose their process
// lists, extension paths or profile names in the exported evidence.
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const resources = '/Applications/ChatGPT.app/Contents/Resources';
const scripts = path.join(resources, 'plugins/openai-bundled/plugins/chrome/scripts');
const node = path.join(resources, 'cua_node/bin/node');

function inspect(browser, script, allowedStatuses) {
  const result = spawnSync(node, [path.join(scripts, script), '--browser', browser, '--json'], {
    encoding: 'utf8', timeout: 8000, maxBuffer: 1024 * 1024,
    env: {HOME: process.env.HOME, PATH: '/usr/bin:/bin:/usr/sbin:/sbin'},
  });
  if (result.error || !allowedStatuses.includes(result.status)) throw new Error(script);
  const data = JSON.parse(result.stdout);
  if (data.browserFamily !== browser) throw new Error(script);
  return data;
}

function inspectInstallation(browser) {
  try {
    const running = inspect(browser, 'chrome-is-running.js', [0]);
    const extension = inspect(browser, 'check-extension-installed.js', [0, 1, 2]);
    const host = inspect(browser, 'check-native-host-manifest.js', [0, 1]);
    if (typeof running.running !== 'boolean' || typeof host.correct !== 'boolean' ||
        !Array.isArray(extension.profiles) || extension.profiles.some(p =>
          ['installed','enabled','selected'].some(key => typeof p[key] !== 'boolean'))) {
      throw new Error('incomplete diagnostic');
    }
    const selected = extension.profiles.filter(p => p.selected);
    const selectedEnabled = selected.length === 1 && selected[0].installed && selected[0].enabled;
    const anyEnabled = extension.profiles.some(p => p.installed && p.enabled);
    return {
      running: running.running, nativeManifestCorrect: host.correct,
      existingProfiles: extension.profiles.length,
      extensionInstalledProfiles: extension.profiles.filter(p => p.installed).length,
      extensionEnabledProfiles: extension.profiles.filter(p => p.installed && p.enabled).length,
      selectedProfileExtensionEnabled: selectedEnabled,
      status: running.running && host.correct && anyEnabled ? 'READY_FOR_RPC_CHECK' : 'INSTALLATION_BLOCKED',
    };
  } catch {
    return {status: 'DIAGNOSTIC_UNAVAILABLE'};
  }
}

if (require.main === module) {
  const families = process.argv.slice(2);
  if (!families.length) families.push('chrome', 'edge');
  if (families.some(f => !['chrome', 'edge'].includes(f))) {
    console.error('Usage: node installed-controller.cjs [chrome] [edge]');
    process.exitCode = 2;
  } else {
    const report = Object.fromEntries(families.map(f => [f, inspectInstallation(f)]));
    console.log(JSON.stringify(report, null, 2));
    if (Object.values(report).some(r => r.status !== 'READY_FOR_RPC_CHECK')) process.exitCode = 1;
  }
}
