"""No browser actions. Prove that only a terminal, positively observed, isolated target can be parked."""
import hashlib,json,os,tempfile,unittest,uuid
from pathlib import Path
from unittest.mock import patch
import gui_control,gui_park,gui_sample,gui_telemetry

class ParkedScope(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.base=Path(self.tmp.name).resolve();self.root=self.base/'g4c-first';self.state=self.root/'signed60/edge'
        self.run=self.state/'live-g4-transport';self.run.mkdir(parents=True)
        self.super=self.base/'super';self.super.mkdir()
        self.asset=str(uuid.uuid4());self.aid='a'*32;self.package='c'*64
        self.scope={'case':'g4c','family':'edge','root':str(self.root)}
        self.target=gui_sample.digest(['birth','window','tab','entry',1,'source',self.package])
        self.claim={'case':'g4c','family':'edge','nonce':'nonce','attemptID':self.aid,'targetKey':self.target,'dmgSHA256':self.package}
        self.term=self.super/('terminal-'+self.aid+'.json')
        j=lambda p,v:p.write_text(json.dumps(v))
        self.j=j
        j(self.base/'active-scope.json',self.scope);j(self.root/'business-claim.json',self.claim)
        j(self.base/'build60-supervisor-owner.json',{'state':str(self.super),'dmgSHA256':self.package})
        j(self.term,dict(self.claim,outcome='INCONCLUSIVE'))
        j(self.state/'before.json',{'windowIDs':['personal'],'sessionID':'birth'})
        j(self.state/'creation.json',{'phase':'qaAddressConfirmed','sessionID':'birth','windowID':'window','tabID':'tab'})
        j(self.state/'original-entry.json',{'entryID':'entry','timeOrigin':1,'sourceDoc':'source'})
        j(self.run/'child.json',{'pid':12345,'profile':self.asset,'candidate':{'sha256':self.package}})
        j(self.run/'result.json',{'privateChildExited':False,'resumeMode':'ORIGINAL_READ_ONLY'})
        j(self.run/'observation-handoff.json',{'issued':True,'noReplay':True,'profile':self.asset,'pid':12345})
        j(self.run/'final-page.json',{'originalDocument':True,'originalEditor':True,'counts':{'fileInput':1,'fileChange':1,'sendButtonClicks':0,'formSubmit':0}})
        j(self.run/'final-db.json',{'operations':[{'id':'original'}]})
    def park(self):
        m=gui_park.proposal(self.base,self.scope)
        return gui_park.install(self.base,self.scope,m,gui_control.write_new)
    def test_old_document_original_private_profile_and_receipts_are_immutable(self):
        hashes={p:gui_park.hash_file(p) for p in self.state.rglob('*.json')}
        p=self.park();self.assertTrue(p.is_file());self.assertFalse((self.base/'active-scope.json').exists())
        self.assertEqual(gui_sample.read(self.root/'preserved-scope.json'),self.scope)
        self.assertTrue(gui_park.excludes(self.base,task='g4c'));self.assertTrue(gui_park.excludes(self.base,target=self.target))
        self.assertFalse(gui_park.excludes(self.base,task='g1',target='fresh-other'))
        self.assertEqual(hashes,{p:gui_park.hash_file(p) for p in self.state.rglob('*.json')})
        self.assertEqual(gui_sample.read(p)['originalPrivateProfile'],self.asset)
    def test_crash_between_marker_and_active_pointer_retirement_recovers(self):
        m=gui_park.proposal(self.base,self.scope);idx=self.base/'parked';idx.mkdir()
        gui_control.write_new(idx/(self.aid+'.json'),m);os.link(self.base/'active-scope.json',self.root/'preserved-scope.json')
        self.park();self.assertFalse((self.base/'active-scope.json').exists());self.assertTrue((self.state/'original-entry.json').is_file())
    def test_changed_term_attempt_or_target_is_never_parked(self):
        self.j(self.term,dict(self.claim,targetKey='e'*64,outcome='INCONCLUSIVE'))
        self.assertIsNone(gui_park.logical(self.base,self.scope))
    def test_unissued_or_zero_input_scope_stays_active_on_stable_environment(self):
        q=self.run/'final-page.json';p=gui_sample.read(q);p['counts']['fileInput']=p['counts']['fileChange']=0;self.j(q,p)
        self.assertIsNone(gui_park.logical(self.base,self.scope));self.assertTrue((self.base/'active-scope.json').is_file())
        self.term.unlink();self.assertIsNone(gui_park.logical(self.base,self.scope))
    def test_active_child_needs_a_scoped_no_replay_read_only_handoff(self):
        (self.run/'observation-handoff.json').unlink()
        self.assertIsNone(gui_park.logical(self.base,self.scope));self.assertTrue((self.base/'active-scope.json').is_file())
    def test_native_target_replacement_is_rejected(self):
        q=self.state/'creation.json';p=gui_sample.read(q);p['windowID']='other';self.j(q,p)
        self.assertIsNone(gui_park.logical(self.base,self.scope))
    def test_parked_candidate_cannot_be_selected_by_the_next_new_case(self):
        self.park()
        self.assertTrue(gui_park.excludes(self.base,task='b4',target=self.target));self.assertFalse(gui_park.excludes(self.base,task='b4',target='e'*64))
    def test_size_case_with_exited_candidate_still_preserves_the_original(self):
        self.scope['case']='b4';self.claim['case']='b4';self.j(self.base/'active-scope.json',self.scope);self.j(self.root/'business-claim.json',self.claim);self.j(self.term,dict(self.claim,outcome='INCONCLUSIVE'))
        self.run=self.run.rename(self.state/'live-size-60');self.j(self.run/'result.json',{'privateChildExited':True,'leaveOriginalWatcherForIndependentRecovery':True})
        self.assertEqual(gui_sample.read(self.park())['case'],'b4')
    def test_transition_log_keeps_contexts_separate_and_redacts_unknown_fields(self):
        checks=dict.fromkeys(gui_sample.CHECKS,False)
        env={'frontBundle':'fixture','frontPID':12,'frontAX':[{'role':'AXWindow','subrole':'AXDialog','modal':False,'title':'PRIVATE_NEVER_RECORDED'}],'displayAwake':True,'onConsole':True,'loginDone':True,'axTrusted':False,'browsers':{'edge':{'running':True,'aePermission':'CONSENT_REQUIRED'}}}
        for _ in range(2):gui_telemetry.journal(self.base,'edge',env,checks,None,True,'Aqua',None,'REGISTERED_AQUA_SUPERVISOR')
        gui_telemetry.journal(self.base,'edge',env,checks,None,True,'Aqua',None,'OTHER_PROCESS')
        env['axTrusted']=True;gui_telemetry.journal(self.base,'edge',env,checks,None,True,'Aqua',None,'REGISTERED_AQUA_SUPERVISOR')
        import sqlite3
        with sqlite3.connect(self.base/'host-observations.sqlite') as db:
            rows=db.execute('select context,metadata from transitions order by id').fetchall()
        self.assertEqual(len(rows),3);self.assertEqual(json.loads(rows[-1][1])['failure'],'APPLE_EVENTS_CONSENT_REQUIRED')
        self.assertTrue(all('PRIVATE_NEVER_RECORDED' not in row[1] for row in rows))
if __name__=='__main__':unittest.main()
