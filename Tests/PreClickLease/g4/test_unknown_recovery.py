"""Independent copies of a temporary synthetic G4-C SQLite pair."""
import base64
from contextlib import closing
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from test_recovery import key, sample, store
from verify_unknown_recovery import verify_files


PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC')


def pair(root, previous_start=False, retired=False):
    old,new,image = sample(previous_start)
    image.update(byteCount=len(PNG), sha256=hashlib.sha256(PNG).hexdigest())
    for op in (old,new):
        for record in (op['call'],op['start'],op['receipt']):
            if record is None:
                continue
            record['target'].update(adapterID='chatgpt-web',surface='webChat')
            record['assetSHA256'] = image['sha256']
    old['receipt'].update(hasError=False,safeToRetry=False,positiveReady=False,outcome='inputTriggered')
    del old['receipt']['attachmentID']
    old['receipt'].pop('originalCardFailureInvocationID',None)
    old['receipt']['reason']='fixture observed file input'
    old['call']['returnedReceipt'] = deepcopy(old['receipt'])
    new['call']['returnedReceipt'] = deepcopy(new['receipt'])
    png = root/'original.png'
    png.write_bytes(PNG)
    ids = [old['id'],new['id']]
    for path,include_new in [(root/'old.sqlite',False),(root/'new.sqlite',True)]:
        with store([old,new] if include_new else [old],image) as m, closing(sqlite3.connect(path)) as db:
            m.commit()
            m.backup(db)
            for field in ('sequence INTEGER','target_key TEXT','created_at REAL','updated_at REAL DEFAULT 10',
                          'reason TEXT','dispatch_exclusive INTEGER DEFAULT 0'):
                db.execute('ALTER TABLE operations ADD COLUMN ' + field)
            db.execute("UPDATE operations SET sequence=attempt,target_key=target_json,created_at=1")
            for field in ('source_key TEXT','file_name TEXT'):
                db.execute('ALTER TABLE assets ADD COLUMN ' + field)
            db.execute("UPDATE assets SET source_key='fixture',file_name='fixture.png'")
            db.execute('CREATE TABLE attachment_reselections(successor_id PRIMARY KEY,predecessor_id)')
            if retired:
                retired_id = 'BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB'
                db.execute('INSERT INTO operations(id,asset_id,attempt,phase,target_json,receipt_json,updated_at) SELECT ?,asset_id,2,?,target_json,NULL,11 FROM operations WHERE id=?',
                           (retired_id,'failed',old['id']))
                db.execute('INSERT INTO attachment_reselections VALUES(?,?)',(retired_id,old['id']))
            if include_new:
                db.execute('INSERT INTO attachment_reselections VALUES(?,?)',(new['id'],old['id']))
                if retired:
                    call = deepcopy(new['call'])
                    call['attempt'] = call['returnedReceipt']['attempt'] = 3
                    db.execute('UPDATE checkpoints SET value=? WHERE key=?',(base64.b64encode(json.dumps(call).encode()),
                        'transfer-dispatch-call-v1:'+new['id']))
                    receipt = dict(new['receipt'],attempt=3)
                    db.execute('UPDATE operations SET attempt=3,receipt_json=? WHERE id=?',(json.dumps(receipt),new['id']))
                    db.execute('UPDATE upload_starts SET receipt_json=? WHERE operation_id=?',(json.dumps(receipt),new['id']))
            db.execute('PRAGMA user_version=7')
            db.commit()
    return root/'old.sqlite',root/'new.sqlite',png,*ids


class UnknownRecoveryTests(unittest.TestCase):
    def test_clean_unmodified_backups(self):
        for started, retired in [(False,False),(True,False),(False,True)]:
            with self.subTest(original_start=started,retired=retired), tempfile.TemporaryDirectory() as folder:
                files = pair(Path(folder),started,retired)
                before = [p.read_bytes() for p in files[:3]]
                result = verify_files(*files)
                self.assertEqual([p.read_bytes() for p in files[:3]], before)
                self.assertEqual(result['originalLatestOutcome'],'inputTriggered')
                self.assertEqual(result['originalSTARTs'],int(started))
                self.assertEqual(result['addedAttachmentAcceptedSTARTs'],1)
                self.assertEqual(result['beforeSHA256'],hashlib.sha256(before[0]).hexdigest())

    def test_snapshot_and_ledger_refusals(self):
        cases = [
            ('named-error', 'both', "UPDATE operations SET receipt_json=json_set(receipt_json,'$.hasError',json('true'),'$.outcome','unknown','$.originalCardFailureInvocationID',?) WHERE id=?", ('old','old')),
            ('missing-new-START','after','DELETE FROM upload_starts WHERE operation_id=?',('new',)),
            ('updated-old-timestamp','after','UPDATE operations SET updated_at=22 WHERE id=?',('old',)),
            ('changed-old-receipt-encoding','after',"UPDATE operations SET receipt_json=' ' || receipt_json WHERE id=?",('old',)),
            ('changed-old-START','after','UPDATE upload_starts SET started_at=2 WHERE operation_id=?',('old',)),
            ('changed-old-call','after',"UPDATE checkpoints SET value=? WHERE key='transfer-dispatch-call-v1:' || ?",('invalid-b64','old')),
            ('missing-link','after','DELETE FROM attachment_reselections',()),
            ('wrong-link','after','UPDATE attachment_reselections SET predecessor_id=?',('new',)),
            ('extra-link','after','INSERT INTO attachment_reselections VALUES(?,?)',('extra','old')),
            ('extra-operation','after','INSERT INTO operations(id,asset_id,attempt,phase,target_json,receipt_json,updated_at) SELECT ?,asset_id,attempt,phase,target_json,receipt_json,updated_at FROM operations WHERE id=?',('extra','old')),
            ('extra-START','after','INSERT INTO upload_starts SELECT ?,receipt_json,started_at FROM upload_starts WHERE operation_id=?',('extra','old')),
            ('wrong-active','after','UPDATE assets SET active_operation_id=?',('old',)),
        ]
        for label,where,q,params in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as folder:
                files=pair(Path(folder),previous_start=True)
                values={'old':files[-2],'new':files[-1],'extra':key(),'invalid-b64':'invalid!'}
                for path in (files[:2] if where=='both' else [files[1]]):
                    with closing(sqlite3.connect(path)) as db:
                        db.execute(q,[values[k] for k in params]);db.commit()
                with self.assertRaises(ValueError):
                    verify_files(*files)

    def test_replaced_identity_in_every_new_record(self):
        for label in ('same-pin','same-pin-lowercase','changed-composer','changed-optional-draft','same-invocation','reused-start'):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as folder:
                files=pair(Path(folder),previous_start=True)
                with closing(sqlite3.connect(files[1])) as db:
                    def call(oid):
                        v=db.execute('SELECT value FROM checkpoints WHERE key=?',('transfer-dispatch-call-v1:'+oid,)).fetchone()[0]
                        return json.loads(base64.b64decode(v))
                    old,new=map(call,files[-2:])
                    new_id=files[-1]
                    target=new['target'].copy()
                    if label in ('same-pin','same-pin-lowercase'):
                        pin=old['target']['clickBindingID']
                        target['clickBindingID']=pin.lower() if label=='same-pin-lowercase' else pin
                    if label=='changed-composer': target['composerID']='other'
                    if label=='changed-optional-draft': target['historyConversationID']=key()
                    if label=='same-invocation': new['invocationID']=old['invocationID']
                    receipt=new['returnedReceipt']
                    if label=='reused-start':
                        prior=json.loads(db.execute('SELECT receipt_json FROM upload_starts WHERE operation_id=?',(files[-2],)).fetchone()[0])
                        receipt['attachmentAcceptanceEvidence']['evidenceID']=prior['attachmentAcceptanceEvidence']['evidenceID']
                    new['target']=receipt['target']=target
                    db.execute('UPDATE operations SET target_key=?,target_json=?,receipt_json=? WHERE id=?',(json.dumps(target),json.dumps(target),json.dumps(receipt),new_id))
                    db.execute('UPDATE upload_starts SET receipt_json=? WHERE operation_id=?',(json.dumps(receipt),new_id))
                    db.execute('UPDATE checkpoints SET value=? WHERE key=?',(base64.b64encode(json.dumps(new).encode()),'transfer-dispatch-call-v1:'+new_id))
                    db.commit()
                with self.assertRaises(ValueError):
                    verify_files(*files)

    def test_requires_distinct_backups_and_original_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            before,after,png,old,new=pair(Path(folder))
            with self.assertRaises(ValueError):
                verify_files(before,before,png,old,new)
            png.write_bytes(PNG+b'x')
            with self.assertRaises(ValueError):
                verify_files(before,after,png,old,new)


if __name__ == '__main__':
    unittest.main()
