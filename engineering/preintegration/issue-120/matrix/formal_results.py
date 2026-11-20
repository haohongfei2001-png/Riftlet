"""Apply independently admitted #120 evidence to the planning matrix. No product writes."""
import base64
import importlib.util
import json
import plistlib
import tempfile
from pathlib import Path
import subprocess

from fixtures import ROOT, sha
from matrix import need, read_json
from native_evidence import CASES, audit_batch, check_package, digest, nonempty

REPO = 'haohongfei2001-png/Riftlet'
INDEX = 'engineering/preintegration/issue-120/matrix/acceptance-index.json'
ADMISSION = 'engineering/mainline/source-admission.json'
HOST = ('browser', 'bundle', 'browserVersion', 'arch', 'macOS')
PROVIDER = ('provider', 'providerRevision', 'programSHA256', 'surface', 'mode', 'locale', 'accountTier')
VARIANT = HOST + PROVIDER
# Minimum coverage from #121 ACCEPTANCE sections 4, 5, 9 and the final delivery request.
REQUIRED = {
    ('global', 'L1'): 'T04 I01 I02 E05 R01 X01'.split(),
    ('provider', 'L1'): 'I03 E01 E03'.split(),
    ('host', 'L2'): 'T01 T02 T04 I01 P01'.split(),
    ('provider', 'L2'): 'T03 I03 I04 E01 E02 E03 E04 P02 D01'.split(),
    ('global', 'L2'): 'I02 E05 R01 R02 X01'.split(),
    ('cell', 'L3'): ['service-recovery'],
    ('global', 'release'): ['package-and-upgrade', 'source-and-CI', 'performance'],
}
HOST_GATES = {'safari':['cold-locator-and-execution-world'], 'brave':['default-shields-and-execution-world']}
NONPASS = {'FAIL', 'BLOCKED_ENV', 'BLOCKED_TECHNICAL', 'UNKNOWN'}
SCOPE = {'global': (), 'host': HOST, 'provider': PROVIDER, 'cell': VARIANT}


def api(path):
    return read_json(subprocess.check_output(['gh','api','--hostname','github.com',f'repos/{REPO}/{path}'],
                                             timeout=45))


def blob(ref, path):
    result = api(f'contents/{path}?ref={ref}')
    need(result.get('path') == path and result.get('type') == 'file' and
         result.get('encoding') == 'base64', 'wrong GitHub blob')
    return base64.b64decode(result['content'].replace('\n',''), validate=True)


def product_binding(pr, candidate, reviewed):
    upstream = api('pulls/119')
    merge = upstream['merge_commit_sha']
    source = candidate['sourceSHA']
    need(upstream['merged'] is True and merge and source != merge, 'final 1.0.7 not inherited')
    for older, newer in ((merge,pr['base']['sha']), (merge,source), (source,reviewed)):
        need(api(f'compare/{older}...{newer}')['merge_base_commit']['sha'] == older, 'wrong product ancestry')
    old = plistlib.loads(blob(merge,'Resources/Info.plist'))['CFBundleVersion']
    actual = plistlib.loads(blob(source,'Resources/Info.plist'))['CFBundleVersion']
    need(actual == candidate['build'] and int(actual) > int(old), 'not a new-cycle source and build')
    def product_files(commit):
        tree = api('git/trees/'+commit+'?recursive=1')
        need(tree['truncated'] is False, 'incomplete product tree')
        return {(row['path'],row['mode'],row['sha']) for row in tree['tree'] if row['type'] != 'tree'
                and not row['path'].startswith(('docs/', 'engineering/evidence/', INDEX.rsplit('/',1)[0]+'/accepted/'))
                and row['path'] not in (INDEX, ADMISSION)}
    need(product_files(source) == product_files(reviewed), 'candidate differs from reviewed product')
    return merge


def remote_index():
    """The local workspace and receipt directory have no authority to select a candidate."""
    pr = api('pulls/122')
    need(pr['base']['ref'] == 'main' and pr['head']['repo']['full_name'] == REPO,
         'formal #122 integration baseline missing')
    need(pr['base']['repo']['full_name'] == REPO and api('compare/'+pr['base']['sha']+'...main')['merge_base_commit']['sha'] ==
         pr['base']['sha'], 'PR base outside actual main')
    head = pr['head']['sha']
    h = api('commits/'+head)
    need(len(h['parents']) == 1 and [(f['filename'], f['status']) for f in h['files']] ==
         [(ADMISSION, 'modified')], 'missing admission-only child on formal #122')
    reviewed = h['parents'][0]['sha']
    tree = api('commits/'+reviewed)['commit']['tree']['sha']
    pin = read_json(blob(head, ADMISSION))
    raw = blob(reviewed, INDEX)
    index = read_json(raw)
    candidate = index['candidate']
    check_package(candidate)
    merge = product_binding(pr, candidate, reviewed)
    need(pin['reviewedSource'] == reviewed and pin['reviewedTree'] == tree, 'admission points elsewhere')
    for entry in pin['reviews']:
        report = read_json(entry['report'])
        if (sha(entry['report'].encode()) == entry['sha256'] and
                entry['source'] == report['reviewedSource'] == reviewed and
                entry['tree'] == report['reviewedTree'] == tree and
                entry['result'] == report['result'] == 'PASS' and report['findings'] == [] and
                report['reviewedBase'] == pin['reviewedBase'] and
                nonempty(entry['reviewer']) and nonempty(pin['authorRole']) and
                entry['reviewer'] == report['reviewer'] and
                entry['reviewer'].strip().casefold() != pin['authorRole'].strip().casefold() and
                report.get('issue120SignedCandidate') == candidate and
                report.get('issue120Verified107Merge') == merge and
                report.get('issue120AcceptanceIndexSHA256') == sha(raw)):
            return index, {'pr':122,'admissionSHA':head,'reviewSHA':reviewed,'indexSHA256':sha(raw)}
    raise ValueError('no independent #120 admission of this candidate and evidence index')


def verify_signed_candidate(workspace, candidate):
    """Reuse the release verifier against both actual installable bytes and expanded App."""
    spec = importlib.util.spec_from_file_location('riftlet_matrix_dmg',ROOT/'scripts/release-dmg.py')
    dmg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dmg)
    team = 'ZB9D4T66QB'
    receipt = read_json((workspace/'formal-dmg/dmg-receipt.json').read_bytes())
    need(digest(receipt['manifestSHA256']), 'invalid package manifest pin')
    manifest = dmg.R.verify_package(workspace/'Riftlet-Release', receipt['manifestSHA256'], team)
    files = {p.removeprefix('Riftlet.app/'):v for p,v in manifest['files'].items() if p.startswith('Riftlet.app/')}
    app = sha(json.dumps(files,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode())
    build = manifest['build']
    dmg.R.verify_accepted_app_log(workspace, manifest)
    suffix = '' if build.get('distributionChannel') == 'stable' else f"-{build['build']}-universal"
    name = f"Riftlet-{build['version']}{suffix}.dmg"
    need(name == Path(name).name and receipt['archive'] == name and manifest['stage'] == 'STAPLED' and
         receipt['stage'] == 'VERIFIED_STAPLED_DMG' and receipt['notaryStatus'] == 'Accepted' and
         receipt['teamID'] == team and receipt['appSubmissionID'] == manifest['notarization']['submissionID'] and
         receipt['version'] == build['version'] and receipt['build'] == build['build'] and build['source']['commit'] == receipt['source'] == candidate['sourceSHA'] and
         build['build'] == candidate['build'] and set(build['architectures']) == {'arm64','x86_64'} and
         files and app == candidate['appSHA256'], 'different signed App, build or source')
    image = workspace/'formal-dmg'/name
    need(dmg.R.digest(image) == receipt['finalSHA256'] == candidate['dmgSHA256'], 'different signed DMG')
    with tempfile.TemporaryDirectory(prefix='riftlet-w5-package-') as tmp:
        logs = Path(tmp).resolve()
        dmg.ticket(image, logs/'ticket.log')
        dmg.image_signature(image,team,logs)
        dmg.assess(image,'open',logs)
        dmg.inspect_image(image,manifest,logs)
    need(dmg.R.digest(image) == candidate['dmgSHA256'], 'package changed during verification')


def summarize(statuses):
    for status in ('FAIL','BLOCKED_TECHNICAL','BLOCKED_ENV','UNKNOWN'):
        if status in statuses:
            return status
    if all(s == 'PASS' for s in statuses):
        return 'PASS'
    return 'NOT_RUN' if all(s == 'NOT_RUN' for s in statuses) else 'PARTIAL'


def apply_index(matrix, index, directory):
    """Input must already be independently admitted. Called directly only in unit tests."""
    need(set(index) == {'schema','candidate','runs','observations'} and type(index['schema']) is int
         and index['schema'] == 1, 'invalid reviewed index')
    candidate = index['candidate']
    check_package(candidate)
    # The expected digest is the only possible filename; recompute over the actual local bytes.
    used = set()
    def read(d):
        need(digest(d) and d not in used, 'invalid or reused raw evidence')
        used.add(d)
        data = (directory / d).read_bytes()
        need(data and sha(data) == d, 'raw evidence digest mismatch')
        return data

    need(isinstance(index['runs'], list) and isinstance(index['observations'], list), 'invalid evidence lists')
    cells = {(c['browser'], c['provider']): c for c in matrix['cells']}
    variants = set()
    def key(scope, fields):
        need(all(nonempty(scope.get(k)) for k in fields if k != 'providerRevision'), 'invalid scope')
        if 'provider' in fields:
            need(scope['provider'] in {p for _,p in cells} and scope['surface'] == 'ordinary-chat' and
                 digest(scope['programSHA256']) and type(scope.get('providerRevision')) is int and scope['providerRevision'] > 0,
                 'invalid provider scope')
        if 'browser' in fields:
            need(any(c['browser'] == scope['browser'] and c['bundle'] == scope['bundle'] for c in cells.values()),
                 'invalid browser scope')
        ident = tuple(scope[k] for k in fields)
        if fields == VARIANT:
            need((scope['browser'],scope['provider']) in cells, 'unplanned cell')
            variants.add(ident)
        return ident

    cases = {}
    samples = []
    native_cards = {}
    for ref in index['runs']:
        need(set(ref) == {'run','oracle'}, 'invalid run link')
        run, raw = read_json(read(ref['run'])), read(ref['oracle'])
        samples.append((run, raw))
        scope = run['scope']
        ident = key(scope, VARIANT)
        outcome = 'PASS'
        for op in run['operations']:
            if op['inputEntered'] is None or (op['inputEntered'] == 1 and
                    any(v is None for v in op['timingsMs'].values())):
                outcome = 'UNKNOWN'
        observed = {row['operation']:row for row in read_json(raw)['operations']}
        for op in run['operations']:
            row = observed.get(op['operation'], {})
            native_cards[op['operation']] = (ident, scope['level'], op['targetSHA256'],
                                              op['originalSHA256'], row.get('newCardSHA256'))
        cases.setdefault((ident,scope['level'],scope['case']), []).append(outcome)
    if samples:
        audit_batch(candidate, samples)

    card_operations = {info[-1]:operation for operation,info in native_cards.items() if info[-1]}
    gates = {}
    recovery_ids = set()
    for d in index['observations']:
        r = read_json(read(d))
        need(set(r) == {'candidate','kind','scope','level','case','status','productRaw','observerRaw'} and
             r['candidate'] == candidate, 'different package or missing external observation')
        kind, scope, level, case, status = (r[k] for k in ('kind','scope','level','case','status'))
        need(kind in SCOPE and set(scope) == set(SCOPE[kind]), 'wrong observation scope')
        ident = key(scope, SCOPE[kind])
        # Raw sources are independently audited by the signer of the index. Summaries alone
        # never establish paired-case PASS, even when they come from an admitted reviewer.
        actors, outcomes, recoveries = set(), [], []
        for field, role in (('productRaw','product'),('observerRaw','independent')):
            envelope = read_json(read(r[field]))
            need(all(envelope.get(k) == r[k] for k in ('candidate','scope','kind','level','case')) and
                 envelope.get('role') == role and nonempty(envelope.get('actor')) and
                 envelope.get('status') in NONPASS | {'PASS'}, 'cross-scope or missing independent raw record')
            actors.add(envelope['actor'].strip().casefold())
            outcomes.append(envelope['status'])
            read(envelope['artifactSHA256'])
            if kind == 'cell' and case == 'service-recovery' and status == 'PASS':
                proof = envelope.get('recovery', {})
                need(all(digest(proof.get(k)) for k in ('operation','target','original','acceptedCard')) and
                     proof.get('failedCard') == proof['acceptedCard'] and proof.get('restoredImage') == proof['original']
                     and proof.get('originalCardServiceFailure') is True and proof.get('availableForNewClick') is True and
                     proof.get('serviceReady') is False and type(proof.get('automaticInputsAfterFailure')) is int and
                     proof['automaticInputsAfterFailure'] == 0, 'missing original card failure or restored image evidence')
                recoveries.append(proof)
        need(len(actors) == 2 and status == summarize(outcomes), 'unsubstantiated reviewed outcome')
        if recoveries:
            proof = recoveries[0]
            need(len(recoveries) == 2 and recoveries[1] == proof, 'different recovery observations')
            related = (ident,level,proof['target'],proof['original'],proof['acceptedCard'])
            need(native_cards.get(proof['operation'], related) == related and
                 card_operations.get(proof['acceptedCard'],proof['operation']) == proof['operation'],
                 'recovery belongs to different native operation')
            for token in (('op',proof['operation']),('card',proof['acceptedCard'])):
                need(token not in recovery_ids, 'reused recovery evidence')
                recovery_ids.add(token)
        if kind == 'cell' and case in CASES:
            need(level in ('L2','L3') and status in NONPASS, 'native PASS requires matched original receipts')
            cases.setdefault((ident,level,case), []).append(status)
        else:
            need((case in REQUIRED.get((kind,level), []) or
                  (kind == 'host' and level == 'L2' and case in HOST_GATES.get(scope['browser'], []))) and status in NONPASS | {'PASS'}, 'unplanned gate or result')
            gates.setdefault((ident,level,case), []).append(status)

    for ident in sorted(variants):
        v = dict(zip(VARIANT,ident))
        cell = cells[(v['browser'],v['provider'])]
        statuses = {}
        by_case = {}
        for level in ('L1','L2','L3','release'):
            evidence = {}
            # Full signed isolated and authenticated native functional coverage are distinct.
            if level in ('L2','L3'):
                required_cases = CASES if level == 'L3' else ('F01',)
                available_cases = [case for case in CASES if (ident,level,case) in cases]
                for case in dict.fromkeys((*required_cases,*available_cases)):
                    evidence[case] = summarize(cases.get((ident,level,case), ['NOT_RUN']))
            for (kind,required_level), names in REQUIRED.items():
                if required_level != level:
                    continue
                projection = tuple(v[k] for k in SCOPE[kind])
                for name in names:
                    evidence[kind+'/'+name] = summarize(gates.get((projection,level,name), ['NOT_RUN']))
            if level == 'L2':
                host_key = tuple(v[k] for k in HOST)
                for name in HOST_GATES.get(v['browser'], []):
                    evidence['host/'+name] = summarize(gates.get((host_key,level,name), ['NOT_RUN']))
            by_case[level] = evidence
            statuses[level] = summarize(list(evidence.values()))
        variant = {'scope':v, 'status':statuses, 'cases':by_case,
                   'eligibleForReleaseReview':all(s == 'PASS' for s in statuses.values())}
        cell.setdefault('variants', []).append(variant)

    for cell in cells.values():
        cell['candidate'] = candidate
        profiles = cell.get('variants', [])
        for level in ('L1','L2','L3'):
            if profiles:
                cell['status'][level] = summarize([p['status'][level] for p in profiles])
        cell['eligibleForReleaseReview'] = bool(profiles) and all(p['eligibleForReleaseReview'] for p in profiles)
    matrix['releaseAuthorization'] = 'REQUIRES_SEPARATE_W0_AND_W8_VERIFICATION'
    matrix['sharedEvidence'] = [
        {'scope':list(projection),'level':level,'case':case,'status':summarize(statuses)}
        for (projection,level,case), statuses in sorted(gates.items(), key=lambda item: repr(item[0]))
    ]
    matrix['candidate'] = candidate
    matrix['coreLivePassed'] = sum(c['status']['L3'] == 'PASS' for c in cells.values() if c['scope'] == 'core')
    matrix['decision'] = ('READY_FOR_RELEASE_REVIEW' if all(c['eligibleForReleaseReview'] for c in cells.values()
                                                           if c['scope'] == 'core') else 'PARTIAL')
    return matrix
