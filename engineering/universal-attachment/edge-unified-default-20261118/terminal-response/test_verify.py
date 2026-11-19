"""Offline protocol/identity regression; all generated records are neutral fixtures."""
import hashlib,json,unittest
import verify
ID='file-NeutralRegression';HASH=hashlib.sha256(ID.encode()).hexdigest()
def frame(name,p,identifier=ID):return json.dumps({'event':'file.processing.'+name,'file_id':identifier,'progress':p},separators=(',',':')).encode()
def entity(*rows):return b'\n'.join(rows)+b'\n'
START=frame('started',0);READY=frame('file_ready',100);DONE=frame('completed',100);FAIL=frame('failed',80)
class ProtocolTests(unittest.TestCase):
 def check(self,raw,terminal='UNKNOWN',digest=HASH):
  d=verify.classify_entity(raw,digest);self.assertEqual(d['terminal'],terminal);return d
 def test_ndjson_complete(self):
  d=self.check(entity(START,READY,DONE),'FILE_PROCESSING_COMPLETED');self.assertEqual(d['format'],'NDJSON');self.assertEqual(d['sseDataLines'],0)
 def test_sse_complete(self):self.check(b''.join(b'data: '+r+b'\n\n' for r in [START,READY,DONE]),'FILE_PROCESSING_COMPLETED')
 def test_sse_crlf(self):self.check(b''.join(b'data: '+r+b'\r\n\r\n' for r in [START,READY,DONE]),'FILE_PROCESSING_COMPLETED')
 def test_sse_no_final_blank(self):self.check(b''.join(b'data: '+r+b'\n\n' for r in [START,READY])+b'data: '+DONE+b'\n')
 def test_sse_header_conflict(self):self.check(b''.join(b'data: '+r+b'\n\n' for r in [START,READY])+b'event: file.processing.failed\ndata: '+DONE+b'\n\n')
 def test_wrong_file(self):self.check(entity(START,READY,frame('completed',100,'file-OtherNeutral')))
 def test_wrong_digest(self):self.check(entity(START,READY,DONE),digest='a'*64)
 def test_truncated_json(self):self.check(entity(START,READY,DONE[:-3]))
 def test_no_ndjson_final_newline(self):self.check(entity(START,READY,DONE).rstrip())
 def test_completed_alone_not_complete_sequence(self):
  d=self.check(entity(DONE));self.assertTrue(d['completedFrameObserved']);self.assertFalse(d['completeKnownSequence'])
 def test_ready_or_100_not_completed(self):self.check(entity(START,READY))
 def test_status_ok_not_completion(self):self.check(b'{"status":"ok"}\n')
 def test_duplicate_event(self):self.check(entity(START,READY,DONE,DONE))
 def test_conflicting_final(self):self.check(entity(START,READY,DONE,FAIL))
 def test_duplicate_id_key(self):self.check(entity(START,READY,DONE.replace(b'"file_id":',b'"file_id":"file-OtherNeutral","file_id":')))
 def test_duplicate_progress_key(self):self.check(entity(START,READY,DONE.replace(b'"progress":',b'"progress":100,"progress":')))
 def test_boolean_progress(self):self.check(entity(START,READY,frame('completed',True)))
 def test_nonfinite(self):self.check(entity(START,READY,frame('completed',float('nan'))))
 def test_out_of_range(self):self.check(entity(START,READY,frame('completed',101)))
 def test_regression(self):self.check(entity(frame('started',40),frame('file_ready',20),DONE))
 def test_failure(self):self.check(entity(START,FAIL),'FILE_PROCESSING_FAILED')
 def test_bytes_bound(self):self.check(entity(START,READY,DONE)+b' '*16384)
 def test_empty(self):self.check(b'')
 def test_upstream_does_not_parse_ndjson(self):
  d=verify.replay_upstream(entity(START,READY,DONE));self.assertEqual(d['sseEventsByChunkPartition'],[0,0,0]);self.assertEqual(d['neutralSSEPositiveControl'],1)
 def test_upstream_accepts_standard_sse(self):
  d=verify.replay_upstream(b''.join(b'data: '+r+b'\n\n' for r in [START,READY,DONE]));self.assertEqual(d['sseEventsByChunkPartition'],[3,3,3])
if __name__=='__main__':unittest.main()
