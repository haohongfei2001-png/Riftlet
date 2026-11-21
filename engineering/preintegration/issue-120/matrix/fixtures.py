"""Collect scoped evidence from the existing build-53 fixture programs. No App or live site."""
import argparse
import hashlib
import json
import os
import platform
import plistlib
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
JS = 'Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js'
SIM = 'Tests/WebPageProgram/acceptance-program.test.cjs'
WEB = 'Tests/WebPageProgram/chrome-input-resource.test.cjs'
SUPPORT = 'Tests/WebPageProgram/'
BROWSERS = {'chrome': ('Google Chrome', 'com.google.Chrome'),
            'edge': ('Microsoft Edge', 'com.microsoft.edgemac')}
SLICES = {
    'I03': 'the activated entry can mount its input synchronously, or later in its own controlled portal',
    'I01': 'a setter exception is uncertain and never causes a second attachment path',
    'E01': 'START requires a current new accepted attachment, not setter, change, old card or filename placeholder',
}


def sha(value):
    return hashlib.sha256(value).hexdigest()


def sources(paths):
    return {p: sha((ROOT / p).read_bytes()) for p in paths}


def run_node(args, env):
    proc = subprocess.run(['node', '--test', '--test-reporter=tap', *args], cwd=ROOT,
                          env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=100)
    return proc.stdout, proc.returncode


def collect(browser, headless):
    stamp = datetime.now(timezone.utc).isoformat(timespec='seconds')
    evidence = dict(schema=1, browser=browser, provider='chatgpt', observedAt=stamp,
                    platform=platform.mac_ver()[0] or platform.system(), arch=platform.machine(),
                    sourceSHA='ef3f58cb7baf26ee3c0fd7c6b1db9d9d32ca21d0',
                    candidate=None, versions={}, results=[])
    # A caller's overrides must never relabel the adapter bytes or select another executable.
    env = {k: v for k, v in os.environ.items() if not k.startswith('RIFTLET_')
           and k not in ('SOURCE_OVERRIDE', 'NODE_OPTIONS', 'NODE_PATH')}
    if not headless:
        evidence['kind'] = 'simulated-js'
        evidence['versions']['node'] = subprocess.check_output(['node', '-v'], text=True).strip()
        evidence['inputs'] = sources([JS, SIM, SUPPORT + 'independent-input-fixture.cjs'])
        pattern = '^(' + '|'.join(re.escape(v) for v in SLICES.values()) + ')$'
        tap, code = run_node(['--test-name-pattern=' + pattern, SIM], env)
        for case, title in SLICES.items():
            ok = re.findall(r'^ok \d+ - ' + re.escape(title) + '$', tap, re.M)
            evidence['results'].append(dict(case=case, test=title,
                                            passed=len(ok) == 1 and code == 0))
    else:
        name, bundle = BROWSERS[browser]
        app = Path('/Applications') / (name + '.app') / 'Contents'
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        binary = app / 'MacOS' / info['CFBundleExecutable']
        if info['CFBundleIdentifier'] != bundle or not binary.is_file():
            raise ValueError('actual installed browser required')
        evidence['versions'].update(bundle=bundle, browser=info['CFBundleShortVersionString'])
        evidence['kind'] = 'headless-web-only'
        evidence['inputs'] = sources([JS, WEB, SUPPORT + 'original-error-card-application.cjs',
                                     SUPPORT + 'attachment-entry-application.cjs', SUPPORT + 'native-chrome-cleanup.cjs'])
        env.update(RIFTLET_CHROME_BIN=str(binary), RIFTLET_REQUIRE_CHROME='1',
                   RIFTLET_NATIVE_CASE='owned-original-failure-card')
        flag = 'true' if browser == 'edge' else 'false'
        pattern = 'native Chrome independent append .*"namedErrorCard":true,"edge":' + flag
        tap, code = run_node(['--test-name-pattern=' + pattern, WEB], env)
        observed = [json.loads(line[2:]) for line in tap.splitlines() if line.startswith('# {')]
        executed = re.findall(r'^ok \d+ - (' + pattern + '.*)$', tap, re.M)
        evidence['results'].append(dict(case='E04', test='original-failure-card',
                                       passed=code == 0 and len(executed) == 1 and len(observed) == 1,
                                       counters=observed[0] if len(observed) == 1 else {}))
    evidence['exitCode'] = code
    evidence['transcriptSHA256'] = sha(tap.encode())
    return evidence, tap


def main():
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['simulation', 'headless'])
    p.add_argument('browser', choices=BROWSERS)
    p.add_argument('directory', type=Path)
    args = p.parse_args()
    if args.mode == 'simulation' and args.browser != 'chrome':
        p.error('the inherited simulated native target is Chrome only')
    stem = args.mode + '-' + args.browser
    if any((args.directory / (stem + ext)).exists() for ext in ('.json','.tap')):
        p.error('use a fresh results directory to preserve previous evidence')
    result, tap = collect(args.browser, args.mode == 'headless')
    args.directory.mkdir(parents=True, exist_ok=True)
    (args.directory / (stem + '.tap')).write_text(tap)
    (args.directory / (stem + '.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(stem, [(r['case'], r['passed']) for r in result['results']])
    return int(any(not r['passed'] for r in result['results']))


if __name__ == '__main__':
    raise SystemExit(main())
