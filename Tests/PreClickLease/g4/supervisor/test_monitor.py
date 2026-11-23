import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import plistlib
import unittest
from unittest.mock import patch

import monitor as m


# The executable has no browser imports and writes only within a temporary fixture root.
FAKE = '''#!/usr/bin/env python3
import hashlib,json,os,sys,time
from pathlib import Path
p=Path(__file__).parent
act,family,*rest=sys.argv[1:]
options=json.loads((p/'options.json').read_text())
def record(row):
 with (p/'calls').open('a') as fp: fp.write(json.dumps(row)+'\\n')
if act=='sample':
 data=dict(options[family])
 if data.pop('broken',False): sys.exit(2)
 data.update(nonce=rest[0],family=family)
 if data.pop('stale',False):data['nonce']='stale'
 print(json.dumps(data))
else:
 task,nonce,*tail=rest
 assert os.path.samestat(os.fstat(int(os.environ['RIFTLET_GUI_LOCK_FD'])),os.stat(os.environ['RIFTLET_GUI_LOCK_PATH']))
 record([act,family,task])
 if act=='prepare':
  if options.get('afterPrepare'):
   options[family]=options['afterPrepare'];(p/'options.json').write_text(json.dumps(options))
  print('{}')
 else:
  claim=json.loads(Path(tail[0]).read_bytes())
  mode=options['terminal']
  if mode=='crash': sys.exit(9)
  if mode=='hold':
   (p/'host-in-flight').touch()
   deadline=time.monotonic()+10
   while not (p/'release').is_file() and time.monotonic()<deadline:time.sleep(0.01)
   if not (p/'release').is_file():sys.exit(9)
   mode='PASS'
  receipt={k:claim[k] for k in ('nonce','family','case','targetKey','attemptID','dmgSHA256')}
  receipt.update(outcome=mode,inputBoundaryEntered=False,productInputCount=0)
  if mode=='PASS':
   report=p/('evidence-'+claim['attemptID']);report.write_text('fixture')
   receipt.update(acceptanceEvidencePath=str(report),acceptanceEvidenceSHA256=hashlib.sha256(report.read_bytes()).hexdigest())
  if options.get('wrong'):receipt['targetKey']='f'*64
  t=Path(claim['terminalPath']);buf=json.dumps(receipt).encode();t.write_bytes(buf)
  print(json.dumps(dict(receipt,receiptPath=str(t),receiptSHA256=hashlib.sha256(buf).hexdigest())))
'''


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.state = self.root/'state'
        self.gui = self.root/'owner'/'gui.lock'
        self.host = self.root/'fixture-host'
        self.host.write_text(FAKE)
        self.host.chmod(0o700)
        self.db = m.db_open(self.state)
        m.configure(self.db,self.state,self.host,self.gui)
        self.options = {f:{'digest':hashlib.sha256(f.encode()).hexdigest(),'ready':False,
            'environment':{'eligibleForPreparation':False},'checks':{},'targetKey':None} for f in m.CASES}
        self.options['terminal']='PASS'

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def arm(self):
        with self.db:
            m.put(self.db,'armed','1')

    def ready(self,f='chrome',key='1'):
        self.options[f].update(ready=True,heldCase=m.CASES[f][0],targetKey=key*64,checks=dict.fromkeys(m.CHECKS,True))

    def tick(self):
        (self.root/'options.json').write_text(json.dumps(self.options))
        m.tick(self.state,self.db)

    def calls(self):
        p=self.root/'calls'
        return list(map(json.loads,p.read_text().splitlines())) if p.exists() else []

    def test_read_only_then_once_on_visible_origin(self):
        self.ready()
        self.tick()
        self.assertEqual(self.calls(),[])
        self.arm()
        for _ in range(3):
            self.tick()
        self.assertEqual(self.calls(),[['run','chrome','g1']])
        self.assertEqual(self.db.execute('SELECT status FROM attempts').fetchall(),[('PASS',)])
        self.assertEqual(self.db.execute("SELECT observations,valid FROM probes WHERE family='chrome'").fetchone(),(4,4))
        self.assertEqual(self.db.execute("SELECT count(*) FROM events WHERE kind='ENVIRONMENT'").fetchone()[0],2)

    def test_all_evidence_required_and_no_stale_sample(self):
        self.arm()
        self.ready()
        for key in m.CHECKS:
            self.options['chrome']['checks'][key]=False
            self.tick()
            self.options['chrome']['checks'][key]=True
        self.options['chrome']['stale']=True
        self.tick()
        self.assertEqual(self.calls(),[])

    def test_prepares_only_on_real_change(self):
        self.arm()
        probe=self.options['edge']
        probe['environment']['eligibleForPreparation']=True
        self.tick()
        self.tick()
        probe['broken']=True
        self.tick()
        del probe['broken']
        self.tick()
        self.assertEqual(self.calls(),[['prepare','edge','g2']])
        probe['digest']='d'*64
        self.tick()
        self.assertEqual(len(self.calls()),2)

    def test_prepare_and_admit_same_new_target_under_one_lease(self):
        self.arm()
        self.options['chrome']['environment']['eligibleForPreparation']=True
        self.options['afterPrepare']={'ready':True,'heldCase':'g1','digest':'e'*64,'targetKey':'f'*64,
            'checks':dict.fromkeys(m.CHECKS,True),'environment':{'eligibleForPreparation':True}}
        self.tick()
        self.assertEqual(self.calls(),[['prepare','chrome','g1'],['run','chrome','g1']])

    def test_copy_cannot_start_another_dispatcher(self):
        self.arm()
        self.ready()
        (self.root/'options.json').write_text(json.dumps(self.options))
        other=self.root/'copy'
        db2=m.db_open(other)
        try:
            self.db.backup(db2)
            m.tick(other,db2)
            self.assertEqual(self.calls(),[])
        finally:
            db2.close()

    def test_registered_persistent_store_recovers_missing_boot_marker(self):
        self.arm()
        self.ready()
        (self.gui.parent/'build60-supervisor-owner.json').unlink()
        self.tick()
        self.assertEqual(self.calls(),[['run','chrome','g1']])
        self.assertTrue((self.gui.parent/'build60-supervisor-owner.json').is_file())

    def test_gui_and_service_exclusion(self):
        self.arm()
        self.ready()
        with m.locked(self.gui):
            self.tick()
            self.assertEqual(self.calls(),[])
        with m.locked(self.state/'monitor.lock'):
            with self.assertRaisesRegex(ValueError,'ANOTHER_MONITOR'):
                m.loop(self.state,self.db,once=True)
        other=self.root/'alternate'
        db2=m.db_open(other)
        try:
            with self.assertRaisesRegex(ValueError,'ANOTHER_OR_LOST'):
                m.configure(db2,other,self.host,self.gui)
        finally:
            db2.close()

    def test_crash_and_other_families(self):
        self.arm()
        self.ready()
        self.options['terminal']='crash'
        self.tick()
        self.db.close()
        self.db=m.db_open(self.state)
        self.options['terminal']='PASS'
        self.options['chrome'].update(ready=False,heldCase=None)
        self.ready('edge','2')
        self.tick()
        self.tick() # never submit another suite on the positive/uncertain consumed target
        self.assertEqual(self.calls(),[['run','chrome','g1'],['run','edge','g2']])
        self.assertEqual(self.db.execute('SELECT status FROM attempts ORDER BY task').fetchall(),[('INCONCLUSIVE',),('PASS',)])
        self.options['edge'].update(targetKey='3'*64,heldCase='g4c')
        self.tick()
        self.assertEqual(self.calls()[-1],['run','edge','g4c'])

    def test_reconciles_only_original_terminal_after_crash(self):
        self.arm()
        self.ready()
        self.options['wrong']=True
        self.tick()
        self.assertEqual(self.db.execute('SELECT status FROM attempts').fetchone()[0],'INCONCLUSIVE')
        self.tick()
        self.assertEqual(len(self.calls()),1)
        claim=json.loads(next(self.state.glob('claim-*.json')).read_bytes())
        term=Path(claim['terminalPath'])
        receipt=json.loads(term.read_bytes())
        receipt.update(targetKey=claim['targetKey'],outcome='STOPPED_BEFORE_INPUT',inputBoundaryEntered=True)
        term.write_text(json.dumps(receipt))
        self.tick()
        self.assertEqual(self.db.execute('SELECT status FROM attempts').fetchone()[0],'INCONCLUSIVE')
        receipt['inputBoundaryEntered']=False
        term.write_text(json.dumps(receipt))
        self.tick()
        self.assertEqual(self.db.execute('SELECT status FROM attempts').fetchone()[0],'STOPPED_BEFORE_INPUT')
        self.assertEqual(len(self.calls()),1)
        del self.options['wrong']
        self.options['chrome']['digest']='a'*64
        self.tick()
        self.assertEqual(len(self.calls()),2)

    def test_crash_before_entering_external_host_proven(self):
        with self.db:
            self.db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,NULL)',('a','chrome','g1','b'*64,1,'CLAIMED'))
        self.tick()
        self.assertEqual(self.db.execute('SELECT status FROM attempts').fetchone()[0],'STOPPED_BEFORE_INPUT')

    def test_external_owner_handoff_blocks_duplicate_and_keeps_other_cases_running(self):
        evidence=self.root/'manual-input-receipt.json'
        evidence.write_text('{"fixture":true}')
        claim=m.adopt(self.state,self.db,'edge','g4c','2'*64,evidence)
        self.assertEqual(m.adopt(self.state,self.db,'edge','g4c','2'*64,evidence),claim)
        self.arm()
        self.ready('edge','2')
        self.options['edge']['heldCase']='g4c'
        self.tick()
        self.assertEqual(self.calls(),[])
        self.options['edge'].update(ready=False,heldCase=None)
        self.ready('chrome','1')
        self.tick()
        self.assertEqual(self.calls(),[['run','chrome','g1']])

    def test_target_changes_after_acquiring_gui_lease(self):
        self.arm()
        self.ready()
        orig=m.sample
        calls=0
        def race(db,family):
            nonlocal calls
            sample=orig(db,family)
            if family=='chrome':
                calls+=1
                if calls==2: sample.update(targetKey='f'*64)
            return sample
        with patch.object(m,'sample',side_effect=race):
            self.tick()
        self.assertEqual(self.calls(),[])

    def test_ready_edge_wins_over_chrome_prepare_and_contradiction_waits(self):
        self.arm()
        self.options['chrome']['environment']['eligibleForPreparation']=True
        self.ready('edge','2')
        self.ready('chrome','1')
        self.tick()
        self.assertEqual(self.calls(),[])
        self.options['chrome'].update(ready=False,heldCase=None)
        self.tick()
        self.assertEqual(self.calls(),[['run','edge','g2']])

    def test_killed_scheduler_leaves_gui_lease_with_original_child_and_reconciles(self):
        self.arm()
        self.ready()
        self.options['terminal']='hold'
        (self.root/'options.json').write_text(json.dumps(self.options))
        cli=[sys.executable,'-B',m.__file__,'--state',str(self.state),'run','--once']
        process=subprocess.Popen(cli,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+5
            while not (self.root/'host-in-flight').exists() and time.monotonic()<deadline:
                time.sleep(0.02)
            self.assertTrue((self.root/'host-in-flight').exists())
            process.kill()
            process.wait(timeout=2)
            with m.locked(self.gui) as claimed:
                self.assertIsNone(claimed)
            subprocess.run(cli,check=True,timeout=5)
            self.assertEqual(self.db.execute('SELECT status FROM attempts').fetchall(),[('CLAIMED',)])
            self.assertEqual(len(self.calls()),1)
            (self.root/'release').touch()
            deadline=time.monotonic()+3
            while not list(self.state.glob('terminal-*.json')) and time.monotonic()<deadline:
                time.sleep(0.02)
            subprocess.run(cli,check=True,timeout=5)
            self.assertEqual(self.db.execute('SELECT status FROM attempts').fetchall(),[('PASS',)])
            self.assertEqual(len(self.calls()),1)
        finally:
            (self.root/'release').touch()
            if process.poll() is None:
                process.kill()
            process.wait(timeout=2)

    def test_stop_resume_and_per_user_launch_definition(self):
        self.arm()
        self.ready()
        (self.root/'options.json').write_text(json.dumps(self.options))
        cli=[sys.executable,'-B',m.__file__,'--state',str(self.state)]
        for args in (['stop'],['run','--once']):
            subprocess.run([*cli,*args],check=True,timeout=5)
        self.assertEqual(self.calls(),[])
        job=plistlib.loads(subprocess.check_output([*cli,'plist'],timeout=5))
        self.assertEqual(job['LimitLoadToSessionType'],'Aqua')
        self.assertEqual(job['ProgramArguments'][-3:],['--state',str(self.state),'run'])
        for args in (['resume'],['run','--once']):
            subprocess.run([*cli,*args],check=True,timeout=5)
        self.assertEqual(self.calls(),[['run','chrome','g1']])

    def test_mutated_or_unavailable_host_never_dispatches(self):
        self.arm()
        self.ready()
        self.host.write_text(FAKE+'\n')
        self.tick()
        self.tick()
        self.assertEqual(self.calls(),[])


if __name__=='__main__':
    unittest.main()
