#!/usr/bin/env python3
"""Run portable, synthetic regressions; no browser, account, queue or network access."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
SOURCES = ['identity.py', 'settled.py', 'test_identity.py',
           'network_policy.swift', 'response.swift', 'main.swift', 'verify.py']

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run():
    with tempfile.TemporaryDirectory(prefix='original-response-unit-tests-') as scratch:
        binary = Path(scratch) / 'verify-response'
        compiled = subprocess.run(['swiftc', '-O', str(ROOT/'network_policy.swift'),
            str(ROOT/'response.swift'), str(ROOT/'main.swift'), '-o', str(binary)],
            capture_output=True, text=True, timeout=90)
        if compiled.returncode:
            raise RuntimeError('swift_compilation_failed')
        native = subprocess.run([str(binary)], capture_output=True, text=True,
                                timeout=15, check=True)
        swift = [json.loads(line) for line in native.stdout.splitlines()]
    python = subprocess.run([sys.executable, '-B', str(ROOT/'test_identity.py')],
                            capture_output=True, text=True, timeout=15, check=True)
    py = json.loads(python.stdout)
    if len(swift) != 2 or not swift[0].get('PASS') or not swift[1].get('success') or not py.get('PASS'):
        raise RuntimeError('regression_assertion_failed')
    counts = {'inputIdentityAndScheduling': py['offlineGateSchedulerAndIdentityCases'],
              'networkCountAndPayloadPolicy': swift[0]['policyCases'],
              'responseProjectionParser': swift[1]['offlineSyntheticPanelCases']}
    if counts != {'inputIdentityAndScheduling': 39, 'networkCountAndPayloadPolicy': 38,
                  'responseProjectionParser': 14}:
        raise RuntimeError('unexpected_fixture_count')
    return {'schema': 1, 'result': 'PASS', 'totalCases': sum(counts.values()), 'cases': counts,
            'pythonCases': py['cases'],
            'sourceSHA256': {name: digest(ROOT/name) for name in SOURCES},
            'GUIActions': 0, 'networkRequests': 0, 'databaseAccesses': 0, 'productInput': 0,
            'syntheticOnly': True, 'nativeBinaryTemporaryAndRemoved': True,
            'liveCaptureReliabilityClaimed': False, 'productCompletionAdmitted': False}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    value = run()
    raw = (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
    if args.output:
        with args.output.open('xb') as dst:
            dst.write(raw)
        print(json.dumps({'result': value['result'], 'totalCases': value['totalCases'],
                          'outputSHA256': hashlib.sha256(raw).hexdigest()}))
    else:
        sys.stdout.buffer.write(raw)

if __name__ == '__main__':
    main()
