"""Independent copies of a temporary synthetic G4-C SQLite pair."""
import base64
from contextlib import closing, contextmanager
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from test_recovery import key, sample, store
from recovery_snapshot import verify_file_pair
from verify_recovery import verify as verify_named
from verify_unknown_recovery import verify_files


PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC')


@contextmanager
def edit_fixture(path):
    """Construct counterexamples in disposable test files with the original guards restored."""
    with closing(sqlite3.connect(path)) as db:
        triggers = list(db.execute("SELECT name,sql FROM sqlite_master WHERE type='trigger'"))
        for name, _ in triggers:
            db.execute('DROP TRIGGER ' + name)
        yield db
        for _, sql in triggers:
            db.execute(sql)
        db.commit()


def pair(root, previous_start=False, retired=False, named_error=False, before_version=7):
    old,new,image = sample(previous_start)
    image.update(byteCount=len(PNG), sha256=hashlib.sha256(PNG).hexdigest())
    for op in (old,new):
        for record in (op['call'],op['start'],op['receipt']):
            if record is None:
                continue
            record['target'].update(adapterID='chatgpt-web',surface='webChat')
            record['assetSHA256'] = image['sha256']
    if not named_error:
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
            db.execute('CREATE UNIQUE INDEX test_operation_id ON operations(id)')
            db.execute('''CREATE TABLE attachment_reselections(
                successor_id TEXT PRIMARY KEY NOT NULL REFERENCES operations(id) DEFERRABLE INITIALLY DEFERRED,
                predecessor_id TEXT NOT NULL REFERENCES operations(id), CHECK(successor_id != predecessor_id))''')
            db.execute('''CREATE TABLE compensations(
                operation_id TEXT PRIMARY KEY REFERENCES operations(id), evidence_json TEXT NOT NULL)''')
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
            version = 7 if include_new else before_version
            if version == 7:
                db.executescript(Path(__file__).with_name('test_schema7.sql').read_text())
            else:
                db.execute("CREATE UNIQUE INDEX one_unresolved_per_asset ON operations(asset_id) WHERE phase NOT IN ('failed','succeeded')")
            db.execute('PRAGMA user_version=' + str(version))
            db.commit()
    return root/'old.sqlite',root/'new.sqlite',png,*ids


class UnknownRecoveryTests(unittest.TestCase):
    def test_first_confirmed_reselection_migrates_on_commit(self):
        for version in (4, 5, 6):
            for named in (True, False):
                with self.subTest(initial=version, named=named), tempfile.TemporaryDirectory() as folder:
                    files = pair(Path(folder), named_error=named, before_version=version)
                    proof = verify_file_pair(*files, audit=verify_named) if named else verify_files(*files)
                    self.assertEqual((proof['beforeSchema'], proof['afterSchema']), (version, 7))

    def test_incomplete_recovery_schemas_and_compensations_are_refused(self):
        cases = [
            ('post-version', 1, 'PRAGMA user_version=4', ()),
            ('pre-relations', 0, 'DROP TABLE attachment_reselections', ()),
            ('post-guard', 1, 'DROP TRIGGER preserve_recovery_call', ()),
            ('old-compensation', 1, 'INSERT INTO compensations VALUES(?,?)', None),
        ]
        for label, index, statement, params in cases:
            for named in (True, False):
                with self.subTest(case=label, named=named), tempfile.TemporaryDirectory() as folder:
                    files = pair(Path(folder), named_error=named, before_version=4)
                    with closing(sqlite3.connect(files[index])) as db:
                        db.execute(statement, params if params is not None else (files[-2], '{}'))
                        db.commit()
                    with self.assertRaises(ValueError):
                        if named:
                            verify_file_pair(*files, audit=verify_named)
                        else:
                            verify_files(*files)

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

    def test_v7_named_recovers_after_original_and_preserved_retired_attempt(self):
        for started in (False, True):
            for retired in (False, True):
                with self.subTest(started=started, retired=retired), tempfile.TemporaryDirectory() as folder:
                    files = pair(Path(folder), started, retired, named_error=True)
                    record = verify_file_pair(*files, audit=verify_named)
                    self.assertEqual(record['errorObserved'], 'afterSTART' if started else 'beforeSTART')
                    self.assertEqual(record['addedPredecessorLinks'], 1)
                    self.assertEqual(record['newOriginalSTARTs'], 1)
                    with self.assertRaises(ValueError):
                        verify_files(*files)

    def test_v7_named_refuses_mutated_history_extra_start_or_missing_link(self):
        cases = {
            'old-time': 'UPDATE operations SET created_at=created_at+10 WHERE id=?',
            'old-reason': "UPDATE operations SET reason='replaced historical reason' WHERE id=?",
            'old-checkpoint': "UPDATE checkpoints SET value=value || ' ' WHERE key='transfer-dispatch-call-v1:' || ?",
            'missing-link': 'DELETE FROM attachment_reselections WHERE predecessor_id=?',
            'extra-start': "INSERT INTO upload_starts SELECT 'unrelated',receipt_json,started_at FROM upload_starts WHERE operation_id=?",
        }
        for label, statement in cases.items():
            with self.subTest(case=label), tempfile.TemporaryDirectory() as folder:
                files = pair(Path(folder), previous_start=True, named_error=True)
                with edit_fixture(files[1]) as db:
                    db.execute(statement, (files[-2],))
                    db.commit()
                with self.assertRaises(ValueError):
                    verify_file_pair(*files, audit=verify_named)

    def test_named_dispatch_must_identify_its_own_error_and_original_card(self):
        for field in ('attachmentID', 'originalCardFailureInvocationID'):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as folder:
                files = pair(Path(folder), named_error=True)
                checkpoint = 'transfer-dispatch-call-v1:' + files[-2]
                replacement = key()
                for path in files[:2]:
                    with edit_fixture(path) as db:
                        encoded, = db.execute('SELECT value FROM checkpoints WHERE key=?', (checkpoint,)).fetchone()
                        call = json.loads(base64.b64decode(encoded))
                        call['returnedReceipt'][field] = replacement
                        encoded = base64.b64encode(json.dumps(call).encode())
                        db.execute('UPDATE checkpoints SET value=? WHERE key=?', (encoded, checkpoint))
                        db.commit()
                with self.assertRaisesRegex(ValueError, 'different card|failure invocation'):
                    verify_file_pair(*files, audit=verify_named)

    def test_successor_returned_start_matches_durable_start(self):
        for field in ('attachmentID', 'evidenceID'):
            for named in (True, False):
                with self.subTest(field=field, named=named), tempfile.TemporaryDirectory() as folder:
                    files = pair(Path(folder), named_error=named)
                    checkpoint = 'transfer-dispatch-call-v1:' + files[-1]
                    with edit_fixture(files[1]) as db:
                        encoded, = db.execute('SELECT value FROM checkpoints WHERE key=?', (checkpoint,)).fetchone()
                        call = json.loads(base64.b64decode(encoded))
                        returned = call['returnedReceipt']
                        owner = returned if field == 'attachmentID' else returned['attachmentAcceptanceEvidence']
                        owner[field] = key()
                        db.execute('UPDATE checkpoints SET value=? WHERE key=?',
                                   (base64.b64encode(json.dumps(call).encode()), checkpoint))
                    with self.assertRaisesRegex(ValueError, 'disagrees with durable START'):
                        if named:
                            verify_file_pair(*files, audit=verify_named)
                        else:
                            verify_files(*files)

    def test_snapshot_and_ledger_refusals(self):
        cases = [
            ('named-error', 'both', "UPDATE operations SET receipt_json=json_set(receipt_json,'$.hasError',json('true'),'$.outcome','unknown','$.originalCardFailureInvocationID',?) WHERE id=?", ('old','old')),
            ('missing-new-START','after','DELETE FROM upload_starts WHERE operation_id=?',('new',)),
            ('updated-old-timestamp','after','UPDATE operations SET updated_at=22 WHERE id=?',('old',)),
            ('changed-old-receipt-encoding','after',"UPDATE operations SET receipt_json=' ' || receipt_json WHERE id=?",('old',)),
            ('changed-old-START','after','UPDATE upload_starts SET started_at=2 WHERE operation_id=?',('old',)),
            ('changed-old-call','after',"UPDATE checkpoints SET value=? WHERE key='transfer-dispatch-call-v1:' || ?",('invalid-b64','old')),
            ('missing-link','after','DELETE FROM attachment_reselections',()),
            ('wrong-link','after','UPDATE attachment_reselections SET successor_id=predecessor_id,predecessor_id=?',('new',)),
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
                    with edit_fixture(path) as db:
                        db.execute(q,[values[k] for k in params]);db.commit()
                with self.assertRaises(ValueError):
                    verify_files(*files)

    def test_replaced_identity_in_every_new_record(self):
        for label in ('same-pin','same-pin-lowercase','changed-composer','changed-optional-draft','same-invocation','reused-start'):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as folder:
                files=pair(Path(folder),previous_start=True)
                with edit_fixture(files[1]) as db:
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
