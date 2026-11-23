"""Verify the SQLite portion of one build-59 G4 acceptance from offline QA snapshots."""
import argparse
import base64
import hashlib
import json
import sqlite3
from contextlib import closing, contextmanager
from pathlib import Path
from uuid import UUID

from audit_history import ATTACHMENT_PROFILE, START_PROFILE, require


@contextmanager
def snapshot(path):
    path = path.resolve(strict=True)
    for suffix in ('-wal', '-journal'):
        sidecar = Path(str(path) + suffix)
        require(not sidecar.exists() or sidecar.stat().st_size == 0, 'Standalone backup required')
    with closing(sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True)) as db:
        require(db.execute('PRAGMA quick_check').fetchone() == ('ok',), 'Invalid snapshot')
        yield db


DRAFT_KEYS = ('applicationID', 'sessionID', 'windowID', 'tabID', 'documentID', 'composerID', 'draftGeneration')


def read_operation(db, oid, png):
    rows = db.execute('''SELECT o.asset_id,o.attempt,o.phase,o.target_json,o.receipt_json,a.image_json
                         FROM operations o JOIN assets a ON a.id=o.asset_id WHERE o.id=?''', (oid,)).fetchall()
    require(len(rows) == 1, 'Missing original operation')
    asset, attempt, phase, target_json, receipt_json, image_json = rows[0]
    target = json.loads(target_json)
    image = json.loads(image_json)
    require(image['origin'] == 'systemScreenshot' and image['mediaType'] == 'image/png' and
            image['id'] == asset and png[:8] == b'\x89PNG\r\n\x1a\n' and image['byteCount'] == len(png) and
            image['sha256'] == hashlib.sha256(png).hexdigest(), 'PNG identity mismatch')
    require(target['applicationID'] in ('com.google.Chrome', 'com.microsoft.edgemac') and target['clickBindingID'] and
            all(target[key] for key in DRAFT_KEYS), 'Incomplete original draft binding')
    identity = dict(operationID=oid, assetID=asset, attempt=attempt, target=target, assetSHA256=image['sha256'])
    checkpoint = db.execute('SELECT value FROM checkpoints WHERE key=?', ('transfer-dispatch-call-v1:' + oid,)).fetchone()
    require(checkpoint, 'No dispatch checkpoint')
    call = json.loads(base64.b64decode(checkpoint[0], validate=True))
    require(UUID(call['invocationID']) and call['version'] == 1 and call['inputExecutionReturned'] is True,
            'No returned original invocation')
    receipt = json.loads(receipt_json)
    starts = db.execute('SELECT receipt_json,started_at FROM upload_starts WHERE operation_id=?', (oid,)).fetchall()
    require(len(starts) <= 1, 'Ambiguous START')
    start = json.loads(starts[0][0]) if starts else None
    for record in [call, receipt] + ([start] if start is not None else []):
        require(all(record.get(key) == value for key, value in identity.items()), 'Conflicting identities')
    if start is not None:
        evidence = start.get('attachmentAcceptanceEvidence') or {}
        require(start['outcome'] == 'uploadStarted' and start['belongsToOriginalDraft'] is True and
                start['hasError'] is False and start['attachmentID'] and start['profileID'] == ATTACHMENT_PROFILE and
                evidence.get('signal') == 'attachmentAccepted' and evidence.get('version') == 1 and
                type(evidence.get('inputCount')) is int and evidence['inputCount'] == 1 and
                evidence.get('evidenceID') and evidence.get('profileID') == START_PROFILE and not start.get('uploadStartEvidence'),
                'Missing original attachmentAccepted START')
    return dict(identity=identity, phase=phase, call=call, receipt=receipt, start=start,
                startedAt=starts[0][1] if starts else None)


def classify_error(old):
    receipt, start, call = old['receipt'], old['start'], old['call']
    require(old['phase'] == 'unknown' and receipt['outcome'] == 'unknown' and receipt['hasError'] is True and
            receipt['profileID'] == ATTACHMENT_PROFILE and receipt['belongsToOriginalDraft'] is True and receipt['safeToRetry'] is False and
            receipt['isUploading'] is False and receipt['positiveReady'] is False and receipt['attachmentID'] and
            not any(receipt.get(key) for key in ('uploadStartEvidence', 'attachmentAcceptanceEvidence',
                                                 'completionEvidence', 'continuationEvidence', 'terminationEvidence')),
            'No unambiguous original-card error receipt')
    failure_invocation = receipt.get('originalCardFailureInvocationID')
    if start is None:
        require(failure_invocation == call['invocationID'], 'Missing original failure invocation')
        return 'beforeSTART'
    require(failure_invocation is None or failure_invocation == call['invocationID'], 'Mismatched failure invocation')
    require(start['attachmentID'] == receipt['attachmentID'] and start['profileID'] == receipt['profileID'] and
            receipt['reason'].split(':')[:3] == ['observer-v2', 'failed', 'integratedDevelopment'],
            'Late error does not identify original accepted card')
    return 'afterSTART'


def accepted_successor_phase(operation):
    # Build 61 ordinarily leaves a positive handoff in inputTriggered.
    # Build 62 may close local observation with an unknown remote outcome.
    # read_operation validated the independent upload_starts row and its identity.
    if operation['phase'] == 'unknown':
        return operation['start'] is not None and operation['receipt'] == operation['start']
    return operation['phase'] in ('inputTriggered', 'attachmentPresent', 'succeeded')


def verify(db_before, db_after, png, original, recovered):
    old = read_operation(db_before, original, png)
    ordering = classify_error(old)
    require(old == read_operation(db_after, original, png), 'Original operation, invocation, error or START changed')
    before = {r[0] for r in db_before.execute('SELECT id FROM operations')}
    after = {r[0] for r in db_after.execute('SELECT id FROM operations')}
    require(recovered not in before and after == before | {recovered}, 'Expected one additional operation')
    new = read_operation(db_after, recovered, png)
    a, b = old['identity'], new['identity']
    require(accepted_successor_phase(new) and new['start'] is not None and
            not new['receipt'].get('hasError') and a['assetID'] == b['assetID'] and
            b['attempt'] == a['attempt'] + 1 and new['call']['invocationID'] != old['call']['invocationID'] and
            a['target']['clickBindingID'] != b['target']['clickBindingID'] and
            all(a['target'][k] == b['target'][k] for k in DRAFT_KEYS) and
            new['start']['attachmentID'] != old['receipt']['attachmentID'], 'Recovery identity mismatch')
    require(db_before.execute('SELECT active_operation_id FROM assets WHERE id=?', (a['assetID'],)).fetchone() ==
            (original,) and db_after.execute('SELECT active_operation_id FROM assets WHERE id=?', (a['assetID'],)).fetchone()
            == (recovered,), 'Unexpected active operation')
    return {'scope':'SQLite and PNG portion only', 'errorObserved':ordering, 'newOriginalSTARTs':1}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('original_png', type=Path)
    parser.add_argument('old_operation')
    parser.add_argument('new_operation')
    args = parser.parse_args()
    with snapshot(args.before) as before, snapshot(args.after) as after:
        print(json.dumps(verify(before, after, args.original_png.read_bytes(), str(UUID(args.old_operation)).upper(),
                                str(UUID(args.new_operation)).upper()), indent=2))
