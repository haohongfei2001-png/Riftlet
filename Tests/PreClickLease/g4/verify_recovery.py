"""Verify a named original-card failure and one explicit recovery using two QA backups."""
import argparse
import json
from pathlib import Path

from audit_history import ATTACHMENT_PROFILE, START_PROFILE, require
from recovery_snapshot import DRAFT_KEYS, classify_error, read_operation, snapshot, verify_file_pair
from verify_unknown_recovery import verify as verify_v7


def verify(db_before, db_after, png, original, recovered):
    return verify_v7(db_before, db_after, png, original, recovered, named_error=True)


def verify_legacy(db_before, db_after, png, original, recovered):
    version = db_before.execute('PRAGMA user_version').fetchone()[0]
    require(db_after.execute('PRAGMA user_version').fetchone() == (version,), 'Mismatched snapshot versions')
    require(0 <= version < 7, 'Expected historical pre-recovery schema')
    old = read_operation(db_before, original, png)
    ordering = classify_error(old)
    require(old == read_operation(db_after, original, png), 'Original operation, invocation, error or START changed')
    before = {r[0] for r in db_before.execute('SELECT id FROM operations')}
    after = {r[0] for r in db_after.execute('SELECT id FROM operations')}
    require(recovered not in before and after == before | {recovered}, 'Expected one additional operation')
    new = read_operation(db_after, recovered, png)
    a, b = old['identity'], new['identity']
    require(new['start'] is not None and not new['receipt'].get('hasError') and a['assetID'] == b['assetID'] and
            b['attempt'] == a['attempt'] + 1 and new['call']['invocationID'] != old['call']['invocationID'] and
            a['target']['clickBindingID'] != b['target']['clickBindingID'] and
            all(a['target'][k] == b['target'][k] for k in DRAFT_KEYS) and
            new['start']['attachmentID'] != old['receipt']['attachmentID'], 'Recovery identity mismatch')
    require(db_before.execute('SELECT active_operation_id FROM assets WHERE id=?', (a['assetID'],)).fetchone() ==
            (original,) and db_after.execute('SELECT active_operation_id FROM assets WHERE id=?', (a['assetID'],)).fetchone()
            == (recovered,), 'Unexpected active operation')
    return {'scope':'historical build 59 SQLite and PNG only', 'errorObserved':ordering, 'newOriginalSTARTs':1}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--legacy-build59', action='store_true', help='Check a historical pre-v7 pair')
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('original_png', type=Path)
    parser.add_argument('old_operation')
    parser.add_argument('new_operation')
    args = parser.parse_args()
    print(json.dumps(verify_file_pair(args.before, args.after, args.original_png,
                                      args.old_operation, args.new_operation,
                                      verify_legacy if args.legacy_build59 else verify), indent=2))
