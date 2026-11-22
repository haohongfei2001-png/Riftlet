"""Drive build-60 Core on independent private copies of the three sealed build-59 failure databases.

Usage: python3 -B run_archives.py ARCHIVE_MANIFEST.json NEW_EVIDENCE_DIRECTORY
The manifest maps each digest listed in ARCHIVES to {"database": "/.../sealed.sqlite", "png": "/.../original.png"}.
Produces private SQLite backups and a shareable summary with hashes only.
"""
import argparse
from collections import Counter
from contextlib import closing
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE.parent))
from verify_unknown_recovery import file_digest, rows, snapshot, verify_files
from verify_recovery import read_operation, require

ARCHIVES = {
    "3f1176fe3da464277c4ae2552c9a4ecee799b8d7aa4d1b5b7337b5b097c1e926": "after-native-send",
    "ed000599b6b66cdb2196989b140c6d097ed366f68c694cf51ed73707bfc0dd88": "partial-native-upload",
    "2a7c15697cde5d96927999e6ec9b4766dd5ef79e58dfd0bb46fd5d0c53a498de": "body-sent-before-response",
}


def copy_backup(source, destination):
    destination.touch(mode=0o600, exist_ok=False)
    with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True)) as original:
        with closing(sqlite3.connect(destination)) as copy:
            original.backup(copy)
    with snapshot(destination) as db:
        require(not db.execute("PRAGMA foreign_key_check").fetchall(), "Invalid backup")


def check_cancelled(archive, before, old_id, png):
    with snapshot(archive) as original, snapshot(before) as db:
        old = read_operation(original, old_id, png)
        require(old == read_operation(db, old_id, png), "Historical dispatch changed during pre-input cancellation")
        for table in ("upload_starts", "checkpoints"):
            require(rows(original, "SELECT * FROM " + table) == rows(db, "SELECT * FROM " + table),
                    "Pre-input cancellation changed a START or checkpoint")
        previous = rows(original, "SELECT * FROM operations")
        entry = db.execute("SELECT successor_id,predecessor_id FROM attachment_reselections").fetchall()
        require(len(entry) == 1 and entry[0][1] == old_id, "Expected exactly one input-free recovery attempt")
        cancelled = entry[0][0]
        cancelled_rows = rows(db, "SELECT * FROM operations WHERE id=?", (cancelled,))
        require(sum(cancelled_rows.values()) == 1 and rows(db, "SELECT * FROM operations") ==
                previous + cancelled_rows, "A historical operation row changed")
        phase = db.execute("SELECT phase,attempt,receipt_json FROM operations WHERE id=?", (cancelled,)).fetchone()
        require(phase == ("failed", old["identity"]["attempt"] + 1, None), "Cancellation was not before input")
        require(original.execute("PRAGMA user_version").fetchone() == (4,) and
                db.execute("PRAGMA user_version").fetchone() == (7,), "Unexpected historical migration")
        a = old["identity"]["assetID"]
        require(db.execute("SELECT active_operation_id FROM assets WHERE id=?", (a,)).fetchone() == (old_id,),
                "Cancellation did not restore the original head")
        return cancelled


def case(executable, database, png_path, work, digest):
    require(not database.is_symlink() and not png_path.is_symlink(), "Plain archived files required")
    require(file_digest(database) == digest, "Incorrect archive fingerprint")
    original_png_digest = file_digest(png_path)
    with snapshot(database) as db:
        pending = db.execute("""SELECT o.id,a.file_name FROM operations o JOIN assets a ON a.id=o.asset_id
                                WHERE o.phase='unknown' AND a.active_operation_id=o.id""").fetchall()
        require(len(pending) == 1, "Expected one archived failure")
        old, filename = pending[0]
        require(Path(filename).name == filename and filename.endswith(".png"), "Unsafe asset name")
        historical = read_operation(db, old, png_path.read_bytes())
        require(historical["call"]["inputExecutionReturned"] and historical["receipt"]["outcome"] == "inputTriggered"
                and historical["start"] is None, "Unexpected historical receipt")
    work.mkdir(mode=0o700)
    (work / "controlled-copy-only").touch(mode=0o600, exist_ok=False)
    working = work / "working.sqlite"
    shutil.copyfile(database, working)
    saved = work / filename
    shutil.copyfile(png_path, saved)
    before, after = work / "before.sqlite", work / "after.sqlite"
    results = []
    for phase, destination in (("cancel", before), ("complete", after)):
        completed = subprocess.run([executable, phase, work], capture_output=True, text=True)
        (work / (phase + ".log")).write_text(completed.stdout + completed.stderr)
        require(completed.returncode == 0, "Controlled phase " + phase + " failed; see its private log")
        results.append(completed.stdout.strip())
        copy_backup(working, destination)
    cancelled = check_cancelled(database, before, old, saved.read_bytes())
    with snapshot(after) as db:
        new = db.execute("SELECT active_operation_id FROM assets WHERE id=?", (historical["identity"]["assetID"],)).fetchone()[0]
        require(len({old, new, cancelled}) == 3, "Distinct identities required")
        require(db.execute("SELECT attempt FROM operations WHERE id=?", (new,)).fetchone() ==
                (historical["identity"]["attempt"] + 2,), "Expected gap for the retained input-free attempt")
        require(rows(db, "SELECT successor_id,predecessor_id FROM attachment_reselections") ==
                Counter([(new, old), (cancelled, old)]), "Prior cancelled link was lost")
    proof = verify_files(before, after, saved, old, new)
    require(file_digest(database) == digest and file_digest(saved) == original_png_digest == file_digest(png_path),
            "Sealed database or original PNG changed")
    return {"case": ARCHIVES[digest], "archiveSHA256": digest, "pngSHA256": original_png_digest,
            "beforeSHA256": proof["beforeSHA256"], "afterSHA256": proof["afterSHA256"],
            "originalAndCancelledRowsUnchanged": True, "lateCallbackFamilies": 5,
            "storedAttempts": [historical["identity"]["attempt"] + offset for offset in range(3)],
            "oldAndNewDispatchInvocations": 2, "cancelledDispatchInvocations": 0,
            "relationshipCount": 2, "controlledAcceptedSTARTs": proof["addedAttachmentAcceptedSTARTs"],
            "originalSTARTs": proof["originalSTARTs"], "realSignedAppInputsDuringAudit": 0, "coreOutput": results}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    refs = json.loads(args.manifest.read_bytes())
    require(set(refs) == set(ARCHIVES), "All three pinned historical sources required")
    output = args.output.resolve()
    output.mkdir(mode=0o700, exist_ok=False)
    binary = output / "archive-recovery"
    core = ROOT / "Sources/RiftletCore"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(output / "module-cache"),
                    "-I", ROOT / "Sources/CSQLite", *sorted(core.glob("*.swift")), HERE / "ArchiveRecovery.swift",
                    "-lsqlite3", "-o", binary], check=True)
    summaries = [case(binary, Path(refs[h]["database"]), Path(refs[h]["png"]), output / name, h)
                 for h, name in ARCHIVES.items()]
    report = {"scope": "Archived originating operations and PNGs, actual build 60 Core, controlled adapter",
              "websiteStatus": "NOT_RUN", "cases": summaries}
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
