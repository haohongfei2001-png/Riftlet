import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from fixtures import HERE, sha
from matrix import fixture_result, read_json, render
from native_evidence import audit, audit_batch


def token(k):
    return sha(str(k).encode())


def pair_case(case='F03'):
    # Unit-test data in memory. No fields come from a packaged application or live service.
    pkg = dict(sourceSHA='a' * 40, build='999', appSHA256=token('app'), dmgSHA256=token('dmg'))
    scope = dict(level='L3', case=case, browser='chrome', bundle='com.google.Chrome', browserVersion='test',
                 provider='chatgpt', providerRevision=1, programSHA256=token('program'), surface='ordinary-chat',
                 mode='default', locale='zh', accountTier='test', macOS='test', arch='arm64',
                 profileKind='authenticated-test-session', composition='ordinary-signed-app', runID='unit')
    host = dict(schema=1, collector='riftlet-native', operator='fixture-operator', candidate=pkg, scope=scope,
                operations=[], pairs=[])
    oracle = dict(schema=1, collector='independent-ui-observer', reviewer='fixture-reviewer', candidate=pkg,
                  scope=scope.copy(), operations=[])
    for i, click in enumerate([0, 500, 2000, 3700, 5000, 6000]):
        op = dict(operation=token(i), invocationSHA256=token(i+10), targetSHA256=token('draft'),
                  originalSHA256=token(i+20), payloadSHA256=token(i+30), clickMs=click, inputEntered=1,
                  timingsMs=dict(clickToBound=None,clickToInput=None,clickToPositive=None,positiveToHidden=None))
        host['operations'].append(op)
        oracle['operations'].append(dict(operation=op['operation'], targetSHA256=op['targetSHA256'],
            originalSHA256=op['originalSHA256'], payloadSHA256=op['payloadSHA256'], newCardSHA256=token(('card',i)), automaticSends=0, changedOtherTargets=0, extraInputs=0,
            addedMatchingCards=1, priorTextPreserved=True, selectionPreserved=True, priorAttachmentsPreserved=True,
            processing='unknown', handoff='accepted', observedOriginalCard=True))
        if i % 2:
            host['pairs'].append([token(i-1),token(i)])
    return pkg, host, oracle


def assess(pkg, host, oracle):
    raw = json.dumps(oracle).encode()
    host['oracleSHA256'] = sha(raw)
    return audit(pkg, host, raw)


class MatrixTests(unittest.TestCase):
    def test_planned_cells_and_only_scoped_evidence(self):
        matrix = render(HERE/'evidence')
        self.assertEqual(len(matrix['cells']), 40)
        self.assertEqual(sum(c['scope'] == 'core' for c in matrix['cells']), 16)
        self.assertEqual(matrix['coreLivePassed'], 0)
        for c in matrix['cells']:
            self.assertFalse(c['enabledForRelease'])
            self.assertEqual(set(c['status'].values()), {'NOT_RUN'})
        self.assertEqual(sum(len(c['slices']) for c in matrix['cells']), 5)
        self.assertEqual(matrix, read_json((HERE/'results.json').read_bytes()))

    def test_fabricated_or_relabelled_fixtures_fail(self):
        orig = HERE/'evidence'/'headless-edge.json'
        rows = read_json(orig.read_bytes())
        mutations = [('empty',lambda x:x.update(results=[])),('changed-hash',lambda x:x.update(transcriptSHA256=token(0))),
                     ('package',lambda x:x.update(candidate={'build':'53'})),('provider',lambda x:x.update(provider='claude')),
                     ('browser',lambda x:x.update(browser='chrome')),('level',lambda x:x.update(kind='L3')),
                     ('counts',lambda x:x['results'][0]['counters'].update(nativeSetters=0)),
                     ('program',lambda x:x['inputs'].clear())]
        for label, mutate in mutations:
            with self.subTest(label), tempfile.TemporaryDirectory() as d:
                file = Path(d)/orig.name
                r=copy.deepcopy(rows)
                mutate(r)
                file.write_text(json.dumps(r))
                shutil.copy(orig.with_suffix('.tap'),file.with_suffix('.tap'))
                with self.assertRaises(ValueError):
                    fixture_result(file)

    def test_formal_reconciliation_and_unknown_input(self):
        pkg, host, oracle = pair_case()
        host['operations'][0]['inputEntered'] = None
        self.assertEqual(assess(pkg, host, oracle), 'MATCHED_RECORD_ONLY')
        host['scope']['level'] = oracle['scope']['level'] = 'L2'
        host['scope']['composition'] = oracle['scope']['composition'] = 'signed-isolated-fixture'
        host['scope']['profileKind'] = oracle['scope']['profileKind'] = 'acceptance-fixture'
        with self.assertRaises(ValueError):
            assess(pkg, host, oracle)
        host['operations'][0]['inputEntered'] = 1
        self.assertEqual(assess(pkg, host, oracle), 'MATCHED_RECORD_ONLY')

    def test_no_empty_wrong_level_cross_package_or_unobserved_pass(self):
        mutations = {
            'reversed-events':lambda h,o:h['operations'][0]['timingsMs'].update(clickToBound=25,clickToInput=2),
            'cross-build':lambda h,o:o.update(candidate={**o['candidate'],'build':'2'}),
            'wrong-bytes':lambda h,o:o.update(candidate={**o['candidate'],'appSHA256':token(100)}),
            'empty':lambda h,o:h.update(operations=[]),
            'product-only':lambda h,o:o.update(collector='riftlet-native'),
            'same-actor':lambda h,o:o.update(reviewer=h['operator']),
            'headless-as-live':lambda h,o:[r['scope'].update(composition='headless') for r in (h,o)],
            'wrong-provider':lambda h,o:o['scope'].update(provider='claude'),
            'wrong-bundle':lambda h,o:[r['scope'].update(bundle='com.microsoft.edgemac') for r in (h,o)],
            'wrong-intent':lambda h,o:o['operations'][0].update(operation=token(98)),
            'wrong-target':lambda h,o:o['operations'][0].update(targetSHA256=token(99)),
            'missing-observation':lambda h,o:o['operations'][0].pop('automaticSends'),
            'sent':lambda h,o:o['operations'][0].update(automaticSends=1),
            'unknown-instead-of-zero':lambda h,o:o['operations'][0].update(changedOtherTargets=None),
            'duplicate':lambda h,o:h['operations'][0].update(inputEntered=2),
            'missing-card':lambda h,o:o['operations'][0].update(addedMatchingCards=0),
            'changed-selection':lambda h,o:o['operations'][0].update(selectionPreserved=False),
            'missing-latency':lambda h,o:h['operations'][0].pop('timingsMs'),
            'single-pair':lambda h,o:h.update(pairs=h['pairs'][:1]),
            'deadline':lambda h,o:h['operations'][1].update(clickMs=2000),
            'reused-pair':lambda h,o:h['pairs'].__setitem__(2,h['pairs'][1]),
        }
        for label, mutate in mutations.items():
            with self.subTest(label):
                pkg, host, oracle=pair_case()
                mutate(host,oracle)
                with self.assertRaises(ValueError):
                    assess(pkg,host,oracle)

    def test_live_case_specific_requirements(self):
        for case in ['F01', 'F02', 'F04', 'F05', 'F06']:
            with self.subTest(case):
                pkg, host, oracle = pair_case(case)
                with self.assertRaises(ValueError):
                    assess(pkg, host, oracle)
                observations = oracle['operations']
                if case == 'F01':
                    observations[0].update(coldUnprepared=True,nonemptySelection=True,hadPriorAttachment=True,hadPriorText=True)
                elif case == 'F02':
                    observations[0].update(warmDraft=True,hadPriorAttachment=True)
                elif case == 'F04':
                    observations[0].update(draftKind='new')
                    observations[1].update(draftKind='saved',targetSHA256=token('saved'))
                    host['operations'][1]['targetSHA256']=observations[1]['targetSHA256']
                elif case == 'F05':
                    observations[0].update(richSelectionObserved=True)
                    observations[1].update(concurrentEditPreserved=True)
                else:
                    ops=host['operations']
                    ops[1]['originalSHA256']=observations[1]['originalSHA256']=ops[0]['originalSHA256']
                    ops[0]['timingsMs']['clickToPositive']=300
                    observations[0]['explicitNewClick']=observations[1]['explicitNewClick']=True
                self.assertEqual(assess(pkg,host,oracle), 'MATCHED_RECORD_ONLY')

    def test_forged_or_conflicting_fixture_transcript(self):
        original = HERE/'evidence'/'headless-edge.json'
        with tempfile.TemporaryDirectory() as d:
            receipt = Path(d)/original.name
            rec = read_json(original.read_bytes())
            rec['versions']['browser'] = '999.0'
            receipt.write_text(json.dumps(rec))
            raw = original.with_suffix('.tap').read_bytes()
            receipt.with_suffix('.tap').write_bytes(raw)
            self.assertFalse(fixture_result(receipt)[1][0]['reviewedReceipt'])
            for extra in (b'not ok 2 - failed\n', b'# fail 1\n', b'Bail out!\n'):
                tap = raw + extra
                rec['transcriptSHA256'] = sha(tap)
                receipt.write_text(json.dumps(rec))
                receipt.with_suffix('.tap').write_bytes(tap)
                with self.assertRaises(ValueError):
                    fixture_result(receipt)

    def test_native_counterexamples(self):
        for label in ('same actor alias','reused card','different observed bytes','untracked card',
                      'nonconsecutive pair','aliased draft'):
            with self.subTest(label):
                pkg, host, oracle = pair_case('F04' if label == 'aliased draft' else 'F03')
                rows = oracle['operations']
                if label == 'same actor alias':
                    oracle['reviewer'] = host['operator'].upper() + ' '
                elif label == 'reused card':
                    rows[1]['newCardSHA256'] = rows[0]['newCardSHA256']
                elif label == 'different observed bytes':
                    rows[0]['payloadSHA256'] = token('different')
                elif label == 'untracked card':
                    del rows[0]['newCardSHA256']
                elif label == 'aliased draft':
                    rows[0]['draftKind'], rows[1]['draftKind'] = 'new', 'saved'
                else:
                    for op, click in zip(host['operations'], (0,500,100,1800,2000,3000)):
                        op['clickMs'] = click
                with self.assertRaises(ValueError):
                    assess(pkg, host, oracle)

    def test_same_file_extra_unrequested_click(self):
        pkg, host, oracle = pair_case('F06')
        ops, rows = host['operations'], oracle['operations']
        for i in range(3):
            ops[i]['originalSHA256'] = rows[i]['originalSHA256'] = ops[0]['originalSHA256']
            ops[i]['payloadSHA256'] = rows[i]['payloadSHA256'] = ops[0]['payloadSHA256']
        rows[0]['explicitNewClick'] = rows[1]['explicitNewClick'] = True
        ops[0]['timingsMs']['clickToPositive'] = 300
        with self.assertRaisesRegex(ValueError,'without an explicit click'):
            assess(pkg,host,oracle)

    def test_batch_relabelling_and_duplicate_evidence(self):
        pkg, host, oracle = pair_case()
        raw = json.dumps(oracle).encode()
        host['oracleSHA256'] = sha(raw)
        for domain in ('runID','operation','invocationSHA256','newCardSHA256',None):
            with self.subTest(domain):
                native, page = copy.deepcopy((host, oracle))
                if domain != 'runID':
                    native['scope']['runID'] = page['scope']['runID'] = 'second'
                for i, (op, row) in enumerate(zip(native['operations'], page['operations'])):
                    if domain != 'operation':
                        op['operation'] = row['operation'] = token(('second-op',i))
                    if domain != 'invocationSHA256':
                        op['invocationSHA256'] = token(('second-invoke',i))
                    if domain != 'newCardSHA256':
                        row['newCardSHA256'] = token(('second-card',i))
                ids = [r['operation'] for r in native['operations']]
                native['pairs'] = [ids[i:i+2] for i in (0,2,4)]
                raw2 = json.dumps(page).encode()
                native['oracleSHA256'] = sha(raw2)
                batch = [(host,raw),(native,raw2)]
                if domain is None:
                    self.assertEqual(audit_batch(pkg,batch), ['MATCHED_RECORD_ONLY']*2)
                else:
                    with self.assertRaisesRegex(ValueError,'reused evidence across runs'):
                        audit_batch(pkg,batch)

    def test_target_switch_before_durable_operation(self):
        pkg, host, oracle=pair_case('T01')
        click=dict(clickSHA256=token(100),targetSHA256=token(101),originalSHA256=token(102))
        host.update(operations=[],preIntentRefusals=[dict(**click,inputEntered=0,outcome='refused-before-intent')])
        oracle.update(operations=[],preIntentRefusals=[dict(**click,addedMatchingCards=0,changedOtherTargets=0,
            automaticSends=0,switchedSameURLTarget=True,trayRetained=True,priorDraftPreserved=True)])
        self.assertEqual(assess(pkg,host,oracle),'MATCHED_RECORD_ONLY')
        oracle['preIntentRefusals'][0]['clickSHA256']=token(103)
        with self.assertRaises(ValueError):
            assess(pkg,host,oracle)
        host['preIntentRefusals'].clear()
        oracle['preIntentRefusals'].clear()
        with self.assertRaises(ValueError):
            assess(pkg,host,oracle)

    def test_target_switch_refusal(self):
        pkg, host, oracle=pair_case('T01')
        for op in host['operations']:
            op['inputEntered']=0
        for row in oracle['operations']:
            row.update(newCardSHA256=None,payloadSHA256=None,handoff='refused',processing='unknown',observedOriginalCard=False,addedMatchingCards=0,switchedSameURLTarget=True,trayRetained=True)
        self.assertEqual(assess(pkg,host,oracle),'MATCHED_RECORD_ONLY')
        row = oracle['operations'][0]
        row['processing'] = 'ready'
        with self.assertRaises(ValueError):
            assess(pkg,host,oracle)
        row['processing'] = 'unknown'
        host['operations'][0]['timingsMs']['clickToInput'] = 15
        with self.assertRaises(ValueError):
            assess(pkg,host,oracle)
        host['operations'][0]['timingsMs']['clickToInput'] = None
        oracle['operations'][0]['trayRetained']=False
        with self.assertRaises(ValueError):
            assess(pkg,host,oracle)


if __name__ == '__main__':
    unittest.main()
