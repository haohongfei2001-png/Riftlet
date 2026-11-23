"""Inspect offline QA database backups and their corresponding private PNG copies.

Usage: python3 audit_history.py BACKUP_DIRECTORY QA_PROFILES_PARENT
Prints only aggregate counts and evidence hashes. Never reports a website PASS.
"""
import base64
import collections
import hashlib
import json
import sqlite3
import sys
import uuid
from pathlib import Path
from contextlib import closing


ATTACHMENT_PROFILE = "chatgpt-web-product-system-attached-20261102-v1"
START_PROFILE = "chatgpt-web-product-system-start-20261102-v1"


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def audit(archive, profile_parent):
    by_browser = collections.defaultdict(collections.Counter)
    stores = sorted(archive.glob('*/queue.sqlite'))
    require(stores, 'Empty QA backup directory')
    reviewed = []
    for store in stores:
        profile_id = str(uuid.UUID(store.parent.name))
        root = profile_parent / ('Riftlet-PreClick-QA-' + profile_id)
        require((root / 'settings-review-identity.txt').read_text() == profile_id + '\n', 'Wrong QA profile')
        sidecars = [Path(str(store) + ext) for ext in ('-wal', '-journal')]
        require(store.resolve() == store and all(not p.exists() or p.stat().st_size == 0 for p in sidecars),
                'Closed standalone QA backup required')
        with closing(sqlite3.connect(store.as_uri() + '?immutable=1&mode=ro', uri=True)) as db:
            require(db.execute('PRAGMA quick_check').fetchone() == ('ok',), 'Invalid SQLite snapshot')
            images = {aid: json.loads(raw) for aid, raw in db.execute('SELECT id,image_json FROM assets')}
            ids = set()
            families = set()
            for oid, aid, attempt, raw_target, raw_receipt in db.execute(
                    'SELECT id,asset_id,attempt,target_json,receipt_json FROM operations'):
                target = json.loads(raw_target)
                family = {'com.google.Chrome':'Chrome','com.microsoft.edgemac':'Edge'}[target['applicationID']]
                families.add(family)
                stats = by_browser[family]
                stats['operations'] += 1
                checkpoint = db.execute('SELECT value FROM checkpoints WHERE key=?',
                                        ('transfer-dispatch-call-v1:' + oid,)).fetchone()
                require(checkpoint, 'Missing original dispatch checkpoint')
                call = json.loads(base64.b64decode(checkpoint[0], validate=True))
                require(call['target'] == target and call['operationID'] == oid and call['attempt'] == attempt and
                        call['assetID'] == aid and call['assetSHA256'] == images[aid]['sha256'],
                        'Dispatch identity mismatch')
                require(call['invocationID'] not in ids, 'Duplicate invocation in backup')
                ids.add(call['invocationID'])
                receipt = json.loads(raw_receipt) if raw_receipt else {}
                if receipt.get('hasError'):
                    stats['storedErrorReceipts'] += 1
                    if receipt.get('originalCardFailureInvocationID') == call['invocationID']:
                        stats['invocationBoundErrorReceipts'] += 1
                rows = db.execute('SELECT receipt_json FROM upload_starts WHERE operation_id=?', (oid,)).fetchall()
                require(len(rows) <= 1, 'Duplicate START')
                if rows:
                    start = json.loads(rows[0][0])
                    proof = start['attachmentAcceptanceEvidence']
                    require(start['outcome'] == 'uploadStarted' and start['target'] == target and
                            start['operationID'] == oid and start['assetID'] == aid and
                            start['attempt'] == attempt and start['assetSHA256'] == call['assetSHA256'] and
                            start['profileID'] == ATTACHMENT_PROFILE and proof['profileID'] == START_PROFILE and
                            start['belongsToOriginalDraft'] is True and proof['signal'] == 'attachmentAccepted' and
                            proof['inputCount'] == 1 and proof['evidenceID'], 'Invalid accepted START')
                    stats['originalStarts'] += 1
            require(len(families) == 1, 'Single-family backup expected')
            stats = by_browser[next(iter(families))]
            stats['profiles'] += 1
            for aid, img in images.items():
                filename = img['fileName']
                require(filename == Path(filename).name and filename.lower() == aid.lower() + '.png' and
                        img['origin'] == 'systemScreenshot', 'Unexpected QA media identity')
                media = root / 'media' / filename
                require(media == media.resolve(), 'Unexpected QA media path')
                data = media.read_bytes()
                require(data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) == img['byteCount'] and
                        digest(data) == img['sha256'], 'PNG byte mismatch')
                stats['verifiedPNGs'] += 1
        reviewed.append(digest(store.read_bytes()))
    return {'scope':'Offline build 59 QA archives and corresponding saved media only',
            'archiveSHA256':sorted(reviewed),
            'browsers':{f:{name:s[name] for name in ('profiles','operations','originalStarts','verifiedPNGs',
                        'storedErrorReceipts','invocationBoundErrorReceipts')} for f,s in sorted(by_browser.items())}}


if __name__ == '__main__':
    print(json.dumps(audit(*(Path(arg).resolve() for arg in sys.argv[1:])), indent=2))
