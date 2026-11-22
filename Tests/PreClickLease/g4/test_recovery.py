"""In-memory negative controls. No browser, files in a QA profile or product writes."""
import base64
import hashlib
import json
import sqlite3
import unittest
import uuid
from copy import deepcopy
from contextlib import closing

from verify_recovery import ATTACHMENT_PROFILE, START_PROFILE, verify


def key():
    return str(uuid.uuid4()).upper()


PNG = b'\x89PNG\r\n\x1a\nfixture'
SHA = hashlib.sha256(PNG).hexdigest()


def sample(late=False):
    old_id, new_id, asset = key(), key(), key()
    target = dict(applicationID='com.microsoft.edgemac', sessionID='s', windowID='w', tabID='t', documentID='d',
                  composerID='e', draftGeneration='g', clickBindingID=key())
    image = dict(id=asset, origin='systemScreenshot', mediaType='image/png', sha256=SHA, byteCount=len(PNG))
    def operation(oid, attempt, destination):
        identity = dict(operationID=oid, assetID=asset, target=destination, assetSHA256=SHA, attempt=attempt)
        call = dict(identity, version=1, invocationID=key(), inputExecutionReturned=True)
        start = dict(identity, outcome='uploadStarted', attachmentID=key(), belongsToOriginalDraft=True,
                     hasError=False, profileID=ATTACHMENT_PROFILE, attachmentAcceptanceEvidence=dict(version=1,
                     inputCount=1, signal='attachmentAccepted', evidenceID=key(), profileID=START_PROFILE))
        return {'id':oid, 'call':call, 'start':start, 'receipt':deepcopy(start), 'phase':'inputTriggered'}
    old = operation(old_id, 1, target)
    new = operation(new_id, 2, dict(target, clickBindingID=key()))
    old['phase'] = 'unknown'
    error = dict(old['receipt'], reason='observer-v2:failed:integratedDevelopment', outcome='unknown', hasError=True,
                 safeToRetry=False, positiveReady=False, isUploading=False)
    error.pop('attachmentAcceptanceEvidence')
    if not late:
        error['originalCardFailureInvocationID'] = old['call']['invocationID']
        old['start'] = None
    old['receipt'] = error
    return old, new, image


def store(rows, img):
    db = sqlite3.connect(':memory:')
    db.executescript('''CREATE TABLE operations(id,asset_id,attempt,phase,target_json,receipt_json);
        CREATE TABLE checkpoints(key,value);
        CREATE TABLE upload_starts(operation_id,receipt_json,started_at);
        CREATE TABLE assets(id,image_json,active_operation_id);''')
    db.execute('INSERT INTO assets VALUES(?,?,?)', (img['id'], json.dumps(img), rows[-1]['id']))
    for row in rows:
        c = row['call']
        db.execute('INSERT INTO operations VALUES(?,?,?,?,?,?)',
                   (row['id'], c['assetID'], c['attempt'], row['phase'], json.dumps(c['target']), json.dumps(row['receipt'])))
        db.execute('INSERT INTO checkpoints VALUES(?,?)', ('transfer-dispatch-call-v1:' + row['id'],
                                                           base64.b64encode(json.dumps(c).encode())))
        if row['start']:
            db.execute('INSERT INTO upload_starts VALUES(?,?,1)', (row['id'], json.dumps(row['start'])))
    return closing(db)


class RecoveryTests(unittest.TestCase):
    def verify(self, late, mutation=None):
        old,new,img = sample(late)
        if mutation:
            mutation(old, new)
        with store([old],img) as before, store([old, new],img) as after:
            return verify(before,after,PNG,old['id'],new['id'])

    def test_before_start(self):
        self.assertEqual(self.verify(False)['errorObserved'], 'beforeSTART')

    def test_after_start(self):
        self.assertEqual(self.verify(True)['errorObserved'], 'afterSTART')

    def test_refusals(self):
        negatives = [
            (False, lambda o,n: o['receipt'].pop('originalCardFailureInvocationID')),
            (True, lambda o,n: o['receipt'].update(originalCardFailureInvocationID=key())),
            (True, lambda o,n: o['receipt'].update(attachmentID=key())),
            (True, lambda o,n: o['receipt'].update(profileID='other')),
            (True, lambda o,n: o['receipt'].update(reason='observer-v2:unknown:integratedDevelopment')),
            (True, lambda o,n: o['receipt'].update(isUploading=True)),
            (False, lambda o,n: o['receipt'].update(safeToRetry=True)),
            (True, lambda o,n: o['start']['attachmentAcceptanceEvidence'].update(inputCount=2)),
            (True, lambda o,n: o['start'].update(profileID=START_PROFILE)),
            (True, lambda o,n: o['start']['attachmentAcceptanceEvidence'].update(profileID=ATTACHMENT_PROFILE)),
            (False, lambda o,n: o['receipt'].update(profileID=START_PROFILE)),
            (True, lambda o,n: n['call'].update(invocationID=o['call']['invocationID'])),
            (False, lambda o,n: n['call']['target'].update(draftGeneration='changed')),
            (False, lambda o,n: n['call'].update(assetSHA256='0'*64)),
            (False, lambda o,n: n['start'].update(attachmentID=o['receipt']['attachmentID'])),
        ]
        for i, (late, mutate) in enumerate(negatives):
            with self.subTest(case=i), self.assertRaises(ValueError):
                self.verify(late, mutate)

    def test_old_receipt_retained(self):
        old, new, image = sample(True)
        changed = deepcopy(old)
        changed['receipt']['reason'] = 'observer-v2:unknown:integratedDevelopment'
        with store([old],image) as before, store([changed, new],image) as after, self.assertRaises(ValueError):
            verify(before,after,PNG,old['id'],new['id'])


if __name__ == '__main__':
    unittest.main()
