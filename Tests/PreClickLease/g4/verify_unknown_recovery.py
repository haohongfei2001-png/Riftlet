"""Verify a G4-C explicit recovery using two standalone SQLite backups and the retained PNG.

Run verify_unknown_recovery.py BEFORE.sqlite AFTER.sqlite ORIGINAL.png OLD_UUID NEW_UUID.
The submitted before snapshot must precede the new selection. The after snapshot
must include the successor's durable attachmentAccepted START. This read-only audit
checks storage. Separate site and AppKit observations must establish disappearance,
the explicit selection, the original editor and actual input/change/send counts.
"""
import argparse
import base64
from collections import Counter
import hashlib
import json
from pathlib import Path
from uuid import UUID

from audit_history import ATTACHMENT_PROFILE, require
from recovery_snapshot import classify_error, file_digest, read_operation, snapshot, verify_file_pair


def rows(db, sql, params=()):
    # Preserve every SQLite value, including raw JSON text, timestamps and duplicates.
    return Counter(db.execute(sql, params))


def links(db):
    return rows(db, 'SELECT successor_id,predecessor_id FROM attachment_reselections')


def check_recovery_schema(db, version):
    guards = {
        'one_unresolved_per_asset': ('index', 'operations'),
        'unresolved_per_asset': ('index', 'operations'),
        'recovery_predecessor': ('index', 'attachment_reselections'),
        'single_unresolved_insert': ('trigger', 'operations'),
        'single_unresolved_update': ('trigger', 'operations'),
        'preserve_recovery_call': ('trigger', 'checkpoints'),
    }
    listed = {name: (kind, table) for kind, name, table in db.execute(
        "SELECT type,name,tbl_name FROM sqlite_master WHERE type IN ('index','trigger')") if name in guards}
    legacy = 'one_unresolved_per_asset'
    expected = {k: v for k, v in guards.items() if (k == legacy) == (version < 7)}
    require(listed == expected, 'Recovery schema disagrees with the declared version')
    index = legacy if version < 7 else 'unresolved_per_asset'
    indexes = {row[1]: (row[2], row[4]) for row in db.execute('PRAGMA index_list(operations)')}
    require(indexes[index] == (int(version < 7), 1) and
            [row[2] for row in db.execute('PRAGMA index_info(' + index + ')')] == ['asset_id'],
            'Unexpected unresolved-operation index')
    if version < 7:
        require(not links(db), 'Pre-migration recovery link already exists')
    else:
        require([row[2] for row in db.execute('PRAGMA index_info(recovery_predecessor)')] == ['predecessor_id'],
                'Incorrect predecessor index')


def check_receipt(operation):
    receipt = operation['receipt']
    require(receipt.get('profileID') == ATTACHMENT_PROFILE and receipt.get('belongsToOriginalDraft') is True and
            receipt.get('hasError') is False and not receipt.get('originalCardFailureInvocationID'),
            'Uncertain, foreign or named-error receipt')
    returned = operation['call'].get('returnedReceipt')
    if returned is not None:
        require(all(returned.get(k) == v for k, v in operation['identity'].items()) and
                returned.get('hasError') is False and not returned.get('originalCardFailureInvocationID'),
                'Contradictory append-return receipt')
        if returned.get('outcome') in ('uploadStarted', 'verifiedReady'):
            start = operation['start']
            require(start and returned.get('attachmentID') == start['attachmentID'],
                    'Returned attachment disagrees with durable START')
            evidence = returned.get('attachmentAcceptanceEvidence')
            if returned['outcome'] == 'uploadStarted' or evidence is not None:
                require(evidence == start['attachmentAcceptanceEvidence'],
                        'Returned attachment evidence disagrees with durable START')
    if receipt.get('outcome') == 'uploadStarted':
        start = operation['start']
        require(start and receipt.get('attachmentID') == start['attachmentID'] and
                receipt.get('attachmentAcceptanceEvidence') == start['attachmentAcceptanceEvidence'],
                'Current and durable START disagree')


def verify(before, after, png, original, recovered, *, named_error=False):
    require(original != recovered, 'Distinct operation IDs required')
    for db in (before, after):
        require(not db.execute('PRAGMA foreign_key_check').fetchall(), 'Broken snapshot references')
    before_version, after_version = (db.execute('PRAGMA user_version').fetchone()[0] for db in (before, after))
    require(before_version in (4, 5, 6, 7) and after_version == 7, 'Expected a committed build 61 recovery')

    required = {
        'operations': {'sequence','id','asset_id','attempt','target_key','target_json','phase','created_at',
                       'updated_at','receipt_json','reason','dispatch_exclusive'},
        'upload_starts': {'operation_id','receipt_json','started_at'},
        'checkpoints': {'key','value'},
        'assets': {'id','source_key','file_name','image_json','active_operation_id'},
        'attachment_reselections': {'successor_id','predecessor_id'},
        'compensations': {'operation_id','evidence_json'},
    }
    for table, fields in required.items():
        statement = 'PRAGMA table_info(' + table + ')'
        old_columns = tuple(row[1] for row in before.execute(statement))
        new_columns = tuple(row[1] for row in after.execute(statement))
        require(old_columns == new_columns and fields.issubset(old_columns), 'Incomplete ledger schema')
    check_recovery_schema(before, before_version)
    check_recovery_schema(after, after_version)
    require(rows(before, 'SELECT * FROM compensations') == rows(after, 'SELECT * FROM compensations') and
            not after.execute('SELECT 1 FROM compensations WHERE operation_id IN (?,?)', (original, recovered)).fetchone(),
            'Conflicting compensation history')

    old = read_operation(before, original, png)
    new = read_operation(after, recovered, png)
    ordering = None
    if named_error:
        ordering = classify_error(old)
        returned = old['call'].get('returnedReceipt')
        if returned is not None:
            require(all(returned.get(k) == v for k, v in old['identity'].items()),
                    'Named failure dispatch identity changed')
            named_invocation = returned.get('originalCardFailureInvocationID')
            if named_invocation is not None:
                require(UUID(named_invocation) == UUID(old['call']['invocationID']) and
                        returned.get('outcome') == 'unknown' and returned.get('hasError') is True and
                        returned.get('belongsToOriginalDraft') is True and returned.get('safeToRetry') is False and
                        returned.get('isUploading') is False and returned.get('positiveReady') is False,
                        'Contradictory returned failure invocation')
            reports_card_error = returned.get('hasError') is True and returned.get('attachmentID') is not None
            if named_invocation is not None or reports_card_error or returned.get('outcome') in ('uploadStarted', 'verifiedReady'):
                require(returned.get('attachmentID') == old['receipt']['attachmentID'],
                        'Returned receipt identifies a different card')
    else:
        check_receipt(old)
        require(old['phase'] == 'unknown' and old['receipt']['outcome'] in ('inputTriggered','unknown','uploadStarted') and
                old['receipt'].get('safeToRetry') is False and old['receipt'].get('positiveReady') is False,
                'Original operation is outside the UNKNOWN branch')
    check_receipt(new)
    for db, op in ((before, old), (after, new)):
        stored_target, exclusive = db.execute('SELECT target_key,dispatch_exclusive FROM operations WHERE id=?',
                                              (op['identity']['operationID'],)).fetchone()
        require(exclusive == 0 and json.loads(stored_target) == op['identity']['target'],
                'Wrong dispatch lane or native target key')
        t = op['identity']['target']
        require(t.get('adapterID') == 'chatgpt-web' and t.get('surface') == 'webChat' and
                UUID(t['clickBindingID']).int != 0 and UUID(op['call']['invocationID']).int != 0,
                'Incomplete product binding')
    require(new['phase'] in ('inputTriggered','attachmentPresent','succeeded') and new['start'] is not None and
            new['receipt']['outcome'] in ('uploadStarted','verifiedReady') and
            new['receipt'].get('attachmentID') == new['start']['attachmentID'],
            'Missing accepted successor')
    if named_error:
        require(new['start']['attachmentID'] != old['receipt']['attachmentID'], 'Reused failed attachment')
    if new['receipt']['outcome'] == 'verifiedReady':
        require(new['receipt'].get('positiveReady') is True and new['receipt'].get('isUploading') is False,
                'Incomplete successor READY observation')
    a, b = old['identity'], new['identity']
    asset = a['assetID']
    require(asset == b['assetID'] and UUID(old['call']['invocationID']) != UUID(new['call']['invocationID']),
            'Asset or invocation mismatch')
    old_target = a['target'].copy()
    new_target = b['target'].copy()
    old_pin = UUID(old_target.pop('clickBindingID'))
    new_pin = UUID(new_target.pop('clickBindingID'))
    require(old_target == new_target and old_pin != new_pin,
            'Expected the original draft and a new click binding')
    highest = before.execute('SELECT MAX(attempt) FROM operations WHERE asset_id=?', (asset,)).fetchone()[0]
    require(type(highest) is int and a['attempt'] <= highest and b['attempt'] == highest + 1,
            'Unexpected successor attempt')
    for (raw,) in before.execute("SELECT value FROM checkpoints WHERE key GLOB 'transfer-dispatch-call-v1:*'"):
        other = json.loads(base64.b64decode(raw, validate=True))
        require(UUID(other['invocationID']) != UUID(new['call']['invocationID']), 'Reused dispatch invocation')
    for (raw,) in before.execute('SELECT target_json FROM operations'):
        pin = json.loads(raw).get('clickBindingID')
        require(pin is None or UUID(pin) != UUID(b['target']['clickBindingID']), 'Reused click capability')
    for (raw,) in before.execute('SELECT receipt_json FROM upload_starts'):
        previous = json.loads(raw)
        evidence = previous.get('attachmentAcceptanceEvidence') or previous.get('uploadStartEvidence') or {}
        require(previous.get('attachmentID') != new['start']['attachmentID'] and
                evidence.get('evidenceID') != new['start']['attachmentAcceptanceEvidence']['evidenceID'],
                'Reused prior attachment or START')

    for db, active in ((before, original),(after, recovered)):
        require(db.execute('SELECT active_operation_id FROM assets WHERE id=?', (asset,)).fetchall() == [(active,)],
                'Unexpected active operation')
    require(rows(before,'SELECT id,source_key,file_name,image_json FROM assets') ==
            rows(after,'SELECT id,source_key,file_name,image_json FROM assets'),
            'Assets or immutable image descriptors changed')

    # A complete independent backup has exactly one new operation, dispatch call and START.
    for table, column, old_key, new_key in (
        ('operations','id',original,recovered),
        ('upload_starts','operation_id',original,recovered),
        ('checkpoints','key','transfer-dispatch-call-v1:'+original,'transfer-dispatch-call-v1:'+recovered),
    ):
        scope = " WHERE key GLOB 'transfer-dispatch-call-v1:*'" if table == 'checkpoints' else ''
        q = 'SELECT * FROM ' + table
        old_rows = rows(before, q + scope)
        new_rows = rows(after, q + scope)
        predecessor = q + ' WHERE ' + column + '=?'
        require(rows(before, predecessor, (old_key,)) == rows(after, predecessor, (old_key,)),
                'Original ledger row changed')
        addition = rows(after, predecessor, (new_key,))
        require(not rows(before, predecessor, (new_key,)) and sum(addition.values()) == 1 and
                new_rows == old_rows + addition, 'Unexpected change in ' + table)
    expected_link = (recovered, original)
    prior_links = links(before)
    require(expected_link not in prior_links and links(after) == prior_links + Counter([expected_link]),
            'Incorrect predecessor link')

    result = {'scope':'G4-C database and PNG only','beforeSchema':before_version,'afterSchema':after_version,
            'originalPhase':old['phase'],
            'originalLatestOutcome':old['receipt']['outcome'],'originalSTARTs':int(old['start'] is not None),
            'originalOperationReceiptSTARTAndCallIdentical':True,'sameDraftNewPin':True,
            'addedOperations':1,'addedInvocations':1,'addedAttachmentAcceptedSTARTs':1,
            'addedPredecessorLinks':1,'pngSHA256':a['assetSHA256'],
            'idSHA256UppercaseUTF8': {label:hashlib.sha256(str(UUID(value)).upper().encode()).hexdigest()
                for label,value in [('oldOperation',original),('newOperation',recovered),
                                    ('oldInvocation',old['call']['invocationID']),('newInvocation',new['call']['invocationID'])]}}
    if named_error:
        result.update(scope='G4-A database and PNG only', errorObserved=ordering, newOriginalSTARTs=1)
    return result


def verify_files(before, after, original_png, original, recovered):
    return verify_file_pair(before, after, original_png, original, recovered, verify)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('original_png', type=Path)
    parser.add_argument('old_operation')
    parser.add_argument('new_operation')
    args = parser.parse_args()
    print(json.dumps(verify_files(args.before,args.after,args.original_png,args.old_operation,args.new_operation),indent=2))
