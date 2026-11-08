"""Exercise the ordinary product in a fresh GitHub-hosted macOS account."""
import argparse
from contextlib import ExitStack
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import struct
import subprocess
import tempfile
import time
import uuid
import zlib


def call(*args, check=True, timeout=40):
    return subprocess.run(list(map(str, args)), check=check, capture_output=True, timeout=timeout)


def sha(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def wait_for(probe, description):
    deadline = time.monotonic() + 24
    while time.monotonic() < deadline:
        result = probe()
        if result:
            return result
        time.sleep(0.15)
    raise RuntimeError("Timeout observing " + description)


def write_fixture(source, seed):
    # A deterministic PNG with the actual macOS screenshot metadata boolean.
    # This exercises collection with a generated fixture, not a physical shortcut.
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    scanline = b"\x00" + bytes((seed, 95, 220, 255)) * 96
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", 96, 72, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanline * 72)) + chunk(b"IEND", b""))
    dest = source / f"Screenshot-identity-{seed}.png"
    temp = source.parent / (dest.name + ".pending")
    temp.write_bytes(data)
    call("xattr", "-wx", "com.apple.metadata:kMDItemIsScreenCapture",
         plistlib.dumps(True, fmt=plistlib.FMT_BINARY).hex(), temp)
    temp.rename(dest)
    return dest


def wait_for_capture(dest, asset_root):
    digest = sha(dest)

    def committed():
        database = asset_root / "queue.sqlite"
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as db:
            matches = [(uid, name, json.loads(image)) for uid, name, image in
                       db.execute("SELECT id, file_name, image_json FROM assets")
                       if json.loads(image)["sha256"] == digest]
        if not matches:
            return False
        assert len(matches) == 1
        uid, filename, image = matches[0]
        journal = asset_root / "journal" / (uid.lower() + ".json")
        media = asset_root / "media" / filename
        assert image["id"].lower() == uid.lower() and image["fileName"] == filename
        assert json.loads(journal.read_text())["image"] == image and sha(media) == digest
        return True

    wait_for(committed, "one committed asset with its matching journal and private bytes")
    return digest


def collect_fixture(source, seed, asset_root):
    return wait_for_capture(write_fixture(source, seed), asset_root)


def snapshot(asset_root):
    with sqlite3.connect((asset_root / "queue.sqlite").as_uri() + "?mode=ro", uri=True) as db:
        assert db.execute("PRAGMA quick_check").fetchall() == [("ok",)]
        version = db.execute("PRAGMA user_version").fetchone()[0]
        logical_hash = hashlib.sha256("\n".join(db.iterdump()).encode()).hexdigest()
        cursor = db.execute("SELECT * FROM assets ORDER BY sequence")
        columns = [c[0] for c in cursor.description]
        assets = [dict(zip(columns, row)) for row in cursor]
        operations = db.execute("SELECT * FROM operations ORDER BY id").fetchall()
        starts = db.execute("SELECT * FROM upload_starts ORDER BY operation_id").fetchall()
    return {"schema": version, "logicalSHA256": logical_hash, "assets": assets, "operations": len(operations), "operationRows": operations,
            "upload_starts": len(starts), "startRows": starts,
            "media": {f.name: sha(f) for f in sorted((asset_root / "media").iterdir()) if f.is_file()},
            "journals": {f.name: sha(f) for f in sorted((asset_root / "journal").iterdir()) if f.is_file()}}

def checked_growth(root, before, after, witness):
    """Require a single new capture and exact preservation of all earlier assets and operations."""
    prior = {a["id"]: a for a in before["assets"]}
    current = {a["id"]: a for a in after["assets"]}
    assert all(current.get(uid) == record for uid, record in prior.items())
    assert before["operationRows"] == after["operationRows"] and before["startRows"] == after["startRows"]
    assert before["operations"] == 1 and before["upload_starts"] == 0
    added = [a for uid, a in current.items() if uid not in prior]
    witness_digest = sha(witness)
    assert before["schema"] == after["schema"] == 4
    new_media, new_journals, witnessed_keys = set(), set(), []
    for a in added:
        image = json.loads(a["image_json"])
        name = a["file_name"]
        assert name == Path(name).name and image["fileName"] == name and image["sourceKey"] == a["source_key"]
        assert uuid.UUID(image["id"]) == uuid.UUID(a["id"])
        assert a["status"] == "pending" and a["visibility"] == "visible" and a["active_operation_id"] is None
        journal_name = str(uuid.UUID(a["id"])) + ".json"
        journal = json.loads((root / "journal" / journal_name).read_text())
        assert journal["image"] == image and image["sha256"] == after["media"][name]
        assert (root / "media" / name).stat().st_size == image["byteCount"]
        new_media.add(name)
        new_journals.add(journal_name)
        assert image["sha256"] == witness_digest
        witnessed_keys.append(a["source_key"])
    assert len(added) == len(witnessed_keys) == 1
    identity = witnessed_keys[0].split(":")
    assert len(identity) == 5 and identity[0] == "volume" and identity[2] == str(witness.stat().st_ino)
    uuid.UUID(identity[1])
    for key, names in (("media", new_media), ("journals", new_journals)):
        assert before[key].items() <= after[key].items()
        assert set(after[key]) - set(before[key]) == names and len(names) == len(added)



def move_idle_root(root, destination, process, app):
    assert call(process, "pid", app, check=False).returncode == 2 and not os.path.lexists(destination)
    with ExitStack() as held:
        for path in (root / "instance.lock", root / "Feedback-v01/feedback.lock"):
            lock = held.enter_context(path.open("rb"))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        root.rename(destination)


def safe_context():
    return (os.uname().sysname == "Darwin" and os.getenv("GITHUB_ACTIONS") == "true"
            and os.getenv("RUNNER_ENVIRONMENT") == "github-hosted"
            and os.getenv("GITHUB_REPOSITORY") == "haohongfei2001-png/Riftlet")


def exercise(old, new, report):
    app = Path.home() / "Applications/Riftlet.app"
    root = Path.home() / "Library/Application Support/Riftlet"
    # The same ordinary paths as a consumer, exclusively on a fresh ephemeral host.
    if app.exists() or app.is_symlink() or root.exists() or root.is_symlink() or call("defaults", "read", "com.riftlet.app", check=False).returncode == 0:
        raise RuntimeError("Expected a fresh app, data directory, and preferences")
    if call("pgrep", "-x", "Riftlet", check=False).returncode == 0:
        raise RuntimeError("Another Riftlet process is running")
    scratch = Path(tempfile.mkdtemp(prefix="riftlet-upgrade-", dir=os.environ["RUNNER_TEMP"]))
    host_tools = Path(__file__).resolve().parent
    repository = host_tools.parents[1]
    process = scratch / "app-process"
    identity = scratch / "check-identity"
    call("swiftc", host_tools / "app-process.swift", "-o", process, timeout=90)
    call("swiftc", repository / "scripts/check-update-identity.swift", "-o", identity, timeout=90)
    source = scratch / "system-source"
    source.mkdir()
    app.parent.mkdir(exist_ok=True)
    report["freshAccountAppState"] = True
    # This setting belongs to the disposable account. The native privacy experiment
    # runs separately using Downloads; this ordinary flow uses an unprotected folder.
    previous = call("defaults", "read", "com.apple.screencapture", "location", check=False)

    def launch(expected, version, build):
        call("codesign", "--verify", "--deep", "--strict", "--all-architectures", app)
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        assert (info["CFBundleIdentifier"], info["CFBundleShortVersionString"], info["CFBundleVersion"]) == ("com.riftlet.app", version, build)
        assert sha(app / "Contents/MacOS/Riftlet") == expected
        call("open", "-n", "-g", app)
        def pid():
            result = call(process, "pid", app, check=False)
            return int(result.stdout) if result.returncode == 0 else None
        return wait_for(pid, "LaunchServices application identity")

    def run_version(expected, version, build, expected_folder=source):
        current = launch(expected, version, build)
        wait_for(lambda: call("lsof", "-nP", "-a", "-p", current, "-Ffn", expected_folder, check=False).returncode == 0,
                 "the ordinary collector holding the expected source folder")
        return current

    def stop():
        call(process, "quit", app)

    def onboarding_observation():
        value = call(process, "onboarding", app).stdout.decode().strip()
        return value if value in {"OBSERVED", "AX_NOT_AVAILABLE"} else None

    def compare(candidate, result, code):
        checked = call(identity, "--installed", app, "--candidate", candidate, check=False)
        observed = json.loads(checked.stdout)
        assert checked.returncode == code and observed["result"] == result
        return {"result": observed["result"], "exit": code, "reason": observed["reason"]}

    old_hash, new_hash = [sha(f / "Contents/MacOS/Riftlet") for f in (old, new)]
    assert old_hash != new_hash
    first_use_source = scratch / "first-use-source"
    first_use_source.mkdir()
    call("defaults", "write", "com.apple.screencapture", "location", "-string", first_use_source)
    try:
        # First exercise the current candidate before any App has run on this account.
        # Use a separate fixture source for the subsequent old -> new -> old experiment.
        call("ditto", new, app)
        run_version(new_hash, "0.3.2", "5", first_use_source)
        candidate_window = wait_for(onboarding_observation, "current candidate's first-use window")
        first_use_key = "Riftlet.firstUse.presented.v1.Riftlet"
        assert call("defaults", "read", "com.riftlet.app", first_use_key).stdout.strip() == b"1"
        first_use_digest = collect_fixture(first_use_source, 63, root)
        stop()
        first_use = snapshot(root)
        assert len(first_use["assets"]) == len(first_use["media"]) == len(first_use["journals"]) == 1
        assert set(first_use["media"].values()) == {first_use_digest}
        assert not first_use["operations"] and not first_use["upload_starts"]
        build_source = json.loads((app / "Contents/Resources/release-build.json").read_text())["source"]["commit"]
        assert build_source == os.environ["GITHUB_SHA"]
        report["candidateFirstUse"] = {
            "buildSource": build_source,
            "executableSHA256": new_hash, "onboardingWindowAX": candidate_window,
            "firstUsePresentationRecorded": True, "collectedAssets": 1,
            "sourceAndPrivateMediaSHA256": first_use_digest, "attachmentOperations": 0, "starts": 0,
        }
        # Preserve the complete first run. Only the one key created above is cleared
        # for the baseline's original first-use observation. Never touch system grants.
        preserved_app = scratch / "candidate-first-use.app"
        preserved_data = scratch / "candidate-first-use-data"
        saved_preferences = scratch / "candidate-first-use.plist"
        assert not any(os.path.lexists(p) for p in (preserved_app, preserved_data, saved_preferences))
        assert call(process, "pid", app, check=False).returncode == 2
        with ExitStack() as held:
            for lock_path in (root / "instance.lock", root / "Feedback-v01/feedback.lock"):
                lock = held.enter_context(lock_path.open("rb"))
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            call("defaults", "export", "com.riftlet.app", saved_preferences)
            assert plistlib.loads(saved_preferences.read_bytes())[first_use_key]
            assert snapshot(root) == first_use and sha(app / "Contents/MacOS/Riftlet") == new_hash
            app.rename(preserved_app)
            root.rename(preserved_data)
            call("defaults", "delete", "com.riftlet.app", first_use_key)
        assert snapshot(preserved_data) == first_use and sha(preserved_app / "Contents/MacOS/Riftlet") == new_hash
        call("defaults", "write", "com.apple.screencapture", "location", "-string", source)

        call("ditto", old, app)
        run_version(old_hash, "0.3.0", "3")
        first_window = wait_for(onboarding_observation, "first-use window on the verified process")
        first = collect_fixture(source, 24, root)
        stop()
        baseline = snapshot(root)
        assert len(baseline["assets"]) == len(baseline["media"]) == len(baseline["journals"]) == 1
        assert set(baseline["media"].values()) == {first} and not (baseline["operations"] or baseline["upload_starts"])
        assert call("defaults", "read", "com.riftlet.app", "Riftlet.firstUse.presented.v1.Riftlet").stdout.strip() == b"1"
        report["firstOrdinaryLaunchAndImport"] = {"scope": "Legacy baseline with fresh fixture data on the same hosted account",
            "assetCount": 1, "sourceAndPrivateMediaSHA256": first,
            "firstUsePresentationRecorded": True, "onboardingWindowAX": first_window}
        # Use the released Core for both the pre-upgrade UNKNOWN and the downgrade probe.
        legacy = scratch / "beta3-source"
        old_source = json.loads((app / "Contents/Resources/release-build.json").read_text())["source"]["commit"]
        assert old_source == "2e779f646ac4874344fac94f79103e8ddf9b02c8"
        call("git", "-C", repository, "worktree", "add", "--detach", legacy, old_source)
        fixture_package = legacy / "Tests/ReleaseUpgradeHost/UnknownFixture"
        shutil.copytree(host_tools / "UnknownFixture", fixture_package)
        fixture = ["swift", "run", "--package-path", fixture_package,
                   "--scratch-path", scratch / "legacy-fixture-build", "SeedUnknown"]
        detached = scratch / "legacy-data"
        move_idle_root(root, detached, process, app)
        call(*fixture, "seed", detached, first, timeout=180)
        baseline = snapshot(detached)
        assert baseline["schema"] == 3 and baseline["operations"] == 1 and baseline["assets"][0]["status"] == "unknown"
        backup = scratch / "pre-upgrade-copy"
        call("ditto", detached, backup)
        assert snapshot(backup) == baseline
        detached.rename(root)
        damaged = scratch / "Damaged.app"
        call("ditto", new, damaged)
        with (damaged / "Contents/Resources/release-build.json").open("ab") as f:
            f.write(b"\n")
        report["refusedDamagedUpdate"] = compare(damaged, "invalid", 1)
        assert snapshot(root) == baseline and sha(app / "Contents/MacOS/Riftlet") == old_hash
        report["crossIdentity"] = compare(new, "mismatch", 2)
        # An explicitly requested identity transition in a disposable host. Preserve the entire old bundle.
        old_copy = app.with_name("Riftlet-old-lab.app")
        if old_copy.exists() or old_copy.is_symlink():
            raise RuntimeError("Unexpected rollback destination")
        app.rename(old_copy)
        call("ditto", new, app)
        run_version(new_hash, "0.3.2", "5")
        second = collect_fixture(source, 159, root)
        stop()
        upgraded = snapshot(root)
        assert len(upgraded["assets"]) == 2 and upgraded["assets"][0] == baseline["assets"][0]
        assert set(upgraded["media"].values()) == {first, second} and len(upgraded["journals"]) == 2
        for key in ("media", "journals"):
            assert baseline[key].items() <= upgraded[key].items()
        assert upgraded["schema"] == 4 and upgraded["operationRows"] == baseline["operationRows"]
        assert upgraded["upload_starts"] == baseline["upload_starts"] == 0
        latest = scratch / "latest-upgraded-data"
        move_idle_root(root, latest, process, app)
        call("ditto", latest, root)
        assert snapshot(root) == snapshot(latest) == upgraded
        new_copy = scratch / "Riftlet-upgrade.app"
        app.rename(new_copy)
        old_copy.rename(app)
        # Beta 3 normalizes the database mode immediately before reading its format.
        # This disposable, owner-only root makes that change observable in the App process.
        queue = root / "queue.sqlite"
        assert root.stat().st_mode & 0o077 == 0 and queue.stat().st_mode & 0o777 == 0o600
        queue.chmod(0o640)
        old_pid = launch(old_hash, "0.3.0", "3")
        # Verify this exact process owns the ordinary root while the new arrival is present.
        wait_for(lambda: call("lsof", "-nP", "-a", "-p", old_pid, root / "instance.lock",
                              check=False).returncode == 0, "old application taking the instance lock")
        wait_for(lambda: queue.stat().st_mode & 0o777 == 0o600, "Beta 3 opening this queue")
        pending_witness = write_fixture(source, 211)
        time.sleep(9)  # The old collector's scheduled retries span 8.3 seconds.
        assert call(process, "pid", app).stdout.strip() == str(old_pid).encode()
        assert call("lsof", "-nP", "-a", "-p", old_pid, source, check=False).returncode == 1
        stop()
        assert snapshot(root) == snapshot(latest) == upgraded
        call(*fixture, "reject", latest, second)
        assert snapshot(latest) == upgraded
        report["appOnlyRollback"] = {"status": "OLD_READER_BLOCKED_AT_SCHEMA_4", "originalQueueAndFilesPreserved": True,
                                     "ordinaryAppOpenedQueue": True, "legacyCoreRefusal": "Unsupported schema version 4",
                                     "knownDuplicateCount": 0, "originalUnknownRetained": True,
                                     "sourceFolderOpenedByOldAppAtObservation": False, "testArrivalCollectedByOldApp": False}
        # Relaunch the compatible application on the very data the old App tried to open.
        app.rename(scratch / "Riftlet-tested-old.app")
        new_copy.rename(app)
        run_version(new_hash, "0.3.2", "5")
        third = wait_for_capture(pending_witness, root)
        after_recovery = snapshot(root)
        checked_growth(root, upgraded, after_recovery, pending_witness)
        fourth = collect_fixture(source, 230, root)
        stop()
        assert len({first, second, third, fourth}) == 4
        checked_growth(root, after_recovery, snapshot(root), source / "Screenshot-identity-230.png")
        assert snapshot(backup) == baseline and snapshot(latest) == upgraded
        report["forwardRecovery"] = {"status": "PASS", "reusedLatestDataAfterOldAttempt": True,
                                     "arrivalDuringDowngradeCollectedOnce": True, "nextCaptureCollectedOnce": True,
                                     "preUpgradeBackupAndLatestCopyPreserved": True, "retainedAssets": 2,
                                     "retainedPreUpgradeUnknownOperations": 1, "finalAssets": 4, "starts": 0}
        report["normalLaunches"] = ["freshCandidate", "adHocBaseline", "candidateUpgrade",
                                    "oldAppOnCurrentDataCopy", "candidateOnSameDataCopy"]
        report["executableSHA256"] = {"old": old_hash, "new": new_hash, "final": sha(app / "Contents/MacOS/Riftlet")}
    finally:
        result = call(process, "pid", app, check=False)
        if result.returncode == 0:
            stop()
        if previous.returncode == 0:
            call("defaults", "write", "com.apple.screencapture", "location", "-string", previous.stdout.decode().strip())
        else:
            call("defaults", "delete", "com.apple.screencapture", "location")


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--new", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not safe_context():
        parser.error("Requires a disposable GitHub-hosted macOS runner for the Riftlet repository")
    result = {"status": "INCOMPLETE", "scope": "Ordinary locally built App, clean hosted account and synthetic screenshots",
              "liveChatGPT": "NOT_RUN", "developerIDTransition": "NOT_RUN", "protectedFolderConsent": "separate probe"}
    try:
        exercise(args.old, args.new, result)
        result["status"] = "OLD_READER_BLOCKED_FORWARD_RECOVERY_VERIFIED"
    finally:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
