"""No WindowServer, browser, Apple Event, or private session is needed for these controls."""
import hashlib,json,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import gui_control
import gui_sample

class CheckHost(unittest.TestCase):
    def setUp(self):
        self.scratch=tempfile.TemporaryDirectory();self.addCleanup(self.scratch.cleanup)
        self.base=Path(self.scratch.name).resolve();self.state=self.base/'g4c-first/signed60/edge';self.state.mkdir(parents=True)
        self.save=lambda path,obj:path.write_text(json.dumps(obj))
        self.save(self.base/'active-scope.json',{'family':'edge','case':'g4c','root':str(self.state.parent.parent)})
        self.save(self.base/'candidate.json',{'dmgSHA256':'d'*64})
        self.save(self.state/'original-entry.json',{'entryID':'e','timeOrigin':1,'sourceDoc':'owned'})
        self.orig={'pid':4,'birth':'birth','nativeWindowID':'w','nativeTabID':'t','systemForeground':True,
           'nativeVisible':True,'cgWindowOnScreen':True,'centerHitOriginalCG':True,'axOriginalWindow':True,
           'selected':True,'singleTab':True,'knownOriginalProcess':True}
        self.env={k:True for k in ('displayAwake','onConsole','loginDone','consoleUIDMatches','axTrusted','eligibleForPreparation')}
        self.env.update(frontBundle='fixture',systemDialogOnScreen=False,protectedForeground=False,frontHasModal=False,screenLocked=False,browsers={'edge':{'running':True,'aePermission':'ALLOWED'},'chrome':{'running':True,'aePermission':'ALLOWED'}})
        self.payload={'pid':4,'sessionID':'birth','windowID':'w','tabID':'t','family':'edge','exactTemporaryURL':True,
           'systemForeground':True,'originalSelection':True,'originalSoleTab':True,'dynamicSignature':True,
           'page':{'entryID':'e','timeOrigin':1,'editor':True,'uploadEntry':True,'signedIn':True,'observationState':{'focused':True,'visible':True}}}
    def obtain(self,f='edge'):
        import base64,types
        def cmd(args):
            if args[0].name=='observer':
                raw=json.dumps(self.payload).encode();return {'payload':self.payload,'payloadBase64':base64.b64encode(raw).decode(),'sha256':hashlib.sha256(raw).hexdigest()}
            return dict(self.env,original=self.orig)
        with patch.object(gui_sample,'command',cmd),patch.object(gui_sample,'journal'),patch.object(gui_sample.subprocess,'run',return_value=types.SimpleNamespace(stdout='Aqua\n')):
            return gui_sample.sample(self.base,self.base,f,'control')
    def test_source_case_label_never_grants_a_new_target(self):
        first=self.obtain();self.assertTrue(first['ready']);self.assertEqual(len(first['checks']),12)
        mark=self.base/'active-scope.json';j=json.loads(mark.read_text());j['case']='g2';self.save(mark,j)
        second=self.obtain();self.assertEqual(first['targetKey'],second['targetKey']);self.assertNotEqual(first['heldCase'],second['heldCase'])
    def test_window_layers_and_page_are_independent_requirements(self):
        for key in ['centerHitOriginalCG','cgWindowOnScreen','axOriginalWindow','nativeVisible','selected','systemForeground','knownOriginalProcess','singleTab']:
            self.orig[key]=False;self.assertFalse(self.obtain()['ready']);self.orig[key]=True
        for key in ['editor','signedIn','uploadEntry']:
            self.payload['page'][key]=False;self.assertFalse(self.obtain()['ready']);self.payload['page'][key]=True
        for key in ['visible','focused']:
            self.payload['page']['observationState'][key]=False;self.assertFalse(self.obtain()['ready']);self.payload['page']['observationState'][key]=True
    def test_disjoint_or_closed_scopes_are_not_held(self):
        self.assertIsNone(self.obtain('chrome')['heldCase']);(self.state/'closed.json').write_text('{}')
        result=self.obtain();self.assertIsNone(result['heldCase']);self.assertFalse(result['ready'])
    def test_wrong_original_route_zeroes_admission(self):
        self.payload['tabID']='replacement';self.assertFalse(self.obtain()['ready']);self.assertIsNone(self.obtain()['targetKey'])
    def test_same_attempt_receipt_never_overwritten(self):
        path=self.base/'terminal.json';gui_control.write_new(path,{'original':1})
        with self.assertRaises(FileExistsError):gui_control.write_new(path,{'replacement':1})
        self.assertEqual(json.loads(path.read_text()),{'original':1})
    def test_wrong_descriptor_rejected(self):
        path=self.base/'gui.lock';path.touch();other=self.base/'wrong';other.touch()
        with other.open() as f,patch.dict(os.environ,{'RIFTLET_GUI_LOCK_PATH':str(path),'RIFTLET_GUI_LOCK_FD':str(f.fileno())}):
            with self.assertRaisesRegex(ValueError,'WRONG_GUI_FD'):
                with gui_control.lease(self.base):pass
if __name__=='__main__':unittest.main()
