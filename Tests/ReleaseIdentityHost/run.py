"""Run only on a disposable GitHub-hosted macOS machine; publish only the --output JSON."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time
from uuid import uuid4


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PHASES = [("v1-initial", "allow"), ("v1-picker", "select"), ("v1-restart", "observe"),
          ("v2-update", "deny"), ("v2-picker", "select"), ("rollback-v1", "observe")]

class HarnessFailure(Exception):
    """A fixed, public-safe reason code."""


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, timeout=45):
    return subprocess.run(args, capture_output=True, timeout=timeout)


def checked(args, stage):
    if command(args).returncode:
        raise HarnessFailure(stage)


def bundle_files(app):
    return {str(p.relative_to(app)): (p.stat().st_mode & 0o7777, sha(p))
            for p in app.rglob("*") if p.is_file()}


def make_bundle(root, binary, nonce, version):
    app = root / ("v" + version) / "Fixture.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    shutil.copy2(binary, contents / "MacOS/Fixture")
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "org.riftlet.release-identity-host." + nonce,
        "CFBundleName": "Riftlet CI " + nonce, "CFBundleDisplayName": "Riftlet CI " + nonce,
        "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL",
        "CFBundleVersion": version, "CFBundleShortVersionString": version + ".0",
        "LSUIElement": True, "FixtureNonce": nonce,
        "NSDownloadsFolderUsageDescription": "Read the disposable Downloads marker for " + nonce,
    }))
    checked(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", app], "FIXTURE_SIGN_FAILED")
    return app


def compare_identity(tool, installed, candidate, expected):
    result = command([tool, "--installed", installed, "--candidate", candidate])
    data = json.loads(result.stdout)
    if result.returncode != expected or not all(data[side].get("signatureValid") and
            data[side].get("adHocSignature") for side in ("installed", "candidate")):
        raise HarnessFailure("UNEXPECTED_CODE_IDENTITY")
    return {"result": data["result"], "requirementOSStatus": data["requirementCheckOSStatus"],
            "sameBundleIdentifier": data["installed"]["bundleIdentifier"] == data["candidate"]["bundleIdentifier"],
            "identicalCDHash": data["installed"]["cdHash"] == data["candidate"]["cdHash"],
            "bothStrictlyValidAdHoc": True}


def stage_app(root, candidate, label):
    current = root / "installed/Fixture.app"
    staged = root / ("stage-" + label + ".app")
    shutil.copytree(candidate, staged)
    if bundle_files(staged) != bundle_files(candidate):
        raise HarnessFailure("STAGED_BYTES_DIFFER")
    if current.exists():
        current.rename(root / ("retired-before-" + label + ".app"))
    staged.rename(current)
    return current


def receipt(path):
    try:
        data = json.loads(path.read_bytes())
        return data["pid"], data["observations"]
    except FileNotFoundError:
        return None, {}


def owned_processes(executable):
    # Only an exact executable in this fresh UUID root can be terminated.
    proc = ctypes.CDLL("/usr/lib/libproc.dylib").proc_pidpath
    proc.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    expected = os.fsencode(executable.resolve())
    listing = command(["/bin/ps", "-axo", "pid="])
    if listing.returncode:
        raise HarnessFailure("PROCESS_LIST_UNAVAILABLE")
    result = set()
    for word in listing.stdout.split():
        pid = int(word)
        buf = ctypes.create_string_buffer(4096)
        if proc(pid, buf, len(buf)) > 0 and os.path.realpath(buf.value) == expected:
            result.add(pid)
    return result


def launch(root, app, nonce, phase, action, observer):
    path = root / (phase + ".json")
    executable = app / "Contents/MacOS/Fixture"
    # A path passed to open as a document can confer user intent. Supply only
    # the .app to LaunchServices; the app derives the protected marker itself.
    process = subprocess.Popen(["/usr/bin/open", "-n", "-W", app, "--args", "--fixture-root", root, "--phase", phase],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = {"phase": phase, "ui": {"state": "NOT_RUN_NO_LAUNCH_RECEIPT"}}
    started = time.monotonic()
    while process.poll() is None and not path.exists() and time.monotonic() - started < 8:
        time.sleep(0.1)
    pid, facts = receipt(path)
    if pid and not facts.get("completed") and pid in owned_processes(executable):
        try:
            seen = command([observer, nonce, str(pid), action, path], timeout=8)
            result["ui"] = json.loads(seen.stdout) if seen.returncode == 0 else {"state": "OBSERVER_UNAVAILABLE"}
        except subprocess.TimeoutExpired:
            result["ui"] = {"state": "OBSERVER_DEADLINE"}
    elif facts.get("completed"):
        result["ui"] = {"state": "COMPLETED_BEFORE_OBSERVATION"}
    try:
        process.wait(timeout=max(1, 20 - (time.monotonic() - started)))
    except subprocess.TimeoutExpired:
        result["launcherTimedOut"] = True
    pid, facts = receipt(path)
    live = owned_processes(executable)
    result["requiredOwnTermination"] = bool(live)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for owned in live:
            if owned in owned_processes(executable):
                try:
                    os.kill(owned, sig)
                except ProcessLookupError:
                    pass
        if live:
            time.sleep(0.35)
        live = owned_processes(executable)
        if not live:
            break
    if process.poll() is None:
        process.kill()  # our /usr/bin/open waiting process only
    process.wait(timeout=3)
    result.update(observations=facts, launchServicesExit=process.returncode,
                  settled=not live and not (result.get("launcherTimedOut") and pid is None))
    return result, pid


def prepare_marker(root, nonce):
    # Keep even the runner's initial fixture write bounded and distinct from any app decision.
    program = """
import os, sys
from pathlib import Path
downloads = Path.home() / 'Downloads'
if downloads.is_symlink(): sys.exit(2)
downloads.mkdir(mode=0o700, exist_ok=True)
if not downloads.is_dir(): sys.exit(2)
folder = downloads / ('riftlet-host-' + sys.argv[1])
folder.mkdir(mode=0o700)
with (folder / 'marker').open('xb') as out: out.write(Path(sys.argv[2]).read_bytes())
sys.exit(0 if (folder / 'marker').read_bytes() == Path(sys.argv[2]).read_bytes() else 3)
"""
    try:
        outcome = command([sys.executable, "-B", "-c", program, nonce, root / "control/marker"], timeout=10)
        return outcome.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def run(report):
    nonce = str(uuid4())
    root = Path(os.environ["RUNNER_TEMP"]).resolve() / ("riftlet-identity-host-" + nonce)
    root.mkdir(mode=0o700)
    (root / "control").mkdir()
    (root / "installed").mkdir()
    sentinel = root / "control/marker"
    sentinel.write_bytes(os.urandom(32))
    initial_hash = sha(sentinel)
    marker_ready = prepare_marker(root, nonce)
    (root / "fixture.json").write_text(json.dumps({"nonce": nonce, "markerReady": marker_ready, "markerSHA256": initial_hash}))
    report["syntheticDownloadsMarkerPrepared"] = marker_ready
    owner = REPO / "Sources/RiftletApp/FirstUsePreferences.swift"
    report["productionFolderAccessSourceSHA256"] = sha(owner)
    for name, inputs in (("probe", [owner, HERE / "Probe.swift"]), ("observer", [HERE / "ObserveUI.swift"]),
                         ("preflight", [REPO / "scripts/check-update-identity.swift"])):
        checked(["/usr/bin/xcrun", "swiftc", *inputs, "-o", root / name], "COMPILE_" + name.upper())
    old = make_bundle(root, root / "probe", nonce, "1")
    new = make_bundle(root, root / "probe", nonce, "2")
    tool = root / "preflight"
    report["codeIdentity"] = {"v1ToV2": compare_identity(tool, old, new, 2),
                              "v2ToV1": compare_identity(tool, new, old, 2)}
    pids = []
    installed = stage_app(root, old, "initial")
    for phase, action in PHASES:
        if phase in ("v2-update", "rollback-v1"):
            installed = stage_app(root, new if phase == "v2-update" else old, phase)
        result, pid = launch(root, installed, nonce, phase, action, root / "observer")
        report["phases"].append(result)
        if pid is not None:
            pids.append(pid)
        if not result["settled"]:
            report["state"] = "NOT_RUN_UNSETTLED_LAUNCH"
            return
        if not result["observations"].get("verifiedSameInstalledPath"):
            report["state"] = "NOT_RUN_NO_VERIFIED_LAUNCH"
            return
    report["distinctFreshProcesses"] = len(set(pids)) == len(PHASES)
    report["dataSentinelUnchanged"] = sha(sentinel) == initial_hash
    report["appOnlyRollbackRestoredExactV1"] = bundle_files(installed) == bundle_files(old)
    if not (report["distinctFreshProcesses"] and report["dataSentinelUnchanged"] and report["appOnlyRollbackRestoredExactV1"]):
        raise HarnessFailure("ROLLBACK_OR_PROCESS_INVARIANT_FAILED")
    observed = {item["phase"]: item for item in report["phases"]}
    def direct(phase):
        return observed[phase]["observations"].get("protectedDirect", {}).get("state", "NOT_RUN")
    def native(phase):
        return observed[phase]["ui"].get("state") == "AX_PRESS_SENT"
    report["v1NativeAllowAndVerifiedRead"] = native("v1-initial") and direct("v1-initial") == "READ_VERIFIED"
    report["v2NativeDenyAndFailedRead"] = native("v2-update") and direct("v2-update") == "READ_FAILED"
    previous = observed["v2-update"]["observations"].get("protectedBookmark", {})
    report["originalV1BookmarkRecoveryAfterObservedDeny"] = bool(report["v2NativeDenyAndFailedRead"]
        and previous.get("matchesFirstSavedBookmark") and previous.get("matchesFolder")
        and previous.get("afterProductionRestore", {}).get("state") == "READ_VERIFIED")
    recovery = observed["v2-picker"]["observations"].get("picker", {})
    report["nativeFolderRecoveryAfterObservedDeny"] = bool(report["v2NativeDenyAndFailedRead"]
        and recovery.get("state") == "EXACT_NATIVE_SELECTION"
        and recovery.get("save", {}).get("afterSave", {}).get("state") == "READ_VERIFIED")
    restored = observed["v1-restart"]["observations"].get("protectedBookmark", {})
    report["v1FreshProcessRestoredOriginalBookmarkAndRead"] = bool(restored.get("matchesFirstSavedBookmark")
        and restored.get("matchesFolder") and restored.get("afterProductionRestore", {}).get("state") == "READ_VERIFIED")
    report["rollbackDirectRead"] = direct("rollback-v1")
    report["everyPhaseCompletedNaturally"] = all(item["observations"].get("completed")
        and not item["requiredOwnTermination"] and item["launchServicesExit"] == 0 for item in report["phases"])
    report["nativeConsentTrials"] = {
        "firstAllow": "OBSERVED_BUTTON_AND_READ" if report["v1NativeAllowAndVerifiedRead"] else "NOT_RUN_OR_UNCONFIRMED",
        "updatedDeny": "OBSERVED_BUTTON_AND_READ_FAILURE" if report["v2NativeDenyAndFailedRead"] else "NOT_RUN_OR_UNCONFIRMED",
        "folderRecovery": "VERIFIED" if report["nativeFolderRecoveryAfterObservedDeny"] else "NOT_RUN_OR_UNCONFIRMED",
    }
    if not marker_ready:
        report["state"] = "NOT_RUN_PROTECTED_MARKER_UNAVAILABLE"
    elif not all((report["v1NativeAllowAndVerifiedRead"], report["v2NativeDenyAndFailedRead"],
                  report["v1FreshProcessRestoredOriginalBookmarkAndRead"], report["nativeFolderRecoveryAfterObservedDeny"],
                  report["rollbackDirectRead"] == "READ_VERIFIED", report["everyPhaseCompletedNaturally"])):
        report["state"] = "PARTIAL_NATIVE_CONSENT_OR_RECOVERY_UNCONFIRMED"
    else:
        report["state"] = "COMPLETED_SCOPED"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if (sys.platform != "darwin" or os.getenv("GITHUB_ACTIONS") != "true"
            or os.getenv("RUNNER_ENVIRONMENT") != "github-hosted" or os.getenv("RUNNER_OS") != "macOS"):
        print("NOT_RUN_REQUIRES_DISPOSABLE_GITHUB_HOSTED_MACOS")
        return 2
    report = {"schemaVersion": 1, "state": "STARTED", "phases": [], "signingClass": "isolatedAdHoc",
              "productionAppOrDataUsed": False, "directTCCDatabaseOrSystemSettingsAccess": False,
              "permissionInjection": False, "firstPermissionSource": "NOT_PROVEN_BY_FILE_READ",
              "controlBookmarkSource": "programmatic selection of an already-owned unprotected control directory",
              "protectedBookmarkSource": "exact normal NSOpenPanel selection only; no bookmark is imported",
              "developerIDSamples": 0}
    try:
        run(report)
        code = 0
    except Exception as error:
        report["state"] = "HARNESS_FAILED"
        report["failure"] = str(error) if isinstance(error, HarnessFailure) else type(error).__name__
        code = 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as stream:
        json.dump(report, stream, sort_keys=True, indent=2)
        stream.write("\n")
    print("release-identity-host:", report["state"])
    return code


if __name__ == "__main__":
    raise SystemExit(main())
