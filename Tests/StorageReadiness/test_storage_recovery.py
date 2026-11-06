"""Isolated real-filesystem/SQLite regressions. No App or production paths."""

import errno
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[2] / "scripts/storage-recovery.py"
spec = importlib.util.spec_from_file_location("riftlet_storage_recovery", SCRIPT)
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


def fingerprint(root):
    return {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}


def image_record(number, payload):
    identifier = str(uuid.UUID(int=number))
    return {"id": identifier.upper(), "sourceKey": "synthetic-source-" + str(number),
            "fileName": identifier + ".png", "sha256": hashlib.sha256(payload).hexdigest(),
            "byteCount": len(payload), "pixelWidth": 1, "pixelHeight": 1,
            "mediaType": "image/png", "firstSeenAt": 0, "importedAt": 0, "origin": "synthetic"}


def make_root(path, version=3):
    path.mkdir(mode=0o700)
    (path / "instance.lock").write_bytes(b"")
    for name in ("media", "journal", "staging", "captures", "opaque-empty", "Feedback-v01"):
        (path / name).mkdir()
    (path / "Feedback-v01/feedback.lock").write_bytes(b"")
    (path / "rift-configuration.json").write_text('{"fitWidth":96,"unknownFutureSetting":"retain"}')
    (path / "capture-entry-settings.json").write_text('{"version":1,"builtInScreenshotEnabled":false}')
    (path / "diagnostics.jsonl").write_bytes(b'{"event":"synthetic"}\n')
    db = sqlite3.connect(path / "queue.sqlite")
    # Independently written historical schema shape, not today's Swift migrator.
    db.executescript("""
        CREATE TABLE assets(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT UNIQUE NOT NULL,
            source_key TEXT UNIQUE NOT NULL,file_name TEXT UNIQUE NOT NULL,sort_at REAL NOT NULL,
            image_json TEXT NOT NULL,status TEXT NOT NULL,active_operation_id TEXT);
        CREATE TABLE operations(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT UNIQUE NOT NULL,
            asset_id TEXT REFERENCES assets(id),attempt INTEGER,target_key TEXT,target_json TEXT,
            phase TEXT,created_at REAL,updated_at REAL,receipt_json TEXT,reason TEXT);
        CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE checkpoints(key TEXT PRIMARY KEY,value BLOB NOT NULL);
        INSERT INTO metadata VALUES('mode','simulation');
        INSERT INTO metadata VALUES('capture_paused','true');
        INSERT INTO metadata VALUES('user_hidden','true');
        INSERT INTO checkpoints VALUES('synthetic-old-journal',X'0001FEFF');
        CREATE TABLE future_history(id INTEGER PRIMARY KEY,payload BLOB,note TEXT);
        INSERT INTO future_history VALUES(31,X'00027FFF','retain unknown columns and tables');
    """)
    if version >= 2:
        db.execute("CREATE TABLE compensations(operation_id TEXT PRIMARY KEY REFERENCES operations(id),evidence_json TEXT NOT NULL)")
    if version >= 3:
        db.executescript("""
            ALTER TABLE assets ADD COLUMN visibility TEXT DEFAULT 'visible';
            ALTER TABLE assets ADD COLUMN visibility_revision INTEGER DEFAULT 0;
            ALTER TABLE assets ADD COLUMN visibility_reason TEXT DEFAULT 'capture';
            ALTER TABLE assets ADD COLUMN last_interaction_at REAL DEFAULT 0;
            ALTER TABLE operations ADD COLUMN dispatch_exclusive INTEGER DEFAULT 1;
            CREATE TABLE upload_starts(operation_id TEXT PRIMARY KEY REFERENCES operations(id),receipt_json TEXT NOT NULL,started_at REAL NOT NULL);
        """)
    for sequence in (1, 8, 14, 20):
        payload = b"synthetic image bytes " + bytes([sequence])
        image = image_record(sequence, payload)
        (path / "media" / image["fileName"]).write_bytes(payload)
        (path / "journal" / (image["id"].lower() + ".json")).write_text(json.dumps({"version": 1, "image": image}))
        db.execute("INSERT INTO assets(sequence,id,source_key,file_name,sort_at,image_json,status,active_operation_id) VALUES(?,?,?,?,?,?,?,?)",
                   (sequence, image["id"], image["sourceKey"], image["fileName"], sequence,
                    json.dumps(image), "unknown" if sequence != 20 else "used", "operation-" + str(sequence)))
        db.execute("INSERT INTO operations(sequence,id,asset_id,attempt,target_key,target_json,phase,created_at,updated_at,receipt_json,reason) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                   (sequence, "operation-" + str(sequence), image["id"], 1, "synthetic-target", '{"synthetic":true}',
                    "unknown" if sequence != 20 else "succeeded", sequence, sequence, '{"receipt":"original bytes"}', "original reason"))
        if version >= 3 and sequence == 20:
            db.execute("INSERT INTO upload_starts VALUES(?,?,?)", ("operation-20", '{"receipt":"synthetic start"}', 20))
    db.execute("PRAGMA user_version=" + str(version))
    db.commit()
    db.close()
    feedback = sqlite3.connect(path / "Feedback-v01/feedback.sqlite")
    feedback.executescript("""
        CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE draft(id INTEGER PRIMARY KEY,revision INTEGER NOT NULL,payload BLOB NOT NULL);
        CREATE TABLE reports(id TEXT PRIMARY KEY,payload BLOB NOT NULL,state TEXT NOT NULL,attempts INTEGER,next_attempt REAL,created REAL);
        CREATE TABLE submissions(revision INTEGER PRIMARY KEY,report_id TEXT NOT NULL);
        CREATE TABLE credential_intents(id TEXT PRIMARY KEY);
        INSERT INTO draft VALUES(1,7,'{"text":"synthetic private draft","revision":7}');
        INSERT INTO reports VALUES('synthetic-report','{"text":"retain this body"}','pending',2,0,0);
        INSERT INTO submissions VALUES(7,'synthetic-report');
        INSERT INTO credential_intents VALUES('synthetic-intent');
        PRAGMA user_version=1;
    """)
    feedback.close()
    return path


class StorageReadiness(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="riftlet-storage-test-")
        self.work = Path(self.temporary.name).resolve()
        self.source = make_root(self.work / "synthetic-root")
        self.bundle = self.work / "backup"
        self.restored = self.work / "restored"

    def tearDown(self):
        self.temporary.cleanup()

    def backup(self, **kwargs):
        return storage.backup(self.source, self.bundle, **kwargs)

    def test_roundtrip_preserves_all_bytes_unknowns_and_all_tables(self):
        before = fingerprint(self.source)
        report = self.backup()
        self.assertEqual(report["health"]["status"], "ok")
        queue = report["health"]["databases"]["queue.sqlite"]
        self.assertEqual(queue["unknownOperationSequences"], [1, 8, 14])
        self.assertEqual(queue["tables"]["upload_starts"]["rows"], 1)
        self.assertIn("sqlite_sequence", queue["tables"])
        self.assertIn("future_history", queue["tables"])
        checked = storage.verify(self.bundle, report["manifestSHA256"])
        self.assertEqual(checked["authenticity"], "external-digest-matched")
        recovered = storage.restore(self.bundle, self.restored, report["manifestSHA256"])
        after = fingerprint(self.restored)
        receipt = json.loads(after.pop(recovered["receipt"]))
        self.assertEqual(after, before)
        self.assertEqual(fingerprint(self.source), before)
        self.assertTrue((self.restored / "opaque-empty").is_dir())
        self.assertEqual(receipt["health"]["databases"], report["health"]["databases"])
        self.assertFalse(receipt["applicationStarted"])
        self.assertFalse(receipt["migrationPerformed"])

    def test_health_readonly_and_private_output_modes(self):
        before = fingerprint(self.source)
        result = storage.health(self.source)
        self.assertTrue(result["sourceReadOnly"])
        self.assertEqual(fingerprint(self.source), before)
        self.backup()
        for path in self.bundle.rglob("*"):
            self.assertEqual(path.stat().st_mode & 0o077, 0)

    def test_running_app_lock_refuses_even_detached_override(self):
        with open(self.source / "instance.lock", "rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for detached in (False, True):
                with self.assertRaisesRegex(storage.StorageError, "still owns"):
                    self.backup(detached=detached)
                with self.assertRaises(storage.StorageError):
                    storage.health(self.source, detached)
        self.assertFalse(self.bundle.exists())

    def test_feedback_lock_also_refuses(self):
        with open(self.source / "Feedback-v01/feedback.lock", "rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(storage.StorageError):
                self.backup()
        self.assertFalse(self.bundle.exists())

    def test_missing_lock_requires_explicit_detached_copy_and_is_not_created(self):
        (self.source / "instance.lock").unlink()
        before = fingerprint(self.source)
        with self.assertRaisesRegex(storage.StorageError, "missing"):
            self.backup()
        result = self.backup(detached=True)
        self.assertEqual(result["offline"]["kind"], "detached-source-declaration")
        self.assertEqual(fingerprint(self.source), before)

    def test_wal_commit_is_in_health_and_raw_sidecars_survive(self):
        db = sqlite3.connect(self.source / "queue.sqlite")
        try:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA wal_autocheckpoint=0")
            db.execute("INSERT INTO future_history VALUES(32,X'1234','committed only in WAL')")
            db.commit()
            self.assertGreater((self.source / "queue.sqlite-wal").stat().st_size, 0)
            before = fingerprint(self.source)
            result = self.backup()
            self.assertEqual(result["health"]["databases"]["queue.sqlite"]["tables"]["future_history"]["rows"], 2)
            self.assertEqual(fingerprint(self.source), before)
            self.assertEqual(fingerprint(self.bundle / "data"), before)
            storage.restore(self.bundle, self.restored)
            self.assertEqual((self.restored / "queue.sqlite-wal").read_bytes(), before["queue.sqlite-wal"])
        finally:
            db.close()

    def test_hot_rollback_journal_recovers_only_on_disposable_copy(self):
        script = """
import os, sqlite3, sys
db=sqlite3.connect(sys.argv[1]); db.execute('PRAGMA journal_mode=DELETE')
db.execute('CREATE TABLE spill(id INTEGER PRIMARY KEY,payload BLOB)')
db.executemany('INSERT INTO spill VALUES(?,?)',[(i,b'original'*1000) for i in range(150)])
db.commit(); db.execute('PRAGMA cache_size=5'); db.execute('BEGIN IMMEDIATE')
db.execute('UPDATE spill SET payload=?',(b'uncommitted'*2000,)); os._exit(0)
"""
        subprocess.run([sys.executable, "-c", script, str(self.source / "interrupted.sqlite")], check=True)
        self.assertGreater((self.source / "interrupted.sqlite-journal").stat().st_size, 0)
        before = fingerprint(self.source)
        result = self.backup()
        self.assertEqual(result["health"]["status"], "ok", result["health"])
        self.assertEqual(result["health"]["databases"]["interrupted.sqlite"]["tables"]["spill"]["rows"], 150)
        self.assertEqual(fingerprint(self.source), before)
        self.assertEqual(fingerprint(self.bundle / "data"), before)

    def test_v1_v2_and_future_schema_are_preserved_without_migration(self):
        for version in (1, 2, 99):
            source = make_root(self.work / ("legacy-" + str(version)), version)
            result = storage.backup(source, self.work / ("backup-" + str(version)))
            self.assertEqual(result["health"]["databases"]["queue.sqlite"]["userVersion"], version)
            self.assertEqual(result["health"]["databases"]["queue.sqlite"]["unknownOperationSequences"], [1, 8, 14])
            self.assertFalse(result["health"]["migrationPerformed"])

    def test_pending_and_unowned_staging_are_retained_not_adopted(self):
        payload = b"durable synthetic stage"
        image = image_record(300, payload)
        (self.source / "staging" / (image["id"].lower() + ".part")).write_bytes(payload)
        (self.source / "journal" / (image["id"].lower() + ".json")).write_text(json.dumps({"version": 1, "image": image}))
        (self.source / "staging/unowned.part").write_bytes(b"partial must not be deleted")
        result = self.backup()
        codes = {w["code"] for w in result["health"]["warnings"]}
        self.assertIn("journaled-import-awaiting-native-recovery", codes)
        self.assertIn("unowned-staging-retained", codes)
        self.assertEqual(result["health"]["databases"]["queue.sqlite"]["tables"]["assets"]["rows"], 4)
        self.assertEqual(fingerprint(self.bundle / "data"), fingerprint(self.source))

    def test_uppercase_journal_uuid_matches_native_recovery_contract(self):
        image = image_record(0xABCDEF, b"synthetic uppercase journal")
        identifier = image["id"]
        (self.source / "journal" / (identifier + ".json")).write_text(json.dumps({"version": 1, "image": image}))
        (self.source / "media" / image["fileName"]).write_bytes(b"synthetic uppercase journal")
        result = self.backup()
        self.assertEqual(result["health"]["status"], "ok", result["health"])
        self.assertTrue((self.bundle / "data/journal" / (identifier + ".json")).exists())

    def test_missing_or_changed_used_media_is_reported_without_rewrite(self):
        used = self.source / "media" / (str(uuid.UUID(int=20)) + ".png")
        used.write_bytes(b"changed used bytes")
        (self.source / "media" / (str(uuid.UUID(int=8)) + ".png")).unlink()
        before = fingerprint(self.source)
        result = self.backup()
        self.assertEqual(result["health"]["status"], "attention")
        codes = {e["code"] for e in result["health"]["errors"]}
        self.assertIn("media-content-mismatch", codes)
        self.assertIn("missing-media", codes)
        self.assertEqual(fingerprint(self.source), before)
        self.assertEqual(storage.verify(self.bundle)["byteIntegrity"], "verified")

    def test_corrupt_database_and_configuration_are_retained_for_recovery(self):
        (self.source / "queue.sqlite").write_bytes(b"damaged synthetic database")
        (self.source / "rift-configuration.json").write_bytes(b"{incomplete")
        before = fingerprint(self.source)
        result = self.backup()
        self.assertEqual(result["health"]["status"], "attention")
        recovered = storage.restore(self.bundle, self.restored)
        after = fingerprint(self.restored)
        after.pop(recovered["receipt"])
        self.assertEqual(after, before)
        self.assertEqual(fingerprint(self.source), before)

    def test_source_symlinks_and_fifo_are_rejected_without_following(self):
        external = self.work / "outside"
        external.write_bytes(b"never touch")
        (self.source / "media/alias").symlink_to(external)
        with self.assertRaises(storage.StorageError):
            self.backup()
        self.assertFalse((self.bundle / "COMPLETE.json").exists())
        self.assertEqual(external.read_bytes(), b"never touch")
        (self.source / "media/alias").unlink()
        os.mkfifo(self.source / "media/pipe")
        with self.assertRaises(storage.StorageError):
            storage.health(self.source)

    def test_symlink_root_ancestor_and_destination_parent_are_rejected(self):
        alias = self.work / "alias"
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(OSError):
            storage.health(alias)
        with self.assertRaises(OSError):
            storage.backup(self.source, alias / "nested-copy")
        self.assertFalse((self.source / "nested-copy").exists())

    def test_restore_refuses_existing_empty_or_occupied_destination(self):
        self.backup()
        self.restored.mkdir()
        with self.assertRaises(FileExistsError):
            storage.restore(self.bundle, self.restored)
        marker = self.restored / "sentinel"
        marker.write_bytes(b"keep")
        with self.assertRaises(FileExistsError):
            storage.restore(self.bundle, self.restored)
        self.assertEqual(marker.read_bytes(), b"keep")

    def test_overlapping_paths_and_parent_traversal_refused(self):
        for destination in (self.source, self.source / "backup", self.work):
            with self.assertRaises(storage.StorageError):
                storage.backup(self.source, destination)
        with self.assertRaises(storage.StorageError):
            storage.health(self.source / ".." / "synthetic-root")

    def test_tampered_data_refuses_restore_before_creating_destination(self):
        self.backup()
        (self.bundle / "data/diagnostics.jsonl").write_bytes(b"altered")
        with self.assertRaises(storage.StorageError):
            storage.restore(self.bundle, self.restored)
        self.assertFalse(self.restored.exists())

    def alter_manifest(self, transform):
        path = self.bundle / "manifest.json"
        manifest = json.loads(path.read_bytes())
        transform(manifest)
        body = storage.encoded(manifest)
        path.write_bytes(body)
        (self.bundle / "COMPLETE.json").write_bytes(storage.encoded({"format": storage.FORMAT, "manifestSHA256": storage.sha(body)}))

    def test_manifest_paths_are_validated_even_with_recomputed_checksum(self):
        self.backup()
        for unsafe in ("../escape", "/absolute", "a/../../escape", "a\\escape"):
            original = (self.bundle / "manifest.json").read_bytes()
            self.alter_manifest(lambda m: m["entries"][0].update(path=unsafe))
            with self.assertRaises(storage.StorageError):
                storage.restore(self.bundle, self.restored)
            self.assertFalse(self.restored.exists())
            (self.bundle / "manifest.json").write_bytes(original)
            (self.bundle / "COMPLETE.json").write_bytes(storage.encoded({"format": storage.FORMAT, "manifestSHA256": storage.sha(original)}))

    def test_duplicate_manifest_path_is_refused(self):
        self.backup()
        self.alter_manifest(lambda m: m["entries"].append(m["entries"][0]))
        with self.assertRaises(storage.StorageError):
            storage.verify(self.bundle)

    def test_added_file_missing_completion_and_external_digest_fail(self):
        result = self.backup()
        with self.assertRaises(storage.StorageError):
            storage.verify(self.bundle, "0" * 64)
        self.assertEqual(storage.verify(self.bundle, result["manifestSHA256"])["byteIntegrity"], "verified")
        (self.bundle / "data/extra").write_bytes(b"unexpected")
        with self.assertRaises(storage.StorageError):
            storage.verify(self.bundle)
        (self.bundle / "data/extra").unlink()
        (self.bundle / "COMPLETE.json").unlink()
        with self.assertRaises(storage.StorageError):
            storage.verify(self.bundle)

    def test_source_change_leaves_incomplete_trace_without_success_marker(self):
        inspect = storage.inspect

        def changing(*args):
            report = inspect(*args)
            (self.source / "diagnostics.jsonl").write_bytes(b"concurrent new content")
            return report

        with patch.object(storage, "inspect", side_effect=changing):
            with self.assertRaisesRegex(storage.StorageError, "changed"):
                self.backup()
        self.assertTrue((self.bundle / "capture.json").exists())
        self.assertTrue((self.bundle / "failure.json").exists())
        self.assertFalse((self.bundle / "COMPLETE.json").exists())

    def test_disk_full_keeps_source_and_partial_backup(self):
        before = fingerprint(self.source)
        original = storage.Tree.open

        def full(tree, relative, write=False):
            if write and tree.path == self.bundle / "data" and relative == "queue.sqlite":
                raise OSError(errno.ENOSPC, "synthetic capacity failure")
            return original(tree, relative, write)

        with patch.object(storage.Tree, "open", full):
            with self.assertRaises(OSError):
                self.backup()
        self.assertEqual(fingerprint(self.source), before)
        self.assertTrue((self.bundle / "failure.json").exists())
        self.assertFalse((self.bundle / "COMPLETE.json").exists())

    def test_restore_io_failure_retains_partial_target_and_failure_receipt(self):
        self.backup()
        before = fingerprint(self.bundle)
        original = storage.Tree.open

        def full(tree, relative, write=False):
            if write and tree.path == self.restored and relative == "queue.sqlite":
                raise OSError(errno.ENOSPC, "synthetic capacity failure")
            return original(tree, relative, write)

        with patch.object(storage.Tree, "open", full):
            with self.assertRaises(OSError):
                storage.restore(self.bundle, self.restored)
        self.assertEqual(fingerprint(self.bundle), before)
        receipts = list(self.restored.glob(".storage-restore-failed-*.json"))
        self.assertEqual(len(receipts), 1)
        self.assertEqual(json.loads(receipts[0].read_bytes())["exception"], "OSError")
        with self.assertRaises(FileExistsError):
            storage.restore(self.bundle, self.restored)

    def test_malicious_import_manifest_does_not_follow_its_filename(self):
        image = image_record(301, b"x")
        image["fileName"] = "../../outside"
        (self.source / "journal" / (image["id"].lower() + ".json")).write_text(json.dumps({"version": 1, "image": image}))
        result = storage.health(self.source)
        self.assertEqual(result["health"]["status"], "attention")
        self.assertIn("invalid-import-journal", {x["code"] for x in result["health"]["errors"]})

    def test_cli_handles_space_paths_and_distinguishes_unhealthy_exit(self):
        moved = self.work / "synthetic root with spaces"
        self.source.rename(moved)
        result = subprocess.run([sys.executable, str(SCRIPT), "health", "--source", str(moved)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["sourceReadOnly"])
        (moved / "queue.sqlite").write_bytes(b"corrupt")
        result = subprocess.run([sys.executable, str(SCRIPT), "health", "--source", str(moved)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)


if __name__ == "__main__":
    unittest.main()
