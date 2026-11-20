"""Synthetic bytes stay in temporary directories. No production trust anchor or raw evidence is installed."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from formal_results import ADMISSION, INDEX, REPO, HOST_GATES, REQUIRED, SCOPE, VARIANT, apply_index, remote_index
from fixtures import HERE, sha
from matrix import render
from native_evidence import CASES
from test_matrix import pair_case, token


class Bundle:
    def __init__(self, directory):
        self.root = Path(directory)
        self.pkg, _, _ = pair_case()
        self.index = dict(schema=1,candidate=self.pkg,runs=[],observations=[])
        self.counter = 0

    def put(self, data):
        raw = json.dumps(data, sort_keys=True).encode()
        d = sha(raw)
        (self.root/d).write_bytes(raw)
        return d

    def sample(self, case, level='L3', mutate=None):
        _, n, o = pair_case(case)
        self.counter += 1
        prefix = str(self.counter)
        n['scope']['runID'] = o['scope']['runID'] = prefix
        for record in (n,o):
            s = record['scope']
            if level == 'L2':
                s.update(level='L2',composition='signed-isolated-fixture',profileKind='acceptance-fixture')
        ops, rows = n['operations'], o['operations']
        for i,(op,row) in enumerate(zip(ops,rows)):
            op['operation'] = row['operation'] = token((prefix,'op',i))
            op['invocationSHA256'] = token((prefix,'inv',i))
            row['newCardSHA256'] = token((prefix,'card',i))
            op['timingsMs'].update(clickToBound=1,clickToInput=8,clickToPositive=10,positiveToHidden=3)
            row.update(coldUnprepared=True,nonemptySelection=True,hadPriorAttachment=True,hadPriorText=True,
                       richSelectionObserved=True,concurrentEditPreserved=True,warmDraft=True,
                       switchedSameURLTarget=True,explicitNewClick=True)
        if case == 'F04':
            rows[0]['draftKind'] = 'new'
            rows[1]['draftKind'] = 'saved'
            rows[1]['targetSHA256'] = ops[1]['targetSHA256'] = token('saved')
        if case == 'F06':
            for field in ('originalSHA256','payloadSHA256'):
                rows[1][field] = ops[1][field] = ops[0][field]
        ids = [v['operation'] for v in ops]
        n['pairs'] = [ids[i:i+2] for i in (0,2,4)]
        if mutate:
            mutate(n,o)
        n['oracleSHA256'] = self.put(o)
        self.index['runs'].append({'run':self.put(n),'oracle':n['oracleSHA256']})
        return {k:n['scope'][k] for k in VARIANT}

    def observation(self, variant, kind, level, case, status='PASS'):
        self.counter += 1
        s = {k:variant[k] for k in SCOPE[kind]}
        obs = dict(candidate=self.pkg,kind=kind,scope=s,level=level,case=case,status=status)
        for field,role in [('productRaw','product'),('observerRaw','independent')]:
            raw = self.put({'synthetic-test-id':[self.counter,role]})
            rec = {k:obs[k] for k in ('candidate','kind','scope','level','case','status')}
            obs[field] = self.put(dict(**rec,role=role,actor=role,artifactSHA256=raw))
        self.index['observations'].append(self.put(obs))

    def replay(self):
        m = apply_index(render(HERE/'evidence'),self.index,self.root)
        return m,next(c for c in m['cells'] if (c['browser'],c['provider']) == ('chrome','chatgpt'))


class FormalTests(unittest.TestCase):
    def test_full_cell_only_and_shared_release_gates(self):
        with tempfile.TemporaryDirectory() as d:
            bundle = Bundle(d)
            for case in CASES:
                v = bundle.sample(case)
            bundle.sample('F01','L2')
            for (kind,level), cases in REQUIRED.items():
                for case in cases:
                    if case != 'R02':
                        bundle.observation(v,kind,level,case)
            m, cell = bundle.replay()
            self.assertEqual((m['decision'],m['coreLivePassed']),('PARTIAL',1))
            self.assertFalse(cell['eligibleForReleaseReview'])
            bundle.observation(v,'global','L2','R02')
            m, cell = bundle.replay()
            self.assertTrue(cell['eligibleForReleaseReview'])
            self.assertFalse(cell['enabledForRelease'])
            self.assertEqual(len(m['cells']),40)
            bundle.observation(v,'cell','L3','F01','FAIL')
            m, cell = bundle.replay()
            self.assertEqual((cell['status']['L3'],m['coreLivePassed']),('FAIL',0))
            self.assertFalse(cell['eligibleForReleaseReview'])

    def test_no_mixing_or_unknown_unique_input(self):
        with tempfile.TemporaryDirectory() as d:
            b = Bundle(d)
            for case in CASES:
                def tweak(n,o):
                    if case == 'F02':
                        o['scope']['programSHA256'] = n['scope']['programSHA256'] = token('other revision')
                v = b.sample(case,mutate=tweak)
            b.observation(v,'cell','L3','service-recovery')
            m,c = b.replay()
            self.assertEqual((len(c['variants']),m['coreLivePassed'],c['status']['L3']),(2,0,'PARTIAL'))
            b.sample('F02',mutate=lambda n,o:n['operations'][0].update(inputEntered=None))
            self.assertEqual(b.replay()[1]['status']['L3'],'UNKNOWN')

    def test_no_summary_pass_tamper_or_reuse(self):
        with tempfile.TemporaryDirectory() as d:
            b = Bundle(d)
            v = b.sample('F01')
            b.observation(v,'cell','L3','F02','PASS')
            with self.assertRaisesRegex(ValueError,'native PASS'):
                b.replay()
            b.index['observations'].clear()
            b.index['runs'].append(b.index['runs'][0])
            with self.assertRaisesRegex(ValueError,'reused'):
                b.replay()
            b.index['runs'].pop()
            (Path(d)/b.index['runs'][0]['oracle']).write_bytes(b'{}')
            with self.assertRaisesRegex(ValueError,'digest mismatch'):
                b.replay()

    def test_complete_core_and_host_specific_proofs(self):
        with tempfile.TemporaryDirectory() as d:
            b = Bundle(d)
            cases = [c for c in render(HERE/'evidence')['cells'] if c['scope'] == 'core']
            gates, special = set(), []
            for cell in cases:
                def scope(n,o):
                    for rec in (n,o):
                        rec['scope'].update(browser=cell['browser'],bundle=cell['bundle'],provider=cell['provider'])
                for case in CASES:
                    v = b.sample(case,mutate=scope)
                b.sample('F01','L2',scope)
                for (kind,level), names in REQUIRED.items():
                    for name in names:
                        ident = (kind,level,name,*(v[k] for k in SCOPE[kind]))
                        if ident not in gates:
                            b.observation(v,kind,level,name)
                            gates.add(ident)
                if v['browser'] in HOST_GATES and not any(x['browser'] == v['browser'] for x in special):
                    special.append(v)
            m,_ = b.replay()
            self.assertEqual((m['decision'],m['coreLivePassed']),('PARTIAL',16))
            for v in special:
                for name in HOST_GATES[v['browser']]:
                    b.observation(v,'host','L2',name)
            m,_ = b.replay()
            self.assertEqual(m['decision'],'READY_FOR_RELEASE_REVIEW')
            self.assertFalse(any(c['enabledForRelease'] for c in m['cells']))
            self.assertEqual(sum(c['eligibleForReleaseReview'] for c in m['cells']),16)

    def test_admission_is_bound_to_reviewed_tree_index_and_candidate(self):
        def encode(obj):
            return json.dumps(obj).encode()
        h,g,tree,main,merge,source = (str(i)*40 for i in range(1,7))
        candidate = dict(sourceSHA=source,appSHA256=token('app'),dmgSHA256=token('dmg'),build='54')
        index = dict(schema=1,candidate=candidate,runs=[],observations=[])
        report = dict(reviewedBase=main,reviewedSource=g,reviewedTree=tree,result='PASS',findings=[],
                      reviewer='reviewer',issue120Verified107Merge=merge,issue120SignedCandidate=candidate,
                      issue120AcceptanceIndexSHA256=sha(encode(index)))
        holder = {}
        def blob(ref,path):
            if (ref,path) == (g,INDEX):
                return encode(index)
            self.assertEqual((ref,path),(h,ADMISSION))
            text = json.dumps(holder['report'])
            return encode(dict(reviewedSource=g,reviewedTree=tree,reviewedBase=main,authorRole='author',
                               reviews=[dict(report=text,sha256=sha(text.encode()),result='PASS',reviewer='reviewer',
                                             source=g,tree=tree)]))
        lookup = {'pulls/122':{'base':{'ref':'main','sha':main,'repo':{'full_name':REPO}},
                               'head':{'repo':{'full_name':REPO},'sha':h}},
                  'compare/'+main+'...main':{'merge_base_commit':{'sha':main}},
                  'commits/'+h:{'parents':[{'sha':g}], 'files':[{'filename':ADMISSION,'status':'modified'}]},
                  'commits/'+g:{'commit':{'tree':{'sha':tree}}}}
        with patch('formal_results.api',side_effect=lookup.__getitem__), patch('formal_results.blob',side_effect=blob), \
             patch('formal_results.product_binding',return_value=merge):
            holder['report'] = report
            self.assertEqual(remote_index()[0],index)
            for change in ({'issue120SignedCandidate':{**candidate,'build':'53'}},{'issue120AcceptanceIndexSHA256':token('forged')},
                           {'issue120Verified107Merge':main},{'reviewedTree':h},{'reviewer':'author'}):
                holder['report'] = {**report,**change}
                with self.assertRaises(ValueError):
                    remote_index()

    def test_remote_retains_trust_boundary(self):
        with patch('formal_results.api',return_value={'base':{'ref':'comparison'}}):
            with self.assertRaisesRegex(ValueError,'integration baseline'):
                remote_index()
