"""Offline W0 regressions. All positive data below are synthetic and never admitted."""
import base64
from pathlib import Path
import json
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import baseline as b
REAL_PACKAGE = b.verify_package
from gate107 import canonical, sha


def label(text):
    return sha(text.encode())


def observations(gate):
    if gate in ('G1','G2'):
        rows = []
        for i,case in enumerate(('cold','warm','pair1a','pair1b','pair2a','pair2b','pair3a','pair3b')):
            draft = 'saved' if case=='warm' else 'temporary'
            row = dict(case=case,browser='Chrome' if gate=='G1' else 'Edge',session=label(gate+'session'),
                       site='chatgpt.com',authenticated=True,ordinaryApp=True,target=label(gate+draft),
                       draftKind=draft,defaultProfile=True,preparedBeforeLaunch=False,alreadyRunning=case!='cold',
                       inputs=1,newOriginalCards=1,priorAttachmentCount=2,selectedLength=3)
            for field in ('originalPNG','operation','invocation','newCard','payload'):
                row[field] = label(gate+case+field)
            row['observedPayload'] = row['payload']
            for prefix,suffix in (('draftBefore','draftAfter'),('selectionBefore','selectionAfter'),
                                  ('attachmentsBefore','retainedAttachments')):
                row[prefix] = row[suffix] = label(prefix)
            for n,k in enumerate(('clickedMs','boundMs','inputMs','acceptedMs','hiddenMs')):
                row[k] = i*1000 + n*10
            rows.append(row)
        return rows
    if gate=='G3':
        return [dict(browser=name,case=c,wrongTargetInputs=0,extraInputs=0,duplicateCards=0,
                     draftMutations=0,observedTransition=True) for c in b_gate_targets() for name in ('Chrome','Edge')]
    if gate=='G4':
        failed,uid,prior,manual = map(label,('failed','uid','old','manual'))
        make = lambda case,**k:dict(case=case,site='chatgpt.com',authenticated=True,ordinaryApp=True,target=label('target'),**k)
        return [make('beforeInput',inputs=0,starts=0,retained=True),
                make('inputNoStart',inputs=1,starts=0,ready=False,operation=prior),
                make('startThenOriginalFailed',inputs=1,starts=1,sameCardServiceFailure=True,ready=False,
                     operation=failed,invocation=uid,originalPNG=label('failed-img'),newCard=label('card'),failedCard=label('card')),
                make('redraw',operation=failed,invocation=uid,inputs=0,sameCardObserved=True),
                make('restartLostReply',operation=failed,invocation=uid,inputs=0,readOnly=True),
                make('restoreOriginal',operation=failed,invocation=uid,inputs=0,restoredPNG=label('failed-img')),
                make('explicitRetry',operation=manual,invocation=label('retry'),manualClick=True,originalPNG=label('failed-img'),
                     payload=label('retry-payload'),observedPayload=label('retry-payload'),newCard=label('recovered-card'),inputs=1,newOriginalCards=1,starts=1),
                make('preservedUnknown',operation=prior,priorUnknownOperation=prior,state='UNKNOWN',afterRetryOperation=manual),
                dict(case='localStorage',quickCheck='ok',trashRestoredCount=1,originalMediaInventory=label('media'),
                     restoredMediaInventory=label('media'),historyPreserved=True,capturedPNGIngested=True)]
    if gate=='G5':
        return [dict(case=k,captureSHA256=label(k),minimumWindow=True,permissionHelpCorrect=True)
                for k in ('en-light','en-dark','zh-light','zh-dark')] + [
                dict(case=k,actualPNGs=5,cpuPercent=5,rssKiB=100,latencyMs=50,measuredOnInstalledApp=True)
                for k in ('library','capture')]
    return [dict(case=k,launched=True,gatekeeper='accepted',slices=['arm64','x86_64'],fromVersion='1.0.5',
                 fromBuild='31',quickCheck='ok',priorMediaCount=5,beforeInventory=label('data'),
                 preservedInventory=label('data'),signedFeedVerified=True) for k in ('install','sparkle','replace')]


def b_gate_targets():
    from gate107 import SAFE_TARGETS
    return sorted(SAFE_TARGETS)


class Verifier(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ws = Path(self.tmp.name)
        self.raw = self.ws/'acceptance'/'w0-originals'
        self.raw.mkdir(parents=True)
        self.head,self.g,self.src,self.merge,self.main,self.ev,self.seal,self.base = [k*40 for k in 'abcedf81']
        self.candidate = dict(sourceSHA=self.src,appSHA256='4'*64,dmgSHA256='5'*64,build='53')
        self.record = dict(schema=1,pr119Head=self.head,candidate=self.candidate,mergeSHA=self.merge,
                           mainlineSHA=self.merge,reviewSHA=self.g,checks={},gates={},acceptanceAdmissionSHA=self.seal)
        self.pull = dict(merged=True,head={'sha':self.head},merge_commit_sha=self.merge,
                         base={'ref':'main','repo':{'full_name':b.REPO}})
        self.api,self.files = {},{}
        self.mock_api = self.patch('api',side_effect=self.get)
        self.patch('verify_package',side_effect=lambda r,w:self.assertEqual(r['candidate'],self.candidate))
        self.make_graph()
        self.make_receipts()
        self.seal_index()

    def patch(self,name,**kwargs):
        ctx = patch.object(b,name,**kwargs)
        obj = ctx.start()
        self.addCleanup(ctx.stop)
        return obj

    def get(self,path):
        if path.startswith('contents/'):
            p,c = path[9:].split('?ref=')
            return {'type':'file','encoding':'base64','path':p,'content':base64.b64encode(self.files[c,p]).decode()}
        return self.api[path]

    def relation(self,a,c):
        self.api[f'compare/{a}...{c}'] = {'merge_base_commit':{'sha':a},'files':[]}

    def make_graph(self):
        for c,parent in [(self.merge,[self.base,self.head]),(self.src,[]),(self.g,[self.src]),
                         (self.head,[self.g]),(self.ev,[self.g]),(self.seal,[self.ev])]:
            self.api['commits/'+c] = dict(parents=[{'sha':p} for p in parent],commit={'tree':{'sha':'2'*40}},
                                         files=[{'filename':b.ADMISSION,'status':'modified'}])
        for a,c in [(b.BUILD49,self.head),(self.merge,self.merge),(self.merge,self.main),(self.src,self.g),
                    (self.seal,self.main),(self.ev,self.ev)]:
            self.relation(a,c)
        for c in (self.main,self.merge):
            self.api['git/trees/'+c] = {'truncated':False,'tree':[{'path':'Sources','type':'tree','mode':'040000','sha':self.src}]}
        self.add_review(self.head,self.g)
        path = 'independent-final.json'
        raw = canonical(dict(product=self.src,tree='2'*40,result='PASS'))
        self.files[self.g,b.EVIDENCE+path] = raw
        self.record.update(productReviewFile=path,productReviewSHA256=sha(raw))
        self.files[self.src,'Resources/Info.plist'] = plistlib.dumps(dict(CFBundleVersion='53',CFBundleShortVersionString='1.0.7'))
        checks = []
        for i,(name,w) in enumerate(b.CHECKS.items(),1):
            run = 10 if name.startswith('Native') else 20
            pin = dict(runID=run,jobID=i,workflowID=run+5,attempt=1,conclusion='success')
            self.record['checks'][name] = pin
            ok = dict(head_sha=self.head,status='completed',conclusion='success')
            checks.append(dict(ok,id=i,name=name,app={'slug':'github-actions'}))
            self.api[f'actions/jobs/{i}'] = dict(ok,id=i,name=name,run_id=run,run_attempt=1)
            self.api[f'actions/runs/{run}'] = dict(ok,id=run,workflow_id=run+5,path='.github/workflows/'+w,
                event='pull_request',repository={'full_name':b.REPO},run_attempt=1,
                pull_requests=[{'number':119,'head':{'sha':self.head},'base':{'ref':'main'}}])
        self.api[f'commits/{self.head}/check-runs?filter=latest&per_page=100'] = dict(total_count=5,check_runs=checks)

    def add_review(self,h,g,**extra):
        tree = '2'*40
        report = dict(reviewedSource=g,reviewedTree=tree,reviewedBase=self.base,reviewer='qa',result='PASS',findings=[],**extra)
        content = canonical(report)
        audit = dict(source=g,tree=tree,result='PASS',reviewer='qa',report=content.decode(),sha256=sha(content))
        self.files[h,b.ADMISSION] = canonical(dict(reviewedSource=g,reviewedTree=tree,reviewedBase=self.base,
                                                   reviews=[audit],authorRole='developer'))

    def make_receipts(self):
        for gate in b.GATES:
            entry = self.record['gates'][gate] = {'status':'PASS'}
            rows = observations(gate)
            for i,row in enumerate(rows):
                row['sampleID'] = label(f'{gate} sample {i}')
            for kind,tag in [('run','product-trace'),('observer','independent-observation')]:
                subset=[]
                for row in rows:
                    if kind=='run':
                        sub = {k:v for k,v in row.items() if k not in ('newCard','observedPayload')}
                        sub['automaticRetries']=0
                    else:
                        sub = {k:v for k,v in row.items() if k in ('browser','case','sampleID','newCard','observedPayload','operation','target')}
                        sub.update(sends=0,foreignWrites=0)
                    subset.append(sub)
                artifact = (kind+gate+' independently reviewed original test data').encode()
                digest=sha(artifact)
                (self.raw/digest).write_bytes(artifact)
                receipt = canonical(dict(gate=gate,candidate=self.candidate,kind=tag,status='PASS',collector=tag,
                                    artifactSHA256=digest,sessionID=label(gate),measurements=subset))
                path = b.EVIDENCE+f'acceptance/{gate}.{kind}.json'
                self.files[self.ev,path] = receipt
                entry[kind] = dict(commit=self.ev,path=path,sha256=sha(receipt),artifactSHA256=digest)

    def seal_index(self):
        i={k:self.record[k] for k in ('candidate','pr119Head','gates')}
        self.add_review(self.seal,self.ev,acceptance107IndexSHA256=sha(canonical(i)))

    def run_check(self):
        return b.verify(self.record,self.pull,self.main,self.ws)

    def test_complete_remote_graph_and_six_measured_gates(self):
        self.run_check()

    def test_unmerged_or_old_head_or_spliced_build(self):
        for field,value in [('pr119Head','f'*40),('mergeSHA',self.src),('mainlineSHA',None)]:
            with self.subTest(field=field),patch.dict(self.record,{field:value}),self.assertRaises((ValueError,KeyError)):
                self.run_check()
        with patch.dict(self.pull,merged=False),self.assertRaises(ValueError):
            self.run_check()
        with patch.dict(self.candidate,build='52'),self.assertRaises(ValueError):
            self.run_check()

    def test_current_main_revert_fails(self):
        self.api['git/trees/'+self.main]['tree'][0]['sha'] = '0'*40
        with self.assertRaisesRegex(ValueError,'product tree'):
            self.run_check()

    def test_missing_failed_or_wrong_workflow(self):
        checks=self.record['checks']
        with patch.dict(checks,clear=True),self.assertRaises(ValueError):
            self.run_check()
        for name,field,value in [('actions/jobs/1','head_sha',self.src),('actions/runs/10','conclusion','failure'),
                                 ('actions/runs/10','path','other.yml')]:
            with self.subTest(field=field),patch.dict(self.api[name],{field:value}),self.assertRaises(ValueError):
                self.run_check()

    def test_self_attested_pass_and_missing_original(self):
        self.add_review(self.seal,self.ev)
        with self.assertRaisesRegex(ValueError,'independent admission'):
            self.run_check()
        self.seal_index()
        next(self.raw.iterdir()).unlink()
        with self.assertRaises(OSError):
            self.run_check()

    def change_receipt(self,gate,kind,change):
        ref=self.record['gates'][gate][kind]
        key=(self.ev,ref['path'])
        data=json.loads(self.files[key])
        change(data)
        self.files[key]=canonical(data)
        ref['sha256']=sha(self.files[key])
        self.seal_index()

    def test_mixed_candidate_even_in_reviewed_index(self):
        self.change_receipt('G2','observer',lambda r:r['candidate'].update(build='51'))
        with self.assertRaisesRegex(ValueError,'scope'):
            self.run_check()

    def test_false_pass_and_unchanged_comment(self):
        self.change_receipt('G4','run',lambda r:r.update(measurements=[]))
        with self.assertRaisesRegex(ValueError,'empty evidence'):
            self.run_check()

    def test_wrong_payload_and_fake_owner(self):
        self.change_receipt('G1','observer',lambda r:r['measurements'][0].update(observedPayload='9'*64))
        with self.assertRaisesRegex(ValueError,'payload'):
            self.run_check()

    def test_three_pairs_cannot_share_an_invocation(self):
        def reuse(r):
            r['measurements'][3]['invocation']=r['measurements'][2]['invocation']
        self.change_receipt('G2','run',reuse)
        with self.assertRaisesRegex(ValueError,'reused invocation'):
            self.run_check()

    def test_fourth_pair_is_checked_and_preserved(self):
        from gate107 import browser_gate
        rows=observations('G1')
        for row in rows:
            row.update(automaticRetries=0,sends=0,foreignWrites=0)
        for n,suffix in enumerate('ab',8):
            row={**rows[-1],'case':'pair4'+suffix}
            for field in ('invocation','operation','originalPNG','newCard'):
                row[field]=label(row['case']+field)
            for offset,k in enumerate(('clickedMs','boundMs','inputMs','acceptedMs','hiddenMs')):
                row[k]=n*1000+offset
            rows.append(row)
        seen=lambda:{k:set() for k in ('invocation','operation','originalPNG','newCard')}
        browser_gate(rows,'G1',seen())
        rows[-1]['clickedMs']+=3000
        with self.assertRaises(ValueError):
            browser_gate(rows,'G1',seen())

    def test_reviewed_dmg_hash_cannot_be_replaced(self):
        raw = canonical({'source':self.src,'version':'1.0.7','build':'53','finalSHA256':'9'*64})
        path=b.EVIDENCE+'build53.json'
        self.files[self.g,path]=raw
        self.record['packageRecord']={'commit':self.g,'path':path,'sha256':sha(raw)}
        with self.assertRaisesRegex(ValueError,'different reviewed package'):
            REAL_PACKAGE(self.record,self.ws)

    def test_signed_app_tree_and_build_match(self):
        files={'Contents/program':{'kind':'file','sha256':'a'*64}}
        manifest={'stage':'STAPLED','build':{'source':{'commit':self.src},'version':'1.0.7','build':'53',
                  'architectures':['arm64','x86_64']},'notarization':{'submissionID':'ticket'},
                  'files':{'Riftlet.app/'+k:v for k,v in files.items()}}
        c={**self.candidate,'appSHA256':sha(canonical(files))}
        release={'appSubmissionID':'ticket'}
        b.verify_manifest_identity(manifest,c,release)
        for field,value in [('appSHA256','0'*64),('build','54'),('sourceSHA',self.g)]:
            with self.subTest(field=field),patch.dict(c,{field:value}),self.assertRaisesRegex(ValueError,'inventory'):
                b.verify_manifest_identity(manifest,c,release)

    def test_old_review_for_new_product(self):
        self.api[f'compare/{self.src}...{self.g}']['files']=[{'filename':'Sources/changed.swift'}]
        with self.assertRaisesRegex(ValueError,'changed after'):
            self.run_check()


if __name__=='__main__':
    unittest.main()
