"""Exercise first Automation decisions on a disposable hosted Mac. This does not inspect browser pages."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
from uuid import uuid4

from run import HERE, REPO, HarnessFailure, checked, command, launch, make_bundle, owned_processes, sha, stage_app


def observed(phase, expected, *, recovery=False):
    facts = phase["observations"]
    return bool(phase["settled"] and phase["launchServicesExit"] == 0 and not phase["requiredOwnTermination"]
                and phase["ui"].get("state") == "AX_PRESS_SENT" and facts.get("completed")
                and facts.get("originalChromeStillCurrent") and facts.get("passiveAfter") == expected
                and (facts.get("passiveBefore") == "denied" and facts.get("settingsOpened") if recovery
                     else facts.get("passiveBefore") == "notRequested" and facts.get("requestResult") == expected))


def exercise(temp, binary, observer, chrome, session, decision, report):
    nonce = str(uuid4())
    root = temp / ("riftlet-automation-host-" + nonce)
    root.mkdir(mode=0o700)
    (root / "installed").mkdir()
    (root / "target.json").write_text(json.dumps({"nonce": nonce, "pid": chrome.pid, "session": session}))
    app = stage_app(root, make_bundle(root, binary, nonce, "1", automation=True), "initial")
    first, _ = launch(root, app, nonce, decision, "automation-" + decision, observer)
    report["phases"].append(first)
    expected = "granted" if decision == "allow" else "denied"
    confirmed = chrome.poll() is None and observed(first, expected)
    report[decision] = "OBSERVED_PROMPT_AND_DECISION" if confirmed else "NOT_RUN_OR_UNCONFIRMED"
    if decision != "deny" or not confirmed:
        return
    restarted, _ = launch(root, app, nonce, "denied-restart", None, observer)
    report["phases"].append(restarted)
    facts = restarted["observations"]
    persistent = bool(restarted["settled"] and restarted["launchServicesExit"] == 0
                      and not restarted["requiredOwnTermination"] and facts.get("completed")
                      and facts.get("originalChromeStillCurrent") and facts.get("passiveBefore") == "denied"
                      and facts.get("passiveAfter") == "denied" and chrome.poll() is None)
    report["deniedInFreshProcess"] = persistent
    if persistent:
        recovered, _ = launch(root, app, nonce, "settings-recovery", "automation-recovery", observer)
        report["phases"].append(recovered)
        if chrome.poll() is None and observed(recovered, "granted", recovery=True):
            report["recovery"] = "OBSERVED_SETTINGS_ACTION_AND_PASSIVE_GRANT"


def run(report):
    if os.stat("/dev/console").st_uid != os.getuid() or os.getuid() == 0:
        report["state"] = "NOT_RUN_NO_OWNED_GUI_SESSION"
        return
    app = Path("/Applications/Google Chrome.app")
    executable = app / "Contents/MacOS/Google Chrome"
    if not executable.is_file() or plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier") != "com.google.Chrome":
        report["state"] = "NOT_RUN_STANDARD_CHROME_UNAVAILABLE"
        return
    requirement = 'anchor apple generic and identifier "com.google.Chrome" and certificate leaf[subject.OU] = "EQHXZ8M8AV"'
    if command(["/usr/bin/codesign", "--verify", "--strict", "-R=" + requirement, app], timeout=30).returncode:
        report["state"] = "NOT_RUN_UNVERIFIED_CHROME_SIGNATURE"
        return
    if owned_processes(executable):
        report["state"] = "NOT_RUN_CHROME_ALREADY_RUNNING"
        return
    temp = Path(os.environ["RUNNER_TEMP"]).resolve()
    tools = temp / ("riftlet-automation-tools-" + str(uuid4()))
    tools.mkdir(mode=0o700)
    profile = tools / "empty-chrome-profile"
    profile.mkdir(mode=0o700)
    identity = REPO / "Sources/RiftletAdapters/ChromeProcessIdentity.swift"
    permission = REPO / "Sources/RiftletApp/AutomationPermission.swift"
    report["source"] = {"chromeIdentitySHA256": sha(identity), "permissionGateSHA256": sha(permission)}
    checked(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-emit-object", "-emit-module",
             "-emit-module-path", tools / "RiftletAdapters.swiftmodule", "-module-name", "RiftletAdapters",
             identity, "-o", tools / "identity.o"], "COMPILE_CHROME_IDENTITY")
    binary = tools / "probe"
    checked(["/usr/bin/xcrun", "swiftc", "-I", tools, permission, HERE / "AutomationProbe.swift", tools / "identity.o",
             "-o", binary], "COMPILE_AUTOMATION_PROBE")
    observer = tools / "observe"
    checked(["/usr/bin/xcrun", "swiftc", HERE / "ObserveUI.swift", "-o", observer], "COMPILE_AUTOMATION_OBSERVER")
    # A real Chrome receiver, one empty profile, no debugging port or navigation beyond startup.
    with subprocess.Popen([str(executable), "--user-data-dir=" + str(profile), "--disable-sync", "--disable-extensions",
                           "--disable-background-networking", "--disable-component-update", "--no-first-run",
                           "--no-default-browser-check", "about:blank"],
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as chrome:
        try:
            until = time.monotonic() + 8
            session = ""
            while chrome.poll() is None and time.monotonic() < until:
                result = command([binary, "--identify-chrome", str(chrome.pid)], timeout=3)
                if result.returncode == 0:
                    session = result.stdout.decode().strip()
                    if session.startswith(f"chrome-kernel-v1:{chrome.pid}:"):
                        break
                session = ""
                time.sleep(0.15)
            if not session or chrome.poll() is not None:
                report["state"] = "NOT_RUN_DEDICATED_CHROME_UNAVAILABLE"
                return
            report["verifiedOwnedChrome"] = True
            for decision in ("allow", "deny"):
                if chrome.poll() is not None:
                    break
                exercise(temp, binary, observer, chrome, session, decision, report)
                if any(not item["settled"] or item["requiredOwnTermination"] for item in report["phases"]):
                    break
            complete = (report["allow"] == report["deny"] == "OBSERVED_PROMPT_AND_DECISION"
                        and report["deniedInFreshProcess"] and report["recovery"] == "OBSERVED_SETTINGS_ACTION_AND_PASSIVE_GRANT")
            report["state"] = "COMPLETED_SCOPED" if complete else "PARTIAL_AUTOMATION_CONSENT"
        finally:
            if chrome.poll() is None:
                chrome.terminate()
                try:
                    chrome.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    chrome.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if (sys.platform != "darwin" or os.getenv("GITHUB_ACTIONS") != "true" or os.getenv("RUNNER_OS") != "macOS"
            or os.getenv("RUNNER_ENVIRONMENT") != "github-hosted" or os.getenv("GITHUB_REPOSITORY") != "haohongfei2001-png/Riftlet"):
        print("NOT_RUN_REQUIRES_DISPOSABLE_PROJECT_RUNNER")
        return 2
    report = {"schemaVersion": 1, "service": "Automation to dedicated Google Chrome", "state": "STARTED",
              "allow": "NOT_RUN", "deny": "NOT_RUN", "deniedInFreshProcess": False, "recovery": "NOT_RUN",
              "phases": [], "verifiedOwnedChrome": False, "browserPageAccess": False, "tccDatabaseAccess": False}
    try:
        run(report)
        code = 0
    except Exception as error:
        report["state"] = "HARNESS_FAILED"
        report["failure"] = str(error) if isinstance(error, HarnessFailure) else type(error).__name__
        code = 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print("automation-consent:", report["state"])
    return code


if __name__ == "__main__":
    raise SystemExit(main())
