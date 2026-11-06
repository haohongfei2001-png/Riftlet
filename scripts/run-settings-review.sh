#!/bin/sh
# Runs the explicit review mode of one supplied App. Does not build/install it.
set -eu
exec python3 - "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import uuid

if len(sys.argv) not in (2, 3) or sys.argv[1] in ("-h", "--help"):
    print("Usage: scripts/run-settings-review.sh /absolute/Riftlet.app [new-private-result-directory]")
    print("Runs native review in a fresh UUID root, then a same-package restart check on success.")
    sys.exit(0 if len(sys.argv) == 2 and sys.argv[1] in ("-h", "--help") else 64)

app = Path(sys.argv[1]).expanduser().resolve(strict=True)
if app.suffix != ".app" or not app.is_dir():
    raise SystemExit("Supply the built .app bundle, not an installed-process PID.")
with (app / "Contents/Info.plist").open("rb") as stream:
    name = plistlib.load(stream).get("CFBundleExecutable")
if not isinstance(name, str) or Path(name).name != name:
    raise SystemExit("Invalid bundle executable name.")
executable = app / "Contents/MacOS" / name
if executable.is_symlink() or not executable.is_file() or not os.access(executable, os.X_OK):
    raise SystemExit("Missing regular bundle executable.")
binary = executable.read_bytes()
for marker in (b"--settings-review-run", b"--settings-review-restart-check",
               b"RIFTLET_SETTINGS_REVIEW_REPORT=", b"Riftlet-Settings-Review-"):
    if marker not in binary:
        raise SystemExit("This executable does not contain the required isolated review entry points.")
binary_sha = hashlib.sha256(binary).hexdigest()
del binary

if len(sys.argv) == 3:
    output = Path(sys.argv[2]).expanduser().absolute()
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    output = output.resolve(strict=True)
else:
    output = Path(tempfile.mkdtemp(prefix="riftlet-settings-review-"))
identifier = str(uuid.uuid4())
prefix = "RIFTLET_SETTINGS_REVIEW_REPORT="

def digest(data):
    return hashlib.sha256(data).hexdigest()

def save_result(name, result):
    destination = output / name
    with destination.open("x") as stream:
        stream.write(json.dumps(result, indent=2, sort_keys=True) + "\n")
    return destination

def launch(flag, log_name, timeout):
    result = {"schema": 1, "reviewID": identifier, "app": str(app),
              "executableSHA256": binary_sha, "status": "INCOMPLETE",
              "productionDataAccess": False, "timeoutSeconds": timeout}
    started = time.monotonic()
    log = output / log_name
    try:
        if executable.is_symlink() or digest(executable.read_bytes()) != binary_sha:
            raise ValueError("executableChangedBeforeLaunch")
        with log.open("xb") as stream:
            process = subprocess.Popen([str(executable), "--settings-review", identifier, flag],
                                       stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT)
            result.update(childPID=process.pid, timedOut=False)
            try:
                result["exitCode"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                result["timedOut"] = True
                # Signal only the exact child created here, never a process
                # found by name or an existing installed Riftlet/browser.
                process.terminate()
                try:
                    result["exitCode"] = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    result["exitCode"] = process.wait()
    except (OSError, ValueError) as error:
        result["launchError"] = type(error).__name__
    result["elapsedSeconds"] = time.monotonic() - started
    if log.exists():
        result["logSHA256"] = digest(log.read_bytes())
    return result, log

def read_report(result, log, filename, directory_prefix):
    paths = [line[len(prefix):] for line in log.read_text(errors="replace").splitlines() if line.startswith(prefix)]
    if len(paths) != 1:
        raise ValueError("missingOrAmbiguousReportPath")
    report = Path(paths[0])
    if report.resolve(strict=True) != report or report.name != filename:
        raise ValueError("unexpectedReportPath")
    if not report.parent.name.startswith(directory_prefix):
        raise ValueError("unexpectedEvidenceDirectory")
    uuid.UUID(report.parent.name[len(directory_prefix):])
    if report.parent.parent.name != "evidence" or report.parent.parent.parent.name != "Riftlet-Settings-Review-" + identifier:
        raise ValueError("unexpectedReviewRoot")
    root = report.parent.parent.parent
    marker = root / "settings-review-identity.txt"
    if marker.is_symlink() or marker.read_bytes() != (identifier + "\n").encode():
        raise ValueError("reviewRootIdentityMismatch")
    raw = report.read_bytes()
    document = json.loads(raw)
    if not isinstance(document, dict):
        raise ValueError("unexpectedReportShape")
    if (document.get("reviewID") != identifier or document.get("executableSHA256") != binary_sha
            or document.get("processPID") != result.get("childPID")):
        raise ValueError("reportIdentityMismatch")
    result.update(report=str(report), reportSHA256=digest(raw),
                  status=document.get("status", "INCOMPLETE"), completed=document.get("completed") is True)
    return root, document

def regular_bytes(path):
    if path.resolve(strict=True) != path or not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError("nonRegularReviewFile")
    return path.read_bytes()

def snapshot(root):
    # Both calls occur only after the exact child has normally exited. The
    # validated UUID root is never replaced with a production/default path.
    if root.resolve(strict=True) != root or root.name != "Riftlet-Settings-Review-" + identifier:
        raise ValueError("unexpectedSnapshotRoot")
    if regular_bytes(root / "settings-review-identity.txt") != (identifier + "\n").encode():
        raise ValueError("snapshotIdentityMismatch")
    database = root / "queue.sqlite"
    if database.resolve(strict=True) != database or not stat.S_ISREG(database.lstat().st_mode):
        raise ValueError("unexpectedDatabaseFile")
    connection = sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=5)
    try:
        connection.execute("PRAGMA query_only=ON")
        connection.execute("BEGIN")
        rows = connection.execute("SELECT id,file_name,image_json FROM assets ORDER BY id").fetchall()
        operations = connection.execute("SELECT COUNT(*) FROM operations").fetchone()[0]
        starts = connection.execute("SELECT COUNT(*) FROM upload_starts").fetchone()[0]
    finally:
        connection.close()
    identities = []
    media = root / "media"
    if media.resolve(strict=True) != media or not media.is_dir():
        raise ValueError("unexpectedMediaDirectory")
    media_files = {}
    media_sizes = {}
    for folder, directories, files in os.walk(media, followlinks=False):
        for directory in directories:
            if (Path(folder) / directory).is_symlink():
                raise ValueError("mediaDirectorySymlink")
        for name in files:
            path = Path(folder) / name
            data = regular_bytes(path)
            relative = str(path.relative_to(media))
            media_files[relative] = digest(data)
            media_sizes[relative] = len(data)
    for asset_id, filename, raw_image in rows:
        image = json.loads(raw_image)
        if not isinstance(image, dict):
            raise ValueError("unexpectedAssetImageShape")
        if (not isinstance(filename, str) or filename in ("", ".", "..") or Path(filename).name != filename
                or image.get("fileName") != filename or image.get("id") != asset_id):
            raise ValueError("assetMediaIdentityMismatch")
        if media_files.get(filename) != image.get("sha256") or media_sizes.get(filename) != image.get("byteCount"):
            raise ValueError("assetMediaBytesMismatch")
        identities.append([asset_id, filename, image["sha256"], image["byteCount"]])
    settings = ["rift-configuration.json", "lifecycle-settings.json", "arrival-motion-settings.json",
                "capture-entry-settings.json", "app-presentation-settings.json"]
    return {"assetCount": len(rows), "assetIdentityMediaMapSHA256": digest(json.dumps(identities, separators=(",", ":")).encode()),
            "operations": operations, "uploadStarts": starts,
            "jsonSHA256": {name: digest(regular_bytes(root / name)) for name in settings},
            "mediaFilesSHA256": media_files, "allMediaMatchAssets": True,
            "databaseReadMode": "SQLite URI mode=ro; query_only; one read transaction; child already exited"}

result, log = launch("--settings-review-run", "application.log", 180)
review_root = None
try:
    review_root, document = read_report(result, log, "report.json", "run-")
    result.update(caseCount=len(document.get("cases", [])), frameCount=len(document.get("frames", [])))
except (OSError, ValueError, KeyError, TypeError) as error:
    result["reportError"] = type(error).__name__
if result.get("timedOut") or result.get("exitCode") != 0 or not result.get("completed"):
    result["status"] = "INCOMPLETE"
destination = save_result("runner-result.json", result)
print("RIFTLET_SETTINGS_REVIEW_RESULT=" + str(destination))
if "report" in result:
    print(prefix + result["report"])

# A failed, partial, or non-exiting original run is preserved as-is. Never run
# the UI suite again or reinterpret it as a successful restart prerequisite.
if result["status"] != "PASS_SCOPED_NATIVE_REVIEW":
    sys.exit(2 if result["status"] == "PARTIAL_NATIVE_REVIEW" else 1)

restart = {"schema": 1, "reviewID": identifier, "executableSHA256": binary_sha,
           "status": "INCOMPLETE", "originalRunnerResult": str(destination),
           "originalRunnerResultSHA256": digest(destination.read_bytes()),
           "originalReportSHA256": result["reportSHA256"], "productionDataAccess": False}
try:
    restart["before"] = snapshot(review_root)
    if restart["before"]["operations"] != 0 or restart["before"]["uploadStarts"] != 0:
        raise ValueError("unexpectedOperationsBeforeRestart")
    execution, restart_log = launch("--settings-review-restart-check", "restart-application.log", 30)
    restart.update(execution)
    # The child has exited (or the exact timed-out child was stopped). Preserve
    # this readback even when its report itself failed, for an honest diagnosis.
    restart["after"] = snapshot(review_root)
    restart["equal"] = restart["before"] == restart["after"]
    if execution.get("timedOut") or execution.get("exitCode") != 0:
        raise ValueError("restartDidNotExitNormally")
    restarted_root, document = read_report(restart, restart_log, "restart-report.json", "restart-")
    if restarted_root != review_root or restart.get("childPID") == result.get("childPID"):
        raise ValueError("restartProcessOrRootMismatch")
    if not restart.get("completed") or document.get("status") != "PASS_SCOPED_NATIVE_RESTART":
        raise ValueError("restartReportDidNotPass")
    prior = next((item for item in document.get("checks", []) if item.get("check") == "same-binary-new-process-after-completed-run"), {})
    if (prior.get("status") != "PASS" or prior.get("priorReport") != result["report"]
            or prior.get("priorReportSHA256") != result["reportSHA256"] or prior.get("priorProcessPID") != result["childPID"]):
        raise ValueError("restartPriorReportMismatch")
    if not restart["equal"]:
        raise ValueError("dataChangedAcrossRestart")
    restart["status"] = "PASS_SCOPED_NATIVE_RESTART"
except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
    restart["status"] = "INCOMPLETE" if restart.get("timedOut") or restart.get("launchError") else "FAIL"
    restart["verificationError"] = str(error) if isinstance(error, ValueError) else type(error).__name__
restart_destination = save_result("restart-runner-result.json", restart)
print("RIFTLET_SETTINGS_RESTART_RESULT=" + str(restart_destination))
if "report" in restart:
    print("RIFTLET_SETTINGS_RESTART_REPORT=" + restart["report"])
sys.exit(0 if restart["status"] == "PASS_SCOPED_NATIVE_RESTART" else 1)
PY
