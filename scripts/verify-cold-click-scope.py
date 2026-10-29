#!/usr/bin/env python3
"""Independent technical branch only; never grants PR #15 integration admission."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

BASE = 'c15fd4b4a27659946ef49280131e875f4d5ab9d1'
BASE_GATE = 'scripts/verify-final-product-composition.py'
BASE_GATE_BLOB = 'd587f376a1382fc5a26e3c3306037af99df54c39'
# Filled only after a committed tree has independent technical review.
REVIEWED_SOURCE = None
META = frozenset({
    'scripts/verify-cold-click-scope.py',
    'engineering/evidence/2026-10-29-cold-click-reliability/README.md',
    'engineering/evidence/2026-10-29-cold-click-reliability/results.json',
})
DELTA = frozenset({
    *META,
    'docs/EXECUTION_BOARD.md',
    'Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js',
    'Sources/RiftletApp/RiftletMain.swift',
    'Sources/RiftletApp/AutomationPermissionPublication.swift',
    'Tests/RiftletAppTests/AutomationPermissionPublicationTests.swift',
    'Tests/RiftletAppTests/ColdClickBoundaryTests.swift',
    'Tests/WebPageProgram/acceptance-program.test.cjs',
    '.github/workflows/cold-click-reliability.yml',
    'Tests/ColdClickBrowser/package.json',
    'Tests/ColdClickBrowser/package-lock.json',
    'Tests/ColdClickBrowser/cold-click.test.mjs',
    'Tests/ColdClickBrowser/README.md',
})


def git_environment():
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    environment['GIT_CONFIG_NOSYSTEM'] = '1'
    environment['GIT_CONFIG_GLOBAL'] = os.devnull
    return environment


def git(root, *args):
    return subprocess.check_output(['git', '--no-replace-objects', '-C', str(root), *args],
                                   env=git_environment(), timeout=180)


def tree(root, ref):
    result = {}
    for entry in git(root, 'ls-tree', '-rz', ref).split(b'\0'):
        if entry:
            obj, path = entry.split(b'\t', 1)
            result[path.decode()] = obj.decode()
    return result


def differences(a, b, excluded=frozenset()):
    return sorted(p for p in (a.keys() | b.keys()) - excluded if a.get(p) != b.get(p))


def audit(root, ref):
    checks = []
    def check(name, ok, **extra):
        checks.append({'check': name, 'result': 'PASS' if ok else 'FAIL', **extra})
    resolved = git(root, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()
    base, current = tree(root, BASE), tree(root, resolved)
    check('base_ancestor', subprocess.run(['git', '--no-replace-objects', '-C', str(root),
        'merge-base', '--is-ancestor', BASE, resolved], env=git_environment(), timeout=180).returncode == 0)
    check('unchanged_formal_gate', base[BASE_GATE] == current.get(BASE_GATE)
        == '100644 blob ' + BASE_GATE_BLOB)
    # Run the exact retained formal gate at its original admitted checkpoint.
    # Its review pin/policy is neither changed nor applied to this new branch.
    # Execute the pinned Git blob, never a possibly dirty working-tree script.
    with tempfile.NamedTemporaryFile(suffix='.py') as source:
        source.write(git(root, 'cat-file', 'blob', BASE_GATE_BLOB))
        source.flush()
        historical = subprocess.run([sys.executable, '-B', source.name, BASE,
            '--repository', str(root)], capture_output=True, text=True,
            env=git_environment(), timeout=180)
    payload = json.loads(historical.stdout)
    check('original_formal_admission', historical.returncode == 0 and payload['result'] == 'PASS'
        and payload['revision'] == BASE)
    delta = differences(base, current)
    check('exact_scoped_paths', set(delta) <= DELTA, differences=delta,
          unexpected=sorted(set(delta) - DELTA))
    check('all_delta_regular_files', all(current.get(p, '').startswith('100644 blob ') for p in delta))
    check('non_author_review_pin', isinstance(REVIEWED_SOURCE, str) and len(REVIEWED_SOURCE) == 40)
    if REVIEWED_SOURCE:
        reviewed = tree(root, REVIEWED_SOURCE)
        check('reviewed_ancestor', subprocess.run(['git', '--no-replace-objects', '-C', str(root),
            'merge-base', '--is-ancestor', REVIEWED_SOURCE, resolved], env=git_environment(), timeout=180).returncode == 0)
        changed = differences(reviewed, current, META)
        check('exact_reviewed_tree', not changed, differences=changed)
        check('metadata_regular_and_preexisting', all(
            reviewed.get(p, '').startswith('100644 blob ') and current.get(p, '').startswith('100644 blob ')
            for p in META))
    return {'result': 'PASS' if all(c['result'] == 'PASS' for c in checks) else 'FAIL',
        'revision': resolved, 'base': BASE, 'reviewedSource': REVIEWED_SOURCE,
        'scope': 'independent technical review; not formal PR integration or upload admission', 'checks': checks}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('revision', nargs='?', default='HEAD')
    args = parser.parse_args()
    try:
        report = audit(Path(__file__).resolve().parents[1], args.revision)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report = {'result': 'FAIL', 'error': str(error)}
    print(json.dumps(report, indent=2))
    sys.exit(0 if report['result'] == 'PASS' else 1)
