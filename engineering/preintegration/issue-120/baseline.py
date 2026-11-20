#!/usr/bin/env python3
"""Read-only preflight for #120. Never creates or merges a branch."""
import hashlib
import json
import subprocess
from pathlib import Path

REPO = 'haohongfei2001-png/Riftlet'
ROOT = Path(__file__).resolve().parents[3]


def gh(*args):
    return json.loads(subprocess.check_output(['gh', *args], text=True, cwd=ROOT))


def api(resource):
    return gh('api', f'repos/{REPO}/{resource}')


def main():
    pull = api('pulls/119')
    baseline = api('git/ref/heads/main')['object']['sha']
    head = pull['head']['sha']
    comparison = api(f'compare/{head}...{baseline}')
    predecessor = api(f'compare/e852af3996cb6fea17ed107d8fb8073e06f582ae...{head}')
    inherited = comparison['merge_base_commit']['sha'] == head
    build49 = predecessor['merge_base_commit']['sha'] == predecessor['base_commit']['sha']
    release = gh('release', 'view', '-R', REPO, '--json', 'tagName,isDraft')
    checks = [(c['name'], c.get('conclusion')) for c in api(f'commits/{head}/check-runs')['check_runs']]
    comment = api('issues/comments/7028325810')
    print(json.dumps({
        'main': baseline, 'pr119Head': head, 'pr119Merged': pull['merged'],
        'pr119Draft': pull['draft'], 'pr119IncludesBuild49': build49,
        'mainContainsPR119': inherited, 'upstreamChecks': checks,
        'upstreamAcceptance': comment['html_url'],
        'upstreamAcceptanceSHA256': hashlib.sha256(comment['body'].encode()).hexdigest(),
        'release': release['tagName'],
        'integrationBase': 'REVIEW_MERGED_107_ACCEPTANCE' if inherited and build49 and pull['merged']
                           else 'WAITING_FOR_107_BASELINE'
    }, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
