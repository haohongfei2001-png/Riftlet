"""Verify the measurements in independent, immutable 1.0.7 acceptance receipts."""
import hashlib
import json
import math
import re


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def hexdigest(value, length=64):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{%d}' % length, value) is not None


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def count(value):
    return type(value) is int and value >= 0


def time_ms(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def zero(row, keys):
    require(all(count(row.get(k)) and row[k] == 0 for k in keys), 'unsafe or unmeasured side effect')


def positive(row):
    times = [row[k] for k in ('clickedMs', 'boundMs', 'inputMs', 'acceptedMs', 'hiddenMs')]
    require(all(time_ms(v) for v in times) and times == sorted(times), 'missing or reversed milestone')
    require(count(row['inputs']) and row['inputs'] == 1 and count(row['newOriginalCards'])
            and row['newOriginalCards'] == 1 and hexdigest(row['payload']) and row['payload'] == row['observedPayload']
            and hexdigest(row['newCard']), 'original card or payload/input count')
    for k in ('originalPNG', 'operation', 'invocation', 'target', 'draftBefore', 'draftAfter',
              'selectionBefore', 'selectionAfter', 'attachmentsBefore', 'retainedAttachments'):
        require(hexdigest(row[k]), 'missing measured identity ' + k)
    require(row['draftBefore'] == row['draftAfter'] and row['selectionBefore'] == row['selectionAfter']
            and row['attachmentsBefore'] == row['retainedAttachments']
            and count(row['priorAttachmentCount']) and row['priorAttachmentCount'] > 0
            and count(row['selectedLength']) and row['selectedLength'] > 0, 'draft changed or empty control')
    zero(row, ('sends', 'foreignWrites', 'automaticRetries'))


def browser_gate(rows, gate, seen):
    cases = {row['case']: row for row in rows}
    require({'cold','warm'} <= cases.keys() and len(rows) == len(cases), 'missing cold/warm or duplicate sample')
    pairs = {}
    for name in cases.keys() - {'cold','warm'}:
        match = re.fullmatch(r'pair([1-9][0-9]*)([ab])',name)
        if match:
            pairs.setdefault(match[1],set()).add(match[2])
        else:
            require(re.fullmatch(r'extra[1-9][0-9]*',name), 'unknown browser sample')
    require(len(pairs) >= 3 and all(sides == {'a','b'} for sides in pairs.values()), 'incomplete pair samples')
    for row in rows:
        positive(row)
        require(row['browser'] == ('Chrome' if gate == 'G1' else 'Edge')
                and row['site'] == 'chatgpt.com' and row['authenticated'] is True
                and row['ordinaryApp'] is True and hexdigest(row['session']), 'wrong browser, site or session')
        require(row['draftKind'] in ('temporary', 'saved', 'new'), 'draft kind')
        if gate == 'G2':
            require(row['defaultProfile'] is True, 'not default Edge')
        for field in ('operation', 'invocation', 'originalPNG', 'newCard'):
            value = row[field]
            require(value not in seen[field], 'reused ' + field)
            seen[field].add(value)
    require(cases['cold']['preparedBeforeLaunch'] is False and cases['cold']['alreadyRunning'] is False
            and cases['warm']['alreadyRunning'] is True,
            'missing cold/warm proof')
    if gate == 'G2':
        require({'temporary','saved'} <= {r['draftKind'] for r in rows}, 'missing Edge draft type')
    for i in pairs:
        a, b = (cases[f'pair{i}{suffix}'] for suffix in 'ab')
        require(a['session'] == b['session'] and a['target'] == b['target']
                and a['draftKind'] == b['draftKind'] and 0 < b['clickedMs'] - a['clickedMs'] < 2000
                and not any(a['clickedMs'] <= r['clickedMs'] <= b['clickedMs'] for r in rows
                            if r not in (a,b) and r['session'] == a['session']), 'pair timing/identity')
    if gate == 'G2':
        require(not ({r['target'] for r in rows if r['draftKind']=='saved'} &
                     {r['target'] for r in rows if r['draftKind']=='temporary'}), 'relabelled Edge draft')


SAFE_TARGETS = {'foreground', 'tab', 'navigation', 'draft', 'windows', 'instances', 'controller',
                'permissionDenied', 'permissionRestored', 'jsOff'}
FAILURES = {'beforeInput', 'inputNoStart', 'startThenOriginalFailed', 'redraw', 'restartLostReply',
            'restoreOriginal', 'explicitRetry', 'preservedUnknown', 'localStorage'}


def gate_details(gate, rows, seen):
    if gate in ('G1', 'G2'):
        browser_gate(rows, gate, seen)
        return
    for row in rows:
        zero(row, ('sends','foreignWrites','automaticRetries'))
    if gate == 'G3':
        require({(r['browser'],r['case']) for r in rows} ==
                {(b,c) for b in ('Chrome','Edge') for c in SAFE_TARGETS}, 'missing target counterexample')
        for r in rows:
            zero(r, ('wrongTargetInputs','extraInputs','duplicateCards','draftMutations'))
            require(r['observedTransition'] is True, 'unobserved safety control')
        return
    cases = {row['case']:row for row in rows}
    require(len(cases) == len(rows), 'duplicate scenario')
    if gate == 'G4':
        require(set(cases) == FAILURES, 'missing failure/recovery')
        for row in rows:
            if row['case'] == 'localStorage':
                continue
            require(row['authenticated'] is True and row['site'] == 'chatgpt.com'
                    and row['ordinaryApp'] is True and hexdigest(row['target']), 'not a real failure session')
        pre, unstarted, failed = (cases[k] for k in ('beforeInput','inputNoStart','startThenOriginalFailed'))
        require(pre['inputs'] == 0 and pre['starts'] == 0 and pre['retained'] is True
                and unstarted['inputs'] == 1 and unstarted['starts'] == 0 and unstarted['ready'] is False,
                'false input or START')
        require(failed['starts'] == 1 and failed['inputs'] == 1 and hexdigest(failed['invocation'])
                and hexdigest(failed['newCard']) and failed['newCard'] == failed['failedCard']
                and failed['sameCardServiceFailure'] is True
                and failed['ready'] is False and hexdigest(failed['operation']), 'unconfirmed original failure')
        for key in ('redraw','restartLostReply','restoreOriginal','explicitRetry','preservedUnknown'):
            require(cases[key]['target'] == failed['target'], 'changed recovery draft')
        for key in ('redraw','restartLostReply','restoreOriginal'):
            require(cases[key]['operation'] == failed['operation'] and cases[key]['invocation'] == failed['invocation']
                    and cases[key]['inputs'] == 0,
                    'replayed or substituted recovery')
        require(cases['redraw']['sameCardObserved'] is True and cases['restartLostReply']['readOnly'] is True
                and hexdigest(failed['originalPNG']) and failed['originalPNG'] == cases['restoreOriginal']['restoredPNG'],
                'unverified restart or restored bytes')
        retry = cases['explicitRetry']
        require(retry['manualClick'] is True and hexdigest(retry['operation']) and retry['operation'] != failed['operation']
                and retry['originalPNG'] == failed['originalPNG'] and retry['inputs'] == 1
                and hexdigest(retry['invocation']) and retry['invocation'] != failed['invocation']
                and hexdigest(retry['newCard']) and retry['newCard'] != failed['newCard']
                and hexdigest(retry['payload']) and retry['observedPayload'] == retry['payload'] and retry['newOriginalCards'] == 1 and retry['starts'] == 1, 'failed manual recovery')
        for subject in (failed,retry):
            for field in ('operation','invocation','newCard'):
                require(subject[field] not in seen[field], 'reused recovery '+field)
                seen[field].add(subject[field])
        local = cases['localStorage']
        require(local['quickCheck'] == 'ok' and local['trashRestoredCount'] > 0
                and hexdigest(local['originalMediaInventory']) and local['originalMediaInventory'] == local['restoredMediaInventory']
                and local['historyPreserved'] is True and local['capturedPNGIngested'] is True, 'missing local recovery')
        old = cases['preservedUnknown']
        require(hexdigest(old['operation']) and old['operation'] != retry['operation']
                and hexdigest(unstarted['operation']) and old['operation'] == unstarted['operation']
                and old['operation'] == old['priorUnknownOperation'] and old['state'] == 'UNKNOWN'
                and old['afterRetryOperation'] == retry['operation'], 'old UNKNOWN rewritten')
    elif gate == 'G5':
        require(set(cases) == {'en-light','en-dark','zh-light','zh-dark','library','capture'}, 'missing G5 sample')
        views = ('en-light','en-dark','zh-light','zh-dark')
        require(len({cases[k]['captureSHA256'] for k in views}) == 4, 'reused UI capture')
        for k in views:
            r = cases[k]
            require(hexdigest(r['captureSHA256']) and r['minimumWindow'] is True and r['permissionHelpCorrect'] is True,
                    'missing installed UI evidence')
        for k in ('library','capture'):
            r = cases[k]
            require(r['actualPNGs'] > 0 and all(time_ms(r[field]) for field in ('latencyMs','cpuPercent','rssKiB'))
                    and r['rssKiB'] > 0 and r['measuredOnInstalledApp'] is True, 'missing performance measurements')
    else:
        require(gate == 'G6' and set(cases) == {'install','sparkle','replace'}, 'missing installation/upgrade route')
        for r in rows:
            require(r['launched'] is True and r['gatekeeper'] == 'accepted' and set(r['slices']) == {'arm64','x86_64'},
                    'unverified installation')
        for k in ('sparkle','replace'):
            r = cases[k]
            require(r['fromVersion'] == '1.0.5' and r['fromBuild'] == '31' and r['quickCheck'] == 'ok'
                    and count(r['priorMediaCount']) and r['priorMediaCount'] > 0 and hexdigest(r['beforeInventory'])
                    and r['beforeInventory'] == r['preservedInventory'], 'upgrade lost prior data')
        require(cases['sparkle']['signedFeedVerified'] is True, 'unverified signed update')


def verify_gate(gate, candidate, run, observer, seen):
    for receipt, kind in ((run, 'product-trace'), (observer, 'independent-observation')):
        require(receipt['gate'] == gate and receipt['candidate'] == candidate and receipt['kind'] == kind
                and receipt['status'] == 'PASS' and hexdigest(receipt['sessionID']), 'wrong evidence scope')
    require(observer['sessionID'] == run['sessionID'] and str(observer['collector']).strip().casefold() != str(run['collector']).strip().casefold()
            and all(isinstance(r['collector'],str) and r['collector'].strip() for r in (run,observer)),
            'missing independent witness')
    def indexed(receipt):
        rows = receipt['measurements']
        require(isinstance(rows,list) and rows, 'empty evidence')
        keys = [(r.get('browser',''),r['case']) for r in rows]
        require(len(set(keys)) == len(rows), 'duplicate case')
        return dict(zip(keys,rows))

    native, observed = indexed(run), indexed(observer)
    require(native.keys() == observed.keys(), 'observer saw different cases')
    rows = []
    for key, trace in native.items():
        witness = observed[key]
        shared = trace.keys() & witness.keys()
        require('sampleID' in shared and hexdigest(trace['sampleID'])
                and all(canonical(trace[k]) == canonical(witness[k]) for k in shared),
                'wrong sample or conflicting observations')
        require('automaticRetries' in trace and 'automaticRetries' not in witness
                and 'sends' in witness and 'sends' not in trace and 'foreignWrites' in witness,
                'need separate native and independent measurements')
        if gate in ('G1','G2'):
            require('inputMs' in trace and 'inputs' in trace and 'inputs' not in witness
                    and 'newCard' in witness and 'newCard' not in trace and 'observedPayload' in witness
                    and 'payload' in trace and 'payload' not in witness and 'observedPayload' not in trace
                    and 'target' in shared and 'operation' in shared, 'missing native or page observation')
        row = {**trace,**witness}
        require(all(count(v) for k,v in row.items() if k in
                    ('inputs','starts','newOriginalCards','priorAttachmentCount','priorMediaCount','selectedLength')),
                'invalid measured count')
        rows.append(row)
    ids = {r['sampleID'] for r in rows}
    require(len(ids) == len(rows) and ids.isdisjoint(seen['sampleID']), 'replayed sample')
    seen['sampleID'].update(ids)
    gate_details(gate,rows,seen)
