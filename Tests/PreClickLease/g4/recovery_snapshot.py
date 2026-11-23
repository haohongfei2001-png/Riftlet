"""Read original PNGs and standalone SQLite backups for the G4 acceptance tools."""
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


def file_digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            sha.update(block)
    return sha.hexdigest()


def verify_file_pair(before, after, original_png, original, recovered, audit):
    require(not before.samefile(after), 'Two separate standalone backups required')
    original, recovered = (str(UUID(k)).upper() for k in (original, recovered))
    hashes = [file_digest(p) for p in (before, after)]
    with snapshot(before) as first, snapshot(after) as second:
        result = audit(first, second, original_png.read_bytes(), original, recovered)
    require([file_digest(p) for p in (before, after)] == hashes, 'Snapshot changed during verification')
    return dict(result,beforeSHA256=hashes[0],afterSHA256=hashes[1])
