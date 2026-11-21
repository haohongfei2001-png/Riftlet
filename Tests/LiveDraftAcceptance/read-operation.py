#!/usr/bin/env python3
"""Export only the candidate/op/PNG-bound facts from an isolated QA QueueStore."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import plistlib
import re
import sqlite3
from uuid import UUID


def need(ok, message):
    if not ok:
        raise ValueError(message)


def read_operation(root, operation, png):
    root = root.resolve(strict=True)
    # Only the named isolated QA layout. Production history must never be enumerated.
    store = root / 'app-home/Library/Application Support/Riftlet/queue.sqlite'
    app = root / 'Riftlet-1.0.7-build53.app'
    need(store.is_file() and store.resolve() == store and app.resolve() == app, 'invalid isolated release layout')
    plist = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    exe = app / 'Contents/MacOS/Riftlet'
    need(plist['CFBundleIdentifier'] == 'com.riftlet.app' and plist['CFBundleVersion'] == '53'
         and sha256(exe.read_bytes()).hexdigest() == '73bea11151f9532c4ab2c3559f3b279e733dbade4c0f0e233e1c1627840e9667',
         'not the reviewed build 53 executable')
    need(re.fullmatch('[a-f0-9]{64}', png), 'invalid image digest')
    expected_id = str(UUID(operation)).upper()
    db = sqlite3.connect(store.as_uri() + '?mode=ro', uri=True)
    try:
        db.row_factory = sqlite3.Row
        row = db.execute("""
            SELECT o.id,o.attempt,o.target_json,o.receipt_json,o.phase,
                   o.updated_at - o.created_at AS elapsed, a.image_json,
                   (SELECT count(*) FROM upload_starts u WHERE u.operation_id=o.id) AS starts,
                   (SELECT min(u.started_at) - o.created_at FROM upload_starts u WHERE u.operation_id=o.id) AS stored_start_elapsed,
                   (SELECT count(*) FROM handled_attachments h WHERE h.operation_id=o.id) AS handled
            FROM operations o JOIN assets a ON a.id=o.asset_id WHERE o.id=?
        """, (expected_id,)).fetchone()
        need(row is not None, 'operation missing from isolated store')
        image, target, receipt = (json.loads(row[k]) for k in ('image_json','target_json','receipt_json'))
        need(image['sha256'] == png == receipt['assetSHA256'] and receipt['operationID'] == expected_id and
             receipt['attempt'] == row['attempt'] and target == receipt['target'], 'image/operation/receipt mismatch')
        needed = ('sessionID','windowID','tabID','documentID','composerID','draftGeneration','clickBindingID')
        need(all(target.get(key) for key in needed), 'receipt lacks a complete click identity')
        target_hash = sha256(json.dumps(target,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        # The independently locked page can compute this same tuple without
        # having the operation, receipt, click binding, or private store.
        draft_keys = ('applicationID','sessionID','windowID','tabID','documentID','composerID','draftGeneration')
        draft_hash = sha256(json.dumps([target[k] for k in draft_keys], ensure_ascii=False,
                                       separators=(',', ':')).encode()).hexdigest()
        # Retain a one-way reference to the target. Never print a conversation ID, text or URL.
        return dict(build='53',operation=expected_id, png=png, pixelWidth=image['pixelWidth'],
                    pixelHeight=image['pixelHeight'], byteCount=image['byteCount'], bundle=target['applicationID'],
                    targetSHA256=target_hash, lockedDraftSHA256=draft_hash, onSavedRoute=bool(target.get('historyConversationID')),
                    phase=row['phase'], attempted=row['attempt'], lastStoreUpdateSeconds=round(row['elapsed'],3),
                    receiptOutcome=receipt['outcome'], belongsToOriginalDraft=receipt['belongsToOriginalDraft'],
                    positiveReady=receipt['positiveReady'], safeToRetry=receipt['safeToRetry'],
                    hasError=receipt['hasError'], storedStartCount=row['starts'], storedStartAfterCreationSeconds=row['stored_start_elapsed'],
                    handledRows=row['handled'])
    finally:
        db.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('isolated_qa_root',type=Path)
    parser.add_argument('operation_id')
    parser.add_argument('original_png_sha256')
    args = parser.parse_args()
    print(json.dumps(read_operation(args.isolated_qa_root,args.operation_id,args.original_png_sha256),indent=2))
