import io
import json
import os
import subprocess
import sys
import unittest
import uuid
from pathlib import Path
from native_host import Gate, Refused, frame, read_frame, MAX_BYTES

def u(): return str(uuid.uuid4())
def d(): return uuid.uuid4().hex.upper()

class NativeTests(unittest.TestCase):
    def setUp(self):
        self.now = 100
        self.g = Gate(lambda: self.now)
        self.channel = u()
        self.g.receive({'v': 1, 'kind': 'hello', 'channel': self.channel})
        self.view = u(); self.seq = 0
        self.identity = dict(documentID=d(), documentNonce=u(), tabID=1, windowID=2, frameID=0)
    def msg(self, kind, **extras):
        self.seq += 1
        return dict(v=1, kind=kind, channel=self.channel, hostEpoch=self.g.host_epoch,
                    sequence=self.seq, viewEpoch=self.view, **extras)
    def publish(self):
        self.g.receive(self.msg('invalidate'))
        self.g.receive(self.msg('publish', phase='document_start', **self.identity))
    def freeze(self, event):
        return self.g.freeze(event, self.view, self.identity)['eligibleOriginalPublication']
    def test_pre_event_publication_can_be_candidate_not_input_authority(self):
        self.publish(); self.now = 200
        self.assertTrue(self.freeze(150))
        self.assertFalse(self.g.freeze(150,self.view,self.identity)['inputAuthority'])
    def test_startup_no_channel_cannot_be_repaired_by_late_publication(self):
        self.assertFalse(self.freeze(50)); self.publish(); self.now=200
        self.assertFalse(self.freeze(50)); self.assertFalse(self.freeze(100))
    def test_invalidation_rejects_queued_old_epoch_publication(self):
        self.publish(); old=self.view;self.view=u();self.g.receive(self.msg('invalidate'))
        message=self.msg('publish',phase='dom_ready',**self.identity);message['viewEpoch']=old
        with self.assertRaises(Refused):self.g.receive(message)
        self.assertIsNone(self.g.publication)
    def test_old_view_epoch_cannot_be_revived_by_ABA(self):
        self.publish();old=self.view;self.view=u();self.g.receive(self.msg('invalidate'));self.view=old
        with self.assertRaises(Refused):self.g.receive(self.msg('invalidate'))
        self.assertIsNone(self.g.publication)
    def test_document_change_requires_invalidation(self):
        self.publish();self.identity['documentID']=d()
        with self.assertRaises(Refused):self.g.receive(self.msg('publish',phase='dom_ready',**self.identity))
    def test_new_document_after_barrier_has_new_identity(self):
        self.publish();old=self.identity.copy();self.view=u();self.identity['documentID']=d();self.publish();self.now=200
        self.assertFalse(self.g.freeze(150,self.view,old)['eligibleOriginalPublication'])
        self.assertTrue(self.freeze(150))
    def test_worker_restart_cannot_reuse_host_epoch_or_sequence(self):
        self.publish();stale=self.msg('publish',phase='dom_ready',**self.identity)
        other=Gate();other.receive({'v':1,'kind':'hello','channel':u()})
        with self.assertRaises(Refused):other.receive(stale)
    def test_out_of_order_and_repeated_sequence_close_channel(self):
        for sequence in [0,2,True]:
            self.setUp();message=self.msg('invalidate');message['sequence']=sequence
            with self.assertRaises(Refused):self.g.receive(message)
            self.assertTrue(self.g.closed)
    def test_subframe_and_unknown_fields_are_rejected(self):
        for patch in [{'frameID':1},{'url':'do-not-collect'},{'originalEventNS':0}]:
            self.setUp();self.g.receive(self.msg('invalidate'))
            m=self.msg('publish',phase='document_start',**self.identity);m.update(patch)
            with self.assertRaises(Refused):self.g.receive(m)
    def test_browser_document_token_has_separate_exact_shape_from_UUID_nonces(self):
        for value in [u(), 'a'*31, 'g'*32, '0'*32, ' a'+'b'*30]:
            self.setUp();self.g.receive(self.msg('invalidate'))
            identity={**self.identity,'documentID':value}
            with self.assertRaises(Refused):self.g.receive(self.msg('publish',phase='document_start',**identity))
        self.setUp();self.publish()  # Uppercase exact 32-hex browser token is valid, preserved.
        self.assertEqual(self.g.publication['identity']['documentID'],self.identity['documentID'])
    def test_disconnect_and_expiry_remove_candidate(self):
        self.publish();self.now=600_000_000;self.assertFalse(self.freeze(self.now));self.g.close();self.assertFalse(self.freeze(self.now))
    def test_undelivered_invalidation_is_a_real_gap_not_solved_by_transport(self):
        self.publish();self.now=200
        # Remote navigation happened but IPC has not delivered invalidation.
        # Cache alone cannot know that; independent current identity still refuses.
        self.assertTrue(self.freeze(150))
        changed={**self.identity,'documentID':d()}
        self.assertFalse(self.g.freeze(150,self.view,changed)['eligibleOriginalPublication'])
    def test_native_framing_fragmentation_and_coalescing(self):
        class Fragmented(io.BytesIO):
            def read(self,n=-1):return super().read(min(n,1))
        a={'v':1,'kind':'hello','channel':u()};stream=Fragmented(frame(a)+frame(a))
        self.assertEqual(read_frame(stream),a);self.assertEqual(read_frame(stream),a);self.assertIsNone(read_frame(stream))
    def test_malformed_oversize_duplicate_utf8_truncated_rejected(self):
        raw=[b'{"v":1,"v":2}',b'\xff',b'{"v":NaN}']
        packets=[len(x).to_bytes(4,sys.byteorder)+x for x in raw]
        packets += [(MAX_BYTES+1).to_bytes(4,sys.byteorder),b'\x01',frame({'x':1})[:-1]]
        for p in packets:
            with self.assertRaises(Refused):read_frame(io.BytesIO(p))
    def test_real_stdio_host_framed_exchange_and_origin_refusal(self):
        origin='chrome-extension://'+'a'*32+'/'
        host=str(Path(__file__).with_name('native_host.py'))
        env={**os.environ,'RIFTLET_LAB_ORIGIN':origin}
        child=subprocess.run([sys.executable,host,origin],input=frame({'v':1,'kind':'hello','channel':self.channel}),
                             capture_output=True,env=env,timeout=3)
        self.assertEqual(child.returncode,0);self.assertEqual(child.stderr,b'')
        reply=read_frame(io.BytesIO(child.stdout));self.assertEqual(reply['kind'],'helloAck');self.assertFalse(reply['inputAuthority'])
        child=subprocess.run([sys.executable,host,origin+'wrong'],input=b'',capture_output=True,env=env,timeout=3)
        self.assertEqual(child.returncode,2);self.assertEqual(child.stdout,b'')

if __name__=='__main__':unittest.main()
