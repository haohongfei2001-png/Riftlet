#!/bin/sh
# Runs the explicit review mode of one supplied App. Does not build/install it.
set -eu
exec python3 - "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid

if len(sys.argv) not in (2, 3) or sys.argv[1] in ("-h", "--help"):
    print("Usage: scripts/run-settings-review.sh /absolute/Riftlet.app [new-private-result-directory]")
    print("Opens only that App's native review windows; creates a fresh UUID data root.")
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
for marker in (b"--settings-review-run", b"RIFTLET_SETTINGS_REVIEW_REPORT=", b"Riftlet-Settings-Review-"):
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
log = output / "application.log"
started = time.monotonic()
timed_out = False
with log.open("xb") as stream:
    process = subprocess.Popen([str(executable), "--settings-review", identifier, "--settings-review-run"],
                               stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT)
    try:
        exit_code = process.wait(timeout=180)
    except subprocess.TimeoutExpired:
        timed_out = True
        # Only the exact child created above is signalled. Never find/quit an
        # existing Riftlet, browser, or process by name.
        process.terminate()
        try:
            exit_code = process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            exit_code = process.wait()

result = {"schema": 1, "reviewID": identifier, "app": str(app),
          "executableSHA256": binary_sha, "childPID": process.pid,
          "exitCode": exit_code, "timedOut": timed_out,
          "elapsedSeconds": time.monotonic() - started,
          "logSHA256": hashlib.sha256(log.read_bytes()).hexdigest(),
          "status": "INCOMPLETE", "productionDataAccess": False,
          "note": "Only explicit isolated settings-review mode; no installation or production restart."}
prefix = "RIFTLET_SETTINGS_REVIEW_REPORT="
paths = [line[len(prefix):] for line in log.read_text(errors="replace").splitlines() if line.startswith(prefix)]
if len(paths) == 1:
    report = Path(paths[0])
    try:
        if report.resolve(strict=True) != report or report.name != "report.json":
            raise ValueError("unexpectedReportPath")
        if report.parent.parent.name != "evidence" or report.parent.parent.parent.name != "Riftlet-Settings-Review-" + identifier:
            raise ValueError("unexpectedReviewRoot")
        raw = report.read_bytes()
        document = json.loads(raw)
        if document.get("reviewID") != identifier or document.get("executableSHA256") != binary_sha:
            raise ValueError("reportIdentityMismatch")
        result.update(report=str(report), reportSHA256=hashlib.sha256(raw).hexdigest(),
                      status=document.get("status", "INCOMPLETE"), completed=document.get("completed", False),
                      caseCount=len(document.get("cases", [])), frameCount=len(document.get("frames", [])))
    except (OSError, ValueError, KeyError) as error:
        result["reportError"] = type(error).__name__
if timed_out or exit_code != 0 or not result.get("completed"):
    result["status"] = "INCOMPLETE"
destination = output / "runner-result.json"
destination.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print("RIFTLET_SETTINGS_REVIEW_RESULT=" + str(destination))
if "report" in result:
    print(prefix + result["report"])
sys.exit(0 if result["status"] == "PASS_SCOPED_NATIVE_REVIEW" else 2 if result["status"] == "PARTIAL_NATIVE_REVIEW" else 1)
PY
