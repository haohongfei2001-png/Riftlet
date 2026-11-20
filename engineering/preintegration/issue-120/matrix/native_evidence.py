"""Read-only cross-check of externally collected native observations. Never launches an App or promotes a cell."""
import argparse
import json
import math
import re
from pathlib import Path
from matrix import need, plan, read_json, sha

HEX = re.compile(r'[0-9a-f]{64}')
CASES = ('F01', 'F02', 'F03', 'F04', 'F05', 'F06', 'T01')
IDENTITY = {'sourceSHA', 'appSHA256', 'dmgSHA256', 'build'}


def digest(value):
    return isinstance(value, str) and HEX.fullmatch(value) is not None


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def integer(value):
    return type(value) is int and value >= 0


def check_package(candidate):
    need(isinstance(candidate, dict) and set(candidate) == IDENTITY
         and re.fullmatch(r'[0-9a-f]{40}', candidate.get('sourceSHA', ''))
         and digest(candidate['appSHA256']) and digest(candidate['dmgSHA256'])
         and re.fullmatch(r'[1-9][0-9]*', candidate['build']), 'missing exact package identity')


def audit(candidate, run, oracle_bytes):
    check_package(candidate)
    oracle = read_json(oracle_bytes)
    need(run.get('schema') == oracle.get('schema') == 1 and run.get('candidate') == oracle.get('candidate') == candidate,
         'different or missing candidate')
    need(run.get('oracleSHA256') == sha(oracle_bytes), 'unlinked independent observation')
    need(run.get('collector') == 'riftlet-native' and oracle.get('collector') == 'independent-ui-observer'
         and nonempty(run.get('operator')) and nonempty(oracle.get('reviewer'))
         and run['operator'] != oracle['reviewer'], 'distinct native and independent evidence required')
    scope = run.get('scope')
    need(isinstance(scope, dict) and scope == oracle.get('scope'), 'cross-scope oracle')
    keys = {'level','case','browser','bundle','browserVersion','provider','providerRevision','programSHA256',
            'surface','mode','locale','accountTier','macOS','arch','profileKind','composition','runID'}
    need(set(scope) == keys and all(nonempty(scope[k]) for k in keys - {'providerRevision'}),
         'incomplete evidence scope')
    need(digest(scope['programSHA256']) and integer(scope['providerRevision']) and scope['providerRevision'] > 0,
         'invalid provider profile')
    need(any(c['browserID'] == scope['browser'] and c['bundleID'] == scope['bundle'] and
             c['providerID'] == scope['provider'] for c in plan()['cells']), 'unplanned host/provider')
    need(scope['case'] in CASES and scope['surface'] == 'ordinary-chat', 'unsupported case or surface')
    modes = {'L2': ('signed-isolated-fixture','acceptance-fixture'), 'L3': ('ordinary-signed-app','authenticated-test-session')}
    need(scope['level'] in modes and (scope['composition'], scope['profileKind']) == modes[scope['level']],
         'wrong native level, composition or profile')
    rejected = run.get('preIntentRefusals', [])
    refused_ui = oracle.get('preIntentRefusals', [])
    need(isinstance(rejected, list) and isinstance(refused_ui, list) and len(rejected) == len(refused_ui),
         'unmatched pre-intent refusals')
    if rejected:
        need(scope['case'] == 'T01', 'refusal cannot prove a positive case')
        clicks = {}
        for witness in rejected:
            key = witness.get('clickSHA256')
            need(set(witness) == {'clickSHA256','targetSHA256','originalSHA256','inputEntered','outcome'}
                 and all(digest(witness[k]) for k in ('clickSHA256','targetSHA256','originalSHA256'))
                 and key not in clicks and integer(witness['inputEntered']) and witness['inputEntered'] == 0
                 and witness['outcome'] == 'refused-before-intent', 'invalid pre-intent native click witness')
            clicks[key] = witness
        for witness in refused_ui:
            original = clicks.pop(witness.get('clickSHA256'), None)
            need(original is not None and
                 set(witness) == {'clickSHA256','targetSHA256','originalSHA256','addedMatchingCards','changedOtherTargets',
                                  'automaticSends','switchedSameURLTarget','trayRetained','priorDraftPreserved'}
                 and all(witness[k] == original[k] for k in ('originalSHA256','targetSHA256'))
                 and all(witness[k] is True for k in ('switchedSameURLTarget','trayRetained','priorDraftPreserved'))
                 and all(integer(witness[k]) and witness[k] == 0 for k in
                         ('addedMatchingCards','changedOtherTargets','automaticSends')), 'unproven pre-intent refusal')
    expected, observed = run.get('operations'), oracle.get('operations')
    need(isinstance(expected, list) and isinstance(observed, list) and (expected or rejected) and len(expected) == len(observed),
         'empty or mismatched operation evidence')
    ids = set()
    opmap = {}
    for op in expected:
        label = op.get('operation')
        need(digest(label) and label not in ids, 'missing or duplicate native operation')
        ids.add(label)
        need(all(digest(op.get(k)) for k in ('originalSHA256','payloadSHA256','targetSHA256','invocationSHA256')),
             'unbound native asset, target or invocation')
        times = op.get('timingsMs')
        need(isinstance(times, dict) and set(times) == {'clickToBound','clickToInput','clickToPositive','positiveToHidden'}
             and all(v is None or number(v) for v in times.values()), 'unknown timing must be explicit null')
        # Compare measured event times on a single native monotonic timeline.
        # A missing milestone stays unknown; never infer it from a later one.
        ordered = [times[k] for k in ('clickToBound', 'clickToInput', 'clickToPositive') if times[k] is not None]
        need(ordered == sorted(ordered), 'native milestone times out of order')
        need(number(op.get('clickMs')) and 'inputEntered' in op and
             ((integer(op['inputEntered']) and op['inputEntered'] <= 1) or
              (scope['level'] == 'L3' and op['inputEntered'] is None)),
             'missing click or repeated input')
        opmap[label] = op
    need(len({v['invocationSHA256'] for v in expected}) == len(ids), 'replayed invocation')
    seen = set()
    for row in observed:
        label = row.get('operation')
        need(label in ids and label not in seen, 'duplicate/unrelated oracle operation')
        seen.add(label)
        op = opmap[label]
        need(op['targetSHA256'] == row.get('targetSHA256') and op['originalSHA256'] == row.get('originalSHA256'),
             'independent oracle saw a different target or image')
        for field in ('automaticSends','changedOtherTargets','extraInputs','addedMatchingCards'):
            need(integer(row.get(field)), 'missing independent count: ' + field)
        need(all(row[k] == 0 for k in ('automaticSends','changedOtherTargets','extraInputs')), 'unsafe observed outcome')
        need(all(row.get(k) is True for k in ('priorTextPreserved','selectionPreserved','priorAttachmentsPreserved')),
             'missing draft preservation')
        need(row.get('processing') in ('unknown','ready','failed') and row.get('handoff') in ('accepted','refused'),
             'separate processing and handoff outcomes required')
        if scope['case'] == 'T01':
            need(row.get('switchedSameURLTarget') is True, 'target switch unobserved')
        if scope['case'] == 'T01' and row['handoff'] == 'refused':
            need(op['inputEntered'] == row['addedMatchingCards'] == 0 and row.get('trayRetained') is True
                 and row['processing'] == 'unknown' and row.get('observedOriginalCard') is not True
                 and all(op['timingsMs'][k] is None for k in ('clickToInput','clickToPositive','positiveToHidden')),
                 'unsafe target refusal')
        else:
            need(row['handoff'] == 'accepted' and op['inputEntered'] in (1, None) and row['addedMatchingCards'] == 1 and
                 row.get('observedOriginalCard') is True, 'missing original card/one input')
    case = scope['case']
    if case == 'F01':
        need(any(r.get('coldUnprepared') is True and r.get('nonemptySelection') is True
                 and r.get('hadPriorAttachment') is True and r.get('hadPriorText') is True
                 for r in observed), 'missing cold draft preconditions')
    elif case == 'F02':
        need(any(r.get('warmDraft') is True and r.get('hadPriorAttachment') is True for r in observed), 'missing warm draft')
    elif case == 'F03':
        pairs = run.get('pairs')
        need(isinstance(pairs, list) and len(pairs) >= 3, 'at least three actual pairs required')
        groups, gaps = set(), []
        for pair in pairs:
            need(isinstance(pair, list) and len(pair) == 2 and all(k in ids for k in pair)
                 and len(set(pair)) == 2 and groups.isdisjoint(pair), 'unrelated/reused pair')
            a, b = (opmap[k] for k in pair)
            need(a['targetSHA256'] == b['targetSHA256'] and a['originalSHA256'] != b['originalSHA256'], 'pair mismatch')
            gap = b['clickMs'] - a['clickMs']
            need(0 < gap < 2000, 'actual click interval outside contract')
            groups.update(pair)
            gaps.append(gap)
        need(groups == ids and len({o['originalSHA256'] for o in expected}) == len(ids)
             and any(350 <= g <= 650 for g in gaps) and any(1500 <= g <= 1900 for g in gaps),
             'missing distinct files, ~0.5 s or ~1.7 s coverage')
    elif case == 'F04':
        need({'new','saved'} <= {r.get('draftKind') for r in observed}, 'new and saved drafts required')
    elif case == 'F05':
        need(any(r.get('richSelectionObserved') is True for r in observed) and
             any(r.get('concurrentEditPreserved') is True for r in observed), 'concurrent edit or rich selection missing')
    elif case == 'F06':
        witness = [opmap[r['operation']] for r in observed if r.get('explicitNewClick') is True]
        need(any(a['operation'] != b['operation'] and a['originalSHA256'] == b['originalSHA256'] and
                 a['targetSHA256'] == b['targetSHA256'] and a['clickMs'] < b['clickMs'] and
                 number(a['timingsMs']['clickToPositive']) and
                 a['clickMs'] + a['timingsMs']['clickToPositive'] < b['clickMs'] for a in witness for b in witness),
             'missing later explicit click after positive handoff of identical file')
    return 'MATCHED_RECORD_ONLY'


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    for k in ['candidate','run','oracle']:
        p.add_argument(k, type=Path)
    args = p.parse_args()
    print(audit(read_json(args.candidate.read_bytes()), read_json(args.run.read_bytes()), args.oracle.read_bytes()))
