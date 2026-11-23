import ast,contextlib,copy,json,sqlite3,tempfile,unittest,uuid
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import sys
# The installed native host lives in an independent deployment. The public host is
# used only for its checks dictionary; these tests never call a browser or WindowServer.
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'gui-host'))
import gui_sample,issuer_cycle as sched,lanes
from window_hit import original_hit
from retire_missing import verify,attested
D=Path(__file__).resolve().parent; H='1'*64; SRC='a'*40
def write(p,x):
    with p.open('x') as f:json.dump(x,f)
def scope(b,f,k,n=None):
    r=b/(k+'-'+(n or uuid.uuid4().hex))
    return dict(root=str(r),family=f,case=k,entry='new-sole-verified-native-window',preInput=True)
class LaneTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.b=b=Path(self.temp.name).resolve();(b/'execution').mkdir()
        self.db=sqlite3.connect(':memory:');self.db.execute('create table ticks(id integer primary key,utc real,sampled int,ready int,protected int)')
        self.real=[];self.prep=[];self.front='chrome';self.eligible={'chrome':True,'edge':True};self.positive={'chrome':True,'edge':True};self.fail=None;self.after=0
        self.m=SimpleNamespace(BASE=b,SITE=b,G4=b,host=SimpleNamespace(write_new=write,action=self.action),claim_gui=lambda:contextlib.nullcontext(8),sample=self.sample)
    def tearDown(self):self.db.close();self.temp.cleanup()
    def keep(self,row):
        r=Path(row['root']);s=r/'signed61'/row['family'];s.mkdir(parents=True);write(s/'ready61.json',{})
        lanes.index(self.b,row,write);return row
    def sample(self,b,site,f,n,scope=None):
        ready=bool(scope and self.positive[f]);target=lanes.hashlib.sha256(scope['root'].encode()).hexdigest() if scope else None
        return dict(family=f,nonce=n,heldCase=scope['case'] if scope else None,ready=ready,targetKey=target,digest=H,
              checks=dict.fromkeys(gui_sample.CHECKS,ready),identityProof={'nativeRouteSHA256':target,'composerSHA256':None} if scope else None,
              environment={'eligibleForPreparation':self.eligible[f],'protectedForeground':False,'systemDialogOnScreen':False,'familyFrontmost':self.front==f})
    def action(self,b,site,g4,args):
        act,f,k,n,*rest=args
        if act=='prepare':
            self.prep.append((f,k));p=b/'active-scope.json'
            if not p.exists():
                row=self.keep(scope(b,f,k));write(p,row)
            return {}
        a=lanes.read(Path(rest[0]));self.real.append((f,k));root=Path(lanes.read(b/'active-scope.json')['root'])
        if self.fail=='before':
            done=dict(a,outcome='STOPPED_BEFORE_INPUT',productInputCount=0,inputBoundaryEntered=False)
        else:
            write(root/'business-claim.json',a)
            if self.fail=='after-claim':raise RuntimeError()
            done=dict(a,outcome='PASS')
        write(Path(a['terminalPath']),done)
        return dict(outcome=done['outcome'],receiptSHA256=H)
    def tick(self,*items):return sched.cycle(self.m,self.db,items,SRC,H)
    def test_legacy_edge_scope_does_not_block_ready_chrome(self):
        edge=self.keep(scope(self.b,'edge','g4c'));write(self.b/'active-scope.json',edge)
        self.eligible['edge']=self.positive['edge']=False
        self.assertEqual(self.tick(('edge','g4c'),('chrome','g1'))['case'],'g1')
        self.assertEqual(self.real,[('chrome','g1')]);self.assertEqual(lanes.original(self.b,'edge','g4c'),edge)
        self.assertEqual(self.tick(('edge','g4c'),('chrome','g1'))['state'],'WAITING_ON_ORIGINAL_ENVIRONMENT')
    def test_pending_case_blocks_both_families_only_for_g4(self):
        self.fail='after-claim';self.tick(('chrome','g4c'))
        self.fail=None;self.tick(('edge','g4c'),('edge','g2'))
        self.assertEqual(self.real,[('chrome','g4c'),('edge','g2')])
        self.assertEqual(self.tick(('edge','g4c'),('chrome','g4c'))['state'],'WAITING_FOR_ORIGINAL_TERMINAL')
    def test_positive_prewriter_stop_allows_another_family(self):
        self.fail='before';self.tick(('edge','g4c'))
        self.fail=None;self.eligible['edge']=False
        self.tick(('edge','g4c'),('chrome','g4c'))
        self.assertEqual(self.real,[('edge','g4c'),('chrome','g4c')])
        self.assertEqual(self.tick(('edge','g4c'),('chrome','g4c'))['state'],'DISPATCH_TERMINAL')
    def test_orphan_business_marker_blocks_failover(self):
        a=self.keep(scope(self.b,'edge','g4c'));write(Path(a['root'])/'business-claim.json',{'targetKey':H})
        self.assertEqual(self.tick(('chrome','g4c'))['state'],'WAITING_FOR_ORIGINAL_TERMINAL');self.assertFalse(self.real)
    def test_global_lease_busy_creates_nothing(self):
        self.m.claim_gui=lambda:contextlib.nullcontext(None)
        self.assertEqual(self.tick(('chrome','g1'))['state'],'GUI_HELD_BY_OTHER_OWNER')
        self.assertEqual(list((self.b/'execution').iterdir()),[])
    def test_different_composer_or_document_in_double_check_blocks(self):
        a=self.keep(scope(self.b,'chrome','g1'))
        i=iter(('11','22','33'));old=self.sample
        def sample(*args,**kw):
            r=old(*args,**kw);r['identityProof']['composerSHA256']=next(i);return r
        self.m.sample=sample
        self.assertEqual(self.tick(('chrome','g1'))['state'],'ORIGINAL_REQUIRED');self.assertFalse(self.real)
    def test_sample_error_in_one_lane_does_not_abort_other(self):
        old=self.sample
        def s(b,site,f,n,scope=None):
            if f=='edge':raise ValueError('READ_REFUSED')
            return old(b,site,f,n,scope)
        self.m.sample=s;self.assertEqual(self.tick(('edge','g2'),('chrome','g1'))['case'],'g1')
    def test_stable_failure_is_bounded_and_recoverable(self):
        self.positive['chrome']=False;self.keep(scope(self.b,'chrome','g1'))
        self.assertEqual(self.tick(('chrome','g1'))['state'],'ORIGINAL_REQUIRED')
        self.assertEqual(self.tick(('chrome','g1'))['state'],'WAITING_ON_ORIGINAL_ENVIRONMENT')
        self.db.execute('update lane_attempts set utc=utc-181')
        self.assertEqual(self.tick(('chrome','g1'))['state'],'ORIGINAL_REQUIRED')
        self.positive['chrome']=True;self.assertEqual(self.tick(('chrome','g1'))['state'],'CASE_OBSERVED')
    def test_mid_switch_journal_preserves_both_originals(self):
        a=self.keep(scope(self.b,'edge','g2'));b=self.keep(scope(self.b,'chrome','g1'));write(self.b/'active-scope.json',a)
        with patch.object(lanes.os,'replace',side_effect=OSError()):
            with self.assertRaises(OSError):lanes.point(self.b,b,write)
        self.assertEqual(lanes.read(self.b/'active-scope.json'),a)
        lanes.point(self.b,b,write)
        self.assertEqual(lanes.original(self.b,'edge','g2'),a);self.assertEqual(lanes.read(self.b/'active-scope.json'),b)
    def test_cg_ax_admission(self):
        for cg,center,quorum,want in [(True,True,False,True),(True,False,True,True),(False,True,True,False),(True,False,False,False),(True,False,1,False)]:
            self.assertEqual(original_hit(dict(cgWindowOnScreen=cg,centerHitOriginalCG=center,originalAXHitQuorum=quorum,originalAXHits=dict(blockedByProtectedSurface=False))),want)
        self.assertFalse(original_hit({}))
        for protected in (True,None,1,0,'false'):
            # Even an independently positive CG and AX quorum cannot authorize protected or unreadable coverage.
            o=dict(cgWindowOnScreen=True,centerHitOriginalCG=True,originalAXHitQuorum=True,
                   originalAXHits=dict(blockedByProtectedSurface=protected))
            self.assertFalse(original_hit(o))
        for classification in ('protectedPID','unresolvedOnCaptureRectangle','protectedForeground'):
            o=dict(cgWindowOnScreen=True,centerHitOriginalCG=True,originalAXHitQuorum=True,
                   originalAXHits=dict(blockedByProtectedSurface=True,classifications=[classification],
                                       unresolvedOnCaptureRectangle=classification=='unresolvedOnCaptureRectangle'))
            self.assertFalse(original_hit(o))
        self.assertFalse(original_hit({'cgWindowOnScreen':True,'centerHitOriginalCG':True}))
    def test_missing_proof_retirement_and_after_issue(self):
        f='edge';a=self.keep(scope(self.b,f,'g4c'));r=Path(a['root']);s=r/'signed61'/f
        write(self.b/'candidate.json',dict(dmgSHA256=H));write(r/'candidate-scope.json',dict(dmgSHA256=H))
        i=dict(family=f,dynamicSignature=True,pid=9,sessionID='birth',bundle='edge',teamID='test',executable='browser',bundlePath='browser.app',developerIDRequirement='signed',windowIDs=[])
        write(s/'before.json',i);write(s/'creation.json',dict(family=f,pid=9,sessionID='birth',phase='qaAddressConfirmed',windowID='7'))
        p=self.b/'evidence';p.mkdir()
        import os
        for n in (1,2):
            q=p/(f+'-inventory-'+str(n)+'.json');write(q,{'code':0,'error':None,'json':i});stamp=(s/'creation.json').stat().st_mtime_ns+n*1000000
            os.utime(q,ns=(stamp,stamp))
        proof=verify(self.b,a,p);write(r/'external-disappearance-before-input.json',proof);self.assertTrue(attested(self.b,a))
        write(r/'business-claim.json',{'targetKey':H})
        with self.assertRaises(ValueError):verify(self.b,a,p)
        with self.assertRaises(ValueError):attested(self.b,a)
    def test_postprepare_observer_exception_is_local_before_claim(self):
        self.keep(scope(self.b,'chrome','g1'));old=self.sample;i=0
        def sample(b,site,f,n,scope=None):
            nonlocal i
            if f=='chrome':
                i+=1
                if i>=2:raise OSError('transient')
            return old(b,site,f,n,scope)
        self.m.sample=sample
        self.assertEqual(self.tick(('chrome','g1'))['state'],'ORIGINAL_SAMPLE_UNAVAILABLE')
        self.assertFalse(list((self.b/'execution').glob('claim-*.json')))
        self.assertEqual(self.tick(('chrome','g1'),('edge','g2'))['state'],'CASE_OBSERVED');self.assertEqual(self.real,[('edge','g2')])
    def test_conflicting_registered_g4_scope_stops_only_g4(self):
        a=self.keep(scope(self.b,'chrome','g4c'));self.keep(scope(self.b,'chrome','g4c'))
        self.assertEqual(self.tick(('chrome','g4c'),('edge','g4c'),('edge','g2'))['state'],'CASE_OBSERVED');self.assertEqual(self.real,[('edge','g2')])
    def test_unindexed_private_scope_with_input_evidence_is_held(self):
        old=scope(self.b,'edge','g4c');s=Path(old['root'])/'signed61/edge/live-g4-transport';s.mkdir(parents=True)
        self.assertEqual(self.tick(('chrome','g4c'))['state'],'WAITING_FOR_ORIGINAL_TERMINAL');self.assertFalse(self.real)
if __name__=='__main__':unittest.main(verbosity=2)
