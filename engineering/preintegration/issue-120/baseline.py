#!/usr/bin/env python3
"""Check the formal 1.0.7 admission against GitHub, signed bytes and observed gates."""
import argparse
import base64
from functools import lru_cache
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile

from gate107 import canonical, hexdigest, require, sha, verify_gate

REPO = 'haohongfei2001-png/Riftlet'
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DOCS = 'docs/releases/1.0.7/'
EVIDENCE = DOCS + 'evidence/'
ADMISSION = 'engineering/mainline/source-admission.json'
BUILD49 = 'e852af3996cb6fea17ed107d8fb8073e06f582ae'
WAIT = 'WAITING_FOR_107_BASELINE'
CHECKS = {
    'Native ARM64': 'native-foundation.yml', 'Native Intel': 'native-foundation.yml',
    'Native source admission': 'native-foundation.yml',
    'Feedback native and service': 'feedback-v01.yml', 'Feedback source admission': 'feedback-v01.yml',
}
GATES = ('G1','G2','G3','G4','G5','G6')
@lru_cache(maxsize=128)
def api(resource):
    return json.loads(subprocess.check_output(
        ['gh','api',f'repos/{REPO}/{resource}'], cwd=ROOT, timeout=45))


def blob(ref, path):
    data = api(f'contents/{path}?ref={ref}')
    require(data['type'] == 'file' and data['encoding'] == 'base64' and data['path'] == path, 'missing ' + path)
    return base64.b64decode(''.join(data['content'].split()), validate=True)


def ancestor(older, newer):
    require(hexdigest(older, 40) and hexdigest(newer, 40), 'invalid commit')
    require(api(f'compare/{older}...{newer}')['merge_base_commit']['sha'] == older, 'wrong ancestry')


def verify_checks(records, head):
    require(set(records) == set(CHECKS), 'missing or unexpected CI')
    checks = api(f'commits/{head}/check-runs?filter=latest&per_page=100')
    require(checks['total_count'] == len(checks['check_runs']), 'incomplete latest check list')
    for name, workflow in CHECKS.items():
        pin = records[name]
        run_id, job_id = pin['runID'], pin['jobID']
        require(pin['conclusion'] == 'success' and all(type(i) is int and i > 0 for i in
                (run_id,job_id,pin['attempt'],pin['workflowID'])), 'bad CI record')
        latest = [c for c in checks['check_runs'] if c['name'] == name]
        require(len(latest) == 1, 'missing or ambiguous latest ' + name)
        check = latest[0]
        job, run = api(f'actions/jobs/{job_id}'), api(f'actions/runs/{run_id}')
        require(all(r['head_sha'] == head and r['status'] == 'completed' and r['conclusion'] == 'success'
                    for r in (check,job,run)), 'unsuccessful or stale CI: ' + name)
        require(check['id'] == job['id'] == job_id and check['app']['slug'] == 'github-actions'
                and job['name'] == name and job['run_id'] == run['id'] == run_id
                and job['run_attempt'] == run['run_attempt'] == pin['attempt']
                and run['workflow_id'] == pin['workflowID'] and run['path'] == '.github/workflows/' + workflow
                and run['event'] == 'pull_request' and run['repository']['full_name'] == REPO
                and any(p['number'] == 119 and p['head']['sha'] == head and p['base']['ref'] == 'main'
                        for p in run['pull_requests']), 'wrong workflow, job or PR: ' + name)


def verify_source(record, head, merge):
    c, review = record['candidate'], record['reviewSHA']
    source = c['sourceSHA']
    require(hexdigest(source,40) and hexdigest(review,40), 'invalid source pin')
    h, g, p = (api(f'commits/{ref}') for ref in (head, review, source))
    require([v['sha'] for v in h['parents']] == [review]
            and [f['filename'] for f in h['files']] == [ADMISSION] and h['files'][0]['status'] == 'modified',
            'head is not admission-only')
    diff = api(f'compare/{source}...{review}')
    require(diff['merge_base_commit']['sha'] == source and len(diff['files']) < 300
            and all(f['filename'].startswith(DOCS) and f.get('previous_filename',DOCS).startswith(DOCS)
                    for f in diff['files']), 'product changed after source review')
    decision = json.loads(blob(head, ADMISSION))
    tree = g['commit']['tree']['sha']
    require(decision['reviewedSource'] == review and decision['reviewedTree'] == tree
            and decision['reviewedBase'] == merge['parents'][0]['sha'], 'admission base or review tree mismatch')
    accepted = []
    for r in decision['reviews']:
        report = json.loads(r['report'])
        accepted.append(r['source'] == review and r['tree'] == tree and r['result'] == 'PASS'
                        and sha(r['report'].encode()) == r['sha256'] and report['result'] == 'PASS'
                        and report['reviewedSource'] == review and report['reviewedTree'] == tree
                        and report['reviewedBase'] == decision['reviewedBase'] and report['findings'] == []
                        and r['reviewer'] == report['reviewer'] and r['reviewer'] != decision['authorRole'])
    require(any(accepted), 'missing source review')
    require(hexdigest(record['productReviewSHA256']), 'missing product review')
    path = record['productReviewFile']
    require(path.startswith('independent-') and path.endswith('.json') and '/' not in path, 'invalid review file')
    raw = blob(review, EVIDENCE + path)
    proof = json.loads(raw)
    require(sha(raw) == record['productReviewSHA256'] and proof['product'] == source
            and proof['tree'] == p['commit']['tree']['sha'] and proof['result'] in ('PASS','PASS_WITH_SCOPED_OBSERVATIONS'),
            'product review mismatch')
    info = plistlib.loads(blob(source,'Resources/Info.plist'))
    require(info['CFBundleVersion'] == c['build'] and info['CFBundleShortVersionString'] == '1.0.7', 'wrong product build')
    require(merge['commit']['tree']['sha'] == h['commit']['tree']['sha'], 'untested merge tree')


def verify_manifest_identity(manifest,candidate,release):
    files = {k.removeprefix('Riftlet.app/'):v for k,v in manifest['files'].items() if k.startswith('Riftlet.app/')}
    require(manifest['stage'] == 'STAPLED' and manifest['build']['source']['commit'] == candidate['sourceSHA']
            and manifest['build']['version'] == '1.0.7' and manifest['build']['build'] == candidate['build']
            and manifest['notarization']['submissionID'] == release['appSubmissionID']
            and set(manifest['build']['architectures']) == {'arm64','x86_64'}
            and sha(canonical(files)) == candidate['appSHA256'], 'signed App inventory mismatch')


def verify_package(record, workspace):
    require(workspace is not None, 'original signed package workspace required')
    candidate = record['candidate']
    ref = record['reviewSHA']
    path = EVIDENCE + 'build' + candidate['build'] + '.json'
    raw = blob(ref,path)
    require(record['packageRecord'] == {'path':path,'commit':ref,'sha256':sha(raw)}, 'reviewed package record mismatch')
    release = json.loads(raw)
    require(release['source'] == candidate['sourceSHA'] and release['version'] == '1.0.7'
            and release['build'] == candidate['build'] and release['finalSHA256'] == candidate['dmgSHA256'],
            'different reviewed package')
    spec = importlib.util.spec_from_file_location('riftlet_release_dmg', ROOT/'scripts/release-dmg.py')
    dmg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dmg)
    receipt = json.loads((workspace/'formal-dmg/dmg-receipt.json').read_bytes())
    image = workspace/'formal-dmg/Riftlet-1.0.7.dmg'
    require(receipt['stage'] == 'VERIFIED_STAPLED_DMG' and receipt['source'] == candidate['sourceSHA']
            and receipt['appSubmissionID'] == release['appSubmissionID'] and receipt['submissionID'] == release['submissionID']
            and receipt['notaryStatus'] == release['notaryStatus'] == 'Accepted'
            and dmg.R.digest(image) == receipt['finalSHA256'] == candidate['dmgSHA256'], 'wrong signed bytes or notary receipt')
    team = 'ZB9D4T66QB'
    manifest = dmg.R.verify_package(workspace/'Riftlet-Release',receipt['manifestSHA256'],team)
    verify_manifest_identity(manifest,candidate,release)
    with tempfile.TemporaryDirectory(prefix='riftlet-w0-') as tmp:
        logs = Path(tmp).resolve()
        dmg.ticket(image, logs/'ticket.log')
        dmg.image_signature(image,team,logs)
        dmg.assess(image,'open',logs)
        dmg.inspect_image(image,manifest,logs)
    require(dmg.R.digest(image) == candidate['dmgSHA256'], 'package changed while checking')


def verify(record, pull, main, workspace):
    require(pull['merged'] is True and pull['base']['ref'] == 'main' and pull['base']['repo']['full_name'] == REPO,
            '#119 has not merged into main')
    head, merge_sha = pull['head']['sha'], pull['merge_commit_sha']
    require(record['schema'] == 1 and record['pr119Head'] == head and record['mergeSHA'] == merge_sha,
            'stale head or merge record')
    ancestor(BUILD49, head)
    ancestor(merge_sha,record['mainlineSHA'])
    ancestor(record['mainlineSHA'],main)
    merge = api(f'commits/{merge_sha}')
    require(len(merge['parents']) == 2 and merge['parents'][1]['sha'] == head, 'unexpected #119 merge parents')
    candidate = record['candidate']
    require(set(candidate) == {'sourceSHA','appSHA256','dmgSHA256','build'} and hexdigest(candidate['sourceSHA'],40)
            and all(hexdigest(candidate[k]) for k in ('appSHA256','dmgSHA256'))
            and candidate['build'].isascii() and candidate['build'].isdecimal() and int(candidate['build']) >= 53,
            'incomplete or superseded candidate')
    verify_source(record,head,merge)
    verify_checks(record['checks'],head)
    verify_package(record,workspace)
    compare_current_product(merge_sha,main)
    verify_evidence(record,main,workspace)


def compare_current_product(merge_sha,main):
    # A revert is still a descendant. Compare complete root entry IDs for
    # everything except documentation, engineering evidence and website content.
    def product_tree(ref):
        tree = api(f'git/trees/{ref}')
        require(tree['truncated'] is False, 'truncated product tree')
        return {e['path']:(e['type'],e['mode'],e['sha']) for e in tree['tree']
                if e['path'] not in ('engineering','docs','website','updates')}
    require(product_tree(merge_sha) == product_tree(main),'main no longer has the admitted product tree')


def verify_evidence_admission(record,main,index_digest):
    # Use the project's normal non-author source admission, also for evidence
    # collected after freezing the signed package. No pre-approved dummy roots.
    h = record['acceptanceAdmissionSHA']
    ancestor(h,main)
    admission = api(f'commits/{h}')
    require(len(admission['parents']) == 1 and [f['filename'] for f in admission['files']] == [ADMISSION]
            and admission['files'][0]['status'] == 'modified', 'missing evidence admission-only child')
    reviewed = admission['parents'][0]['sha']
    tree = api(f'commits/{reviewed}')['commit']['tree']['sha']
    pin = json.loads(blob(h,ADMISSION))
    require(pin['reviewedSource'] == reviewed and pin['reviewedTree'] == tree, 'wrong evidence review tree')
    for audit in pin['reviews']:
        report = json.loads(audit['report'])
        if (audit['result'] == report['result'] == 'PASS' and report['findings'] == []
                and audit['source'] == report['reviewedSource'] == reviewed
                and audit['tree'] == report['reviewedTree'] == tree
                and report['reviewedBase'] == pin['reviewedBase']
                and report['reviewer'] == audit['reviewer'] and audit['reviewer'] != pin['authorRole']
                and hexdigest(report.get('acceptance107IndexSHA256'))
                and report['acceptance107IndexSHA256'] == index_digest
                and sha(audit['report'].encode()) == audit['sha256']):
            return reviewed
    raise ValueError('no independent admission of the original evidence index')


def verify_evidence(record,main,workspace):
    candidate = record['candidate']
    require(set(record['gates']) == set(GATES), 'incomplete gates')
    index = {'candidate':candidate,'pr119Head':record['pr119Head'],'gates':record['gates']}
    reviewed = verify_evidence_admission(record,main,sha(canonical(index)))
    seen = {k:set() for k in ('invocation','operation','originalPNG','newCard','sampleID')}
    raw_digests = set()
    for gate in GATES:
        entry = record['gates'][gate]
        require(entry['status'] == 'PASS', gate + ' is unverified')
        receipts = []
        for kind in ('run','observer'):
            ref = entry[kind]
            ancestor(ref['commit'],reviewed)
            path = EVIDENCE + f'acceptance/{gate}.{kind}.json'
            require(ref['path'] == path, 'unexpected evidence path')
            raw = blob(ref['commit'],path)
            require(sha(raw) == ref['sha256'], 'evidence digest mismatch')
            receipt = json.loads(raw)
            # Raw nonpublic artifacts remain in the private release workspace.
            # The independent reviewer checks how they map to the public projection.
            artifact = ref['artifactSHA256']
            require(hexdigest(artifact) and artifact == receipt['artifactSHA256']
                    and artifact not in raw_digests, 'reused or missing original capture')
            original = workspace/'acceptance'/'w0-originals'/artifact
            require(original.stat().st_size > 0 and sha(original.read_bytes()) == artifact, 'missing original bytes')
            raw_digests.add(artifact)
            receipts.append(receipt)
        verify_gate(gate,candidate,*receipts,seen)



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace',type=Path,help='original signed package workspace on macOS')
    args = parser.parse_args()
    result = {'integrationBase':WAIT}
    try:
        pull = api('pulls/119')
        main_sha = api('git/ref/heads/main')['object']['sha']
        result.update(main=main_sha,pr119Head=pull['head']['sha'],pr119Merged=pull['merged'])
        verify(json.loads((HERE/'107-admission.json').read_bytes()),pull,main_sha,args.workspace)
        api.cache_clear()
        fresh = api('pulls/119')
        require(api('git/ref/heads/main')['object']['sha'] == main_sha
                and fresh['head']['sha'] == pull['head']['sha'] and fresh['merge_commit_sha'] == pull['merge_commit_sha'],
                'remote ref changed during verification')
        result['integrationBase'] = 'REVIEW_MERGED_107_ACCEPTANCE'
    except Exception as error:
        result['reason'] = str(error)
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return 0 if result['integrationBase'] != WAIT else 1


if __name__ == '__main__':
    raise SystemExit(main())
