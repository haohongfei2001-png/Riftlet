"""Issue 120 W5. Replay evidence without converting a partial fixture to product acceptance."""
import argparse
import json
import re
from pathlib import Path
from fixtures import BROWSERS, HERE, JS, ROOT, SIM, SLICES, SUPPORT, WEB, sha, sources

PLAN = 'a18ef269b63d1682384531a155c425d856b37e5d'
PLAN_FILE = 'docs/plans/issue-120/compatibility-matrix.json'
PLAN_DIGEST = '35318faf7eacecf80972a7e47eaca173af15682f7ead047198e79da44cc30658'
# Reviewed receipt bytes at #122 4daab3f. Each receipt binds the matching TAP bytes.
REVIEWED_RECEIPTS = {
    'headless-chrome.json': '2b9a5c1275c19ed3ef6541228f718b4d64708630b6dbe8020d762ee01b8fb614',
    'headless-edge.json': '8edd3850d978ad539f2155cbe60c0850bf2b837b71b2fb83d7cf15be69a533d6',
    'simulation-chrome.json': '505709dc70edc06dc4a42364d13a32494d808dba537668fd1d4b3916a5fdfd08',
}
SHARED = 'T01 T02 T03 T04 I01 I02 I03 I04 E01 E02 E03 E04 E05 P01 P02 D01 R01 R02 X01'.split()
LEVELS = ('L1', 'L2', 'L3')


def need(ok, message):
    if not ok:
        raise ValueError(message)


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def read_json(data):
    return json.loads(data, object_pairs_hook=no_duplicates)


def plan():
    raw = (ROOT / PLAN_FILE).read_bytes()
    need(sha(raw) == PLAN_DIGEST, 'planning matrix digest mismatch')
    return read_json(raw)


def fixture_result(path):
    raw = path.read_bytes()
    rec = read_json(raw)
    reviewed = sha(raw) == REVIEWED_RECEIPTS.get(path.name)
    keys = {'schema', 'browser', 'provider', 'observedAt', 'platform', 'arch', 'sourceSHA',
            'candidate', 'versions', 'results', 'kind', 'inputs', 'exitCode', 'transcriptSHA256'}
    need(set(rec) == keys and rec['schema'] == 1 and rec['candidate'] is None, 'unexpected fixture schema/candidate')
    need(rec['provider'] == 'chatgpt' and rec['browser'] in BROWSERS, 'wrong fixture scope')
    need(type(rec['exitCode']) is int and rec['exitCode'] >= 0, 'missing exit code')
    need(all(isinstance(rec[k], str) and rec[k].strip() for k in ['observedAt', 'arch', 'platform']), 'missing environment')
    tap_bytes = path.with_suffix('.tap').read_bytes()
    need(rec['transcriptSHA256'] == sha(tap_bytes), 'transcript digest mismatch')
    tap = tap_bytes.decode()
    web = rec['kind'] == 'headless-web-only'
    if web:
        mode = 'headless'
        need(rec['versions'].get('bundle') == BROWSERS[rec['browser']][1] and
             re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', rec['versions'].get('browser', '')), 'wrong browser binary')
        files = [JS, WEB, SUPPORT + 'original-error-card-application.cjs', SUPPORT + 'attachment-entry-application.cjs',
                 SUPPORT + 'native-chrome-cleanup.cjs']
        expected = {'E04': 'original-failure-card'}
    else:
        mode = 'simulation'
        need(rec['kind'] == 'simulated-js' and rec['browser'] == 'chrome' and
             re.fullmatch(r'v[0-9]+(?:\.[0-9]+)+', rec['versions'].get('node', '')), 'wrong simulated target')
        files = [JS, SIM, SUPPORT + 'independent-input-fixture.cjs']
        expected = SLICES
    need(path.stem == mode + '-' + rec['browser'], 'wrong evidence filename/receiver')
    need(rec['inputs'] == sources(files), 'wrong fixture or adapter program bytes')
    need(re.fullmatch(r'[0-9a-f]{40}', rec['sourceSHA']), 'invalid program source')
    need(rec['sourceSHA'] == 'ef3f58cb7baf26ee3c0fd7c6b1db9d9d32ca21d0' and
         rec['inputs'][JS] == '50b0d16d10f38c688ce33189df55ad3da6588b4c7006b710777f30340dc55ed7',
         'different inherited program provenance')
    rows = rec['results']
    need(isinstance(rows, list) and len(rows) == len(expected) and
         {r['case'] for r in rows} == set(expected), 'missing, duplicate or extra test')
    total = len(expected)
    summary_ok = (not re.search(r'^(?:not ok |Bail out!)', tap, re.M)
                  and len(re.findall(r'^ok [0-9]+ - ', tap, re.M)) == total
                  and re.findall(r'^1\.\.(\d+)$', tap, re.M) == [str(total)]
                  and all(re.findall(r'^# ' + field + r' (\d+)$', tap, re.M) == [str(count)]
                          for field, count in (('tests', total), ('pass', total), ('fail', 0),
                                               ('skipped', 0), ('cancelled', 0), ('todo', 0))))
    replay = []
    for row in rows:
        case = row['case']
        need(row['test'] == expected[case] and type(row['passed']) is bool, 'wrong test or result type')
        if web:
            edge = 'true' if rec['browser'] == 'edge' else 'false'
            pattern = r'^ok \d+ - native Chrome independent append (\{.*\})$'
            matches = re.findall(pattern, tap, re.M)
            valid = len(matches) == 1 and read_json(matches[0]) == {
                'name': 'owned-original-failure-card', 'namedErrorCard': True, 'edge': edge == 'true',
                'count': 1, 'retained': True, 'route': 'https://chatgpt.com/'}
            counters = row.get('counters', {})
            observed = [read_json(v[2:]) for v in tap.splitlines() if v.startswith('# {')]
            valid = valid and observed == [counters] and counters.get('passed') is True and all(
                type(counters.get(k)) is int and counters[k] == n for k, n in {
                    'rejectedShapes': 23, 'retiredCases': 4, 'nativeSetters': 31, 'nativeChanges': 31, 'automaticSends': 0
                }.items())
        else:
            valid = len(re.findall(r'^ok \d+ - ' + re.escape(row['test']) + '$', tap, re.M)) == 1
        valid = bool(valid and rec['exitCode'] == 0 and summary_ok)
        need(valid == row['passed'], 'claimed result disagrees with raw transcript')
        replay.append(dict(case=case, scope=rec['kind'], status='PASS' if valid else 'FAIL',
                           evidence=path.name, reviewedReceipt=reviewed, transcriptSHA256=rec['transcriptSHA256']))
    return (rec['browser'], rec['provider']), replay


def render(directory):
    p = plan()
    index = {}
    files = sorted(directory.glob('*.json'))
    canonical = directory.resolve() == (HERE / 'evidence').resolve()
    if canonical:
        need({f.name for f in files} == REVIEWED_RECEIPTS.keys(), 'incomplete reviewed receipt set')
    for filename in files:
        cell, rows = fixture_result(filename)
        if canonical:
            need(all(row['reviewedReceipt'] for row in rows), 'canonical receipt differs from reviewed bytes')
        index.setdefault(cell, []).extend(rows)
    cells = []
    for item in p['cells']:
        key = item['browserID'], item['providerID']
        cells.append(dict(browser=key[0], provider=key[1], scope=item['scope'], bundle=item['bundleID'],
                          candidate=None, status={level: 'NOT_RUN' for level in LEVELS}, enabledForRelease=False,
                          slices=index.pop(key, [])))
    need(not index, 'evidence for unplanned combination')
    return dict(schema=1, planSHA=PLAN, planMatrixSHA256=PLAN_DIGEST, candidate=None,
                decision='WAITING_FOR_107_BASELINE', coreCells=p['coreCellCount'], coreLivePassed=0,
                defaultCaseResult={'status': 'NOT_RUN', 'reason': 'No complete next-cycle case on this level.'},
                requiredLiveCases=p['requiredLiveCases'], sharedCases=SHARED, conditionalHosts=p['conditionalHosts'],
                cells=cells)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package-workspace', type=Path, help='signed release workspace used with --formal-evidence')
    parser.add_argument('--formal-evidence', type=Path,
                        help='directory of content-addressed raw evidence; index comes from reviewed GitHub #122')
    parser.add_argument('--fixtures', type=Path, default=HERE / 'evidence')
    parser.add_argument('--case', choices=list(dict.fromkeys(plan()['requiredLiveCases'] + SHARED + ['service-recovery'])))
    parser.add_argument('--level', choices=LEVELS)
    parser.add_argument('--browser')
    parser.add_argument('--provider')
    args = parser.parse_args()
    result = render(args.fixtures)
    if bool(args.formal_evidence) != bool(args.package_workspace):
        parser.error('supply --formal-evidence and --package-workspace together')
    if args.formal_evidence:
        from formal_results import apply_index, remote_index, verify_signed_candidate
        index, admission = remote_index()
        verify_signed_candidate(args.package_workspace, index['candidate'])
        result = apply_index(result, index, args.formal_evidence)
        result['acceptanceAdmission'] = admission
    if args.case or args.level or args.browser or args.provider:
        rows = []
        cases = [args.case] if args.case else list(dict.fromkeys(result['requiredLiveCases'] + SHARED + (['service-recovery'] if result['candidate'] else [])))
        for cell in result['cells']:
            if args.browser and args.browser != cell['browser'] or args.provider and args.provider != cell['provider']:
                continue
            for case in cases:
                for level in ([args.level] if args.level else LEVELS):
                    if cell.get('variants'):
                        for variant in cell['variants']:
                            facts = {k:v for k,v in variant['cases'][level].items() if k.split('/')[-1] == case}
                            from formal_results import summarize
                            rows.append(dict(browser=cell['browser'],provider=cell['provider'],case=case,level=level,
                                             scope=variant['scope'], status=summarize(list(facts.values())) if facts else 'NOT_RUN',
                                             details=facts, candidate=result['candidate']))
                        continue
                    rows.append(dict(browser=cell['browser'], provider=cell['provider'], case=case, level=level,
                                     **result['defaultCaseResult'], candidate=result['candidate'],
                                     slices=[s for s in cell['slices'] if s['case'] == case and
                                             level == 'L1' and s['scope'] == 'simulated-js']))
        need(rows, 'unplanned matrix selection')
        result = rows
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
