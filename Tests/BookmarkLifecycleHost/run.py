"""Run one disposable macOS GUI experiment. No browser, TCC database, policy or release output."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
from uuid import uuid4
import zlib

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
spec = importlib.util.spec_from_file_location("identity_host", HERE.parent / "ReleaseIdentityHost/run.py")
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)
owned = identity.owned_processes


class Stop(Exception):
    pass


def check(command, reason, timeout=45):
    run = subprocess.run(command, capture_output=True, timeout=timeout)
    if run.returncode:
        raise Stop(reason)
    return run.stdout


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(root):
    package = root / "package"
    (package / "Sources/Probe").mkdir(parents=True)
    shutil.copyfile(HERE / "Package.fixture", package / "Package.swift")
    for name in ["CSQLite", "RiftletCore", "RiftletCapture"]:
        shutil.copytree(REPO / "Sources" / name, package / "Sources" / name)
    shutil.copyfile(REPO / "Sources/RiftletApp/FirstUsePreferences.swift", package / "Sources/Probe/FirstUsePreferences.swift")
    shutil.copyfile(HERE / "Probe.swift", package / "Sources/Probe/Probe.swift")
    build_args = ["swift", "build", "--package-path", str(package), "-c", "release"]
    check(build_args + ["--product","Probe"], "FIXTURE_BUILD_FAILED", 360)
    bindir = Path(check(build_args + ["--show-bin-path"], "FIXTURE_BINDIR_FAILED").decode().strip())
    check(["swiftc", "-O", HERE / "Observer.swift", "-o", root / "observer"], "OBSERVER_BUILD_FAILED", 100)
    return bindir / "Probe"


def app(root, binary, token, role):
    name = {"book":"Riftlet Bookmarks ", "docallow":"Riftlet Files Allow ", "docdeny":"Riftlet Files Deny ",
            "aeallow":"Riftlet Consent Allow ", "aedeny":"Riftlet Consent Deny ", "receiver":"Riftlet Receiver "}[role] + token
    bundle = root / (role + ".app")
    exe = bundle / "Contents/MacOS/Probe"
    exe.parent.mkdir(parents=True)
    shutil.copy2(binary, exe)
    info = {"CFBundleName":name, "CFBundleDisplayName":name, "CFBundleIdentifier":"org.riftlet.scopedlab." + role + "." + token,
            "CFBundleExecutable":"Probe","CFBundlePackageType":"APPL", "CFBundleShortVersionString":"1.0", "CFBundleVersion":"1",
            "FixtureNonce":token, "FixtureRole":role, "LSUIElement":True}
    rights = {}
    if role == "book":
        rights = {"com.apple.security.app-sandbox":True, "com.apple.security.files.user-selected.read-only":True,
                  "com.apple.security.files.bookmarks.app-scope":True}
    if role.startswith("doc"):
        info["NSDocumentsFolderUsageDescription"] = "Check access to a disposable test file."
    if role.startswith("ae"):
        info["NSAppleEventsUsageDescription"] = "Check access to an isolated test utility."
        rights = {"com.apple.security.automation.apple-events":True}
    if role == "receiver":
        info["NSAppleScriptEnabled"] = True
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    run = ["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", "--options", "runtime"]
    if rights:
        ent = root / (role + ".plist")
        ent.write_bytes(plistlib.dumps(rights))
        run += ["--entitlements", ent]
    check(run + [bundle], "SIGN_FAILED")
    check(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", bundle], "INVALID_SIGNATURE")
    extracted = check(["/usr/bin/codesign","--display","--entitlements",":-",bundle], "CANNOT_READ_SIGNED_ENTITLEMENTS")
    if (plistlib.loads(extracted) if extracted.strip() else {}) != rights:
        raise Stop("SIGNED_ENTITLEMENTS_DIFFER")
    return bundle


def events(file, token):
    try:
        raw = file.read_bytes()
    except FileNotFoundError:
        return []
    result = []
    for line in raw.splitlines():
        try:
            row = json.loads(line)
        except (ValueError, UnicodeError):
            continue
        if row.get("token") == token and type(row.get("pid")) is int and row["pid"] > 1:
            result.append(row)
    return result


def launch_events(file, token, role, phase, expected_pid):
    rows = events(file, token)
    if not rows:
        return rows
    pid = rows[0]["pid"] if expected_pid is None else expected_pid
    if (rows[0].get("stage") != "launched" or any(row["pid"] != pid or row.get("role") != role
            or row.get("phase") != phase or not isinstance(row.get("facts"), dict) for row in rows)):
        raise Stop("UNVERIFIED_OUTPUT_IDENTITY")
    return rows


def png(seed):
    def chunk(kind, value):
        return struct.pack(">I",len(value)) + kind + value + struct.pack(">I",zlib.crc32(kind + value))
    line = b"\0" + bytes([seed,95,220,255]) * 96
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR",struct.pack(">2I5B",96,72,8,6,0,0,0))
            + chunk(b"IDAT",zlib.compress(line * 72)) + chunk(b"IEND",b""))


def drop(source, seed):
    data = png(seed)
    temp = source.parent / ("incoming-" + str(seed))
    temp.write_bytes(data)
    check(["/usr/bin/xattr","-wx","com.apple.metadata:kMDItemIsScreenCapture",
           plistlib.dumps(True,fmt=plistlib.FMT_BINARY).hex(),temp], "MARK_FIXTURE_FAILED")
    dest = source / ("Screenshot-" + str(seed) + ".png")
    temp.rename(dest)
    return dest


def terminate_exact(executable):
    for pid in owned(executable):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and owned(executable):
        time.sleep(0.08)
    for pid in owned(executable):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class Lab:
    def __init__(self, root, neutral, token, binary):
        self.root, self.neutral, self.token, self.binary = root,neutral,token,binary
        self.pids = []
        self.apps = {}

    def bundle(self, role):
        if role not in self.apps:
            self.apps[role] = app(self.root, self.binary, self.token, role)
        return self.apps[role]

    @contextmanager
    def launch(self, role, phase, member="none", expected="-", receiver=0):
        bundle = self.bundle(role)
        exe = bundle / "Contents/MacOS/Probe"
        if owned(exe):
            raise Stop("IDENTITY_ALREADY_RUNNING")
        out = self.root / (str(uuid4()) + ".ndjson")
        out.touch(mode=0o600)
        # Only the app is opened. No source directory or marker is passed as a document.
        process = subprocess.Popen(["/usr/bin/open","-n","-W","--stdout",out,"--stderr","/dev/null",bundle,
                                    "--args",self.neutral,self.root,phase,member,expected,str(receiver)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            yield process,out,exe
        finally:
            terminate_exact(exe)
            if process.poll() is None:
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=3)

    def exercise(self, role, phase, member="none", expected="-", action=None, seed=None, receiver=0, on_watch=None):
        result = {"role":role, "phase":phase, "action":"NOT_RUN", "state":"NO_VERIFIED_LAUNCH", "facts":{}}
        with self.launch(role,phase,member,expected,receiver) as (process,out,exe):
            deadline = time.monotonic() + 22
            injected = False
            observed = False
            pid = None
            def accept_done(row):
                result.update(state="FINISHED", facts=row["facts"], sampledOwnedProcess=observed,
                              distinctPID=pid not in self.pids[:-1] if observed else pid not in self.pids)
                if not observed:
                    self.pids.append(pid)
            while time.monotonic() < deadline:
                rows = launch_events(out,self.token,role,phase,pid)
                if rows:
                    pid = rows[0]["pid"]
                    if not observed and pid in owned(exe):
                        observed = True
                        self.pids.append(pid)
                    # Fast phases can exit between launch and PID inspection. The emitter is an inherited
                    # stdout of this exact verified LS app and attests its own role/path at startup.
                    last = rows[-1]
                    if last["stage"] == "done":
                        accept_done(last)
                        break
                    if action and result["action"] == "NOT_RUN" and observed:
                        expected_stage = {"select":"showingPanel","settings":"recovering"}.get(action, "reading" if role.startswith("doc") else "requesting")
                        if last["stage"] == expected_stage:
                            try:
                                r=check([self.root/"observer",self.token,role,str(pid),action,self.bundle(role),out],"OBSERVATION_FAILED",10)
                                result["action"] = json.loads(r)
                            except (Stop,subprocess.TimeoutExpired):
                                result["action"] = {"state":"OBSERVATION_UNAVAILABLE"}
                    if last["stage"] == "watching" and seed is not None and not injected:
                        drop(self.neutral / member, seed)
                        injected = True
                    if last["stage"] == "watching" and on_watch is not None and not injected:
                        on_watch()
                        injected = True
                if process.poll() is not None:
                    # open -W has joined the writer. An AX action may have completed
                    # while the observer held the loop, so inspect the final receipt.
                    final = launch_events(out,self.token,role,phase,pid)
                    result["receiptReadAfterExit"] = True
                    if final and final[-1]["stage"] == "done":
                        pid = final[0]["pid"]
                        accept_done(final[-1])
                    elif final:
                        result.update(state="UNKNOWN_NO_TERMINAL_RECEIPT", facts=final[-1]["facts"])
                    break
                time.sleep(0.11)
            else:
                result.update(state="BOUNDED_STOP", facts=rows[-1]["facts"] if rows else {})
            result["fixtureInjectedAfterWatch"] = injected
            if observed:
                result["sampledOwnedProcess"] = True
        return result


def matched(result):
    return result.get("state") == "FINISHED" and result["facts"].get("failure") is None


def pressed(result):
    a=result.get("action")
    return isinstance(a,dict) and a.get("state") in {"PRESS_ACK","PRESS_UNCONFIRMED"}


def denied_read(facts):
    return any((e["domain"] == "NSCocoaErrorDomain" and e["code"] == 257)
               or (e["domain"] == "NSPOSIXErrorDomain" and e["code"] in (1,13)) for e in facts.get("read",{}).get("codes",[]))


def captured(result, previous):
    f=result["facts"]
    return (matched(result) and result.get("fixtureInjectedAfterWatch") and result.get("distinctPID")
            and f.get("owner") == "MATCHING" and f.get("bookmarkAfter") == f.get("bookmarkBefore")
            and f.get("watchRunning") and f.get("watchReadable") and f.get("privateCopyMatches")
            and f.get("rowsBefore") == previous and f.get("rowsAfter") == previous+1)


def bookmark(lab,report):
    a,m=lab.neutral/"A",lab.neutral/"M"
    a.mkdir()
    original=b"synthetic original marker"
    replacement=b"synthetic replacement marker"
    (a/"marker").write_bytes(original)
    run=lab.exercise
    phases=report["phases"]
    def note(label,out):
        phases[label]=out
        return out["facts"]
    first=run("book","select","A",sha(original),action="select")
    f=note("initialSelection",first)
    if not (matched(first) and pressed(first) and f.get("panel")=="CONFIRMED_EXACT_FOLDER" and f.get("afterSelectionRead",{}).get("state")=="MATCH"):
        report["state"]="PARTIAL_INITIAL_PANEL"; return
    report["initialGrantObserved"]=True
    report["initialSandboxReadDenied"]=denied_read({"read":f.get("beforeSelectionRead",{})})
    saved=f.get("bookmarkAfter")
    if not isinstance(saved,str) or len(saved)!=64:
        report["state"]="PARTIAL_NO_SAVED_BOOKMARK"; return
    one=run("book","capture","A",sha(png(31)),seed=31)
    note("initialNewProcessImport",one)
    report["firstImport"]=captured(one,0)

    original_inode=a.stat().st_ino
    def replace():
        a.rename(m)
        time.sleep(0.18)
        a.mkdir()
        (a/"marker").write_bytes(replacement)
        drop(a,43)
    live=run("book","live","A",sha(png(43)),on_watch=replace)
    livefacts=note("replaceWhileWatching",live)
    report["liveWatcherBlocked"]=(matched(live) and live.get("fixtureInjectedAfterWatch") and livefacts.get("owner")=="MATCHING"
        and livefacts.get("watchRunning") and livefacts.get("watchReadable") and livefacts.get("runningAfterReplacement") is False
        and livefacts.get("accessibleAfterReplacement") is False and livefacts.get("rowsBefore")==livefacts.get("passiveRows")==livefacts.get("rowsAfter"))
    if not m.exists():
        replace()
    report["differentDirectoryAtOriginalPath"]=(m.stat().st_ino==original_inode and (a.stat().st_dev,a.stat().st_ino)!=(m.stat().st_dev,m.stat().st_ino))
    # Positive OS facts for both paths are reported independently.
    note("movedOriginal",run("book","inspect","M",sha(original)))
    stale=note("replacement",run("book","inspect","A",sha(replacement)))
    denied=note("replacementCaptureAttempt",run("book","capture","A","unused",seed=52))
    report["replacementBlocked"]=(stale.get("owner")=="NEEDS_SELECTION" and stale.get("bookmarkBefore")==saved==stale.get("bookmarkAfter")
          and denied.get("owner")=="NEEDS_SELECTION" and denied.get("bookmarkBefore")==saved==denied.get("bookmarkAfter")
          and denied.get("watchRunning") is False and denied.get("rowsBefore")==denied.get("rowsAfter"))
    # Invalidate both original names without deleting any fixture bytes. A genuinely unresolvable
    # bookmark is recorded only if Foundation reports an error; a relocated result is reported as such.
    witness=lab.neutral/"Witness"
    witness.mkdir()
    blocked_png=a/"Screenshot-43.png"
    if blocked_png.read_bytes()!=png(43):
        raise Stop("BLOCKED_ORIGINAL_BYTES_DIFFER")
    blocked_png.rename(witness/"blocked.png")
    for item in list(m.iterdir()):
        item.rename(witness/item.name)
    m.rmdir()
    a.rename(lab.neutral/"ReplacementWitness")
    missing=note("neitherNamedFolderExists",run("book","inspect","A",sha(replacement)))
    report["absentPathBlocks"]=missing.get("owner")=="NEEDS_SELECTION" and missing.get("bookmarkBefore")==saved==missing.get("bookmarkAfter")
    report["foundationUnresolvableObserved"]=bool(missing.get("rawResolution",{}).get("errors"))
    (lab.neutral/"ReplacementWitness").rename(a)
    second=run("book","select","A",sha(replacement),action="select")
    f=note("explicitReselection",second)
    report["reselected"]=(matched(second) and pressed(second) and f.get("panel")=="CONFIRMED_EXACT_FOLDER"
        and f.get("bookmarkBefore")==saved and f.get("bookmarkAfter") not in (None,"ABSENT",saved)
        and f.get("afterSelectionRead",{}).get("state")=="MATCH")
    if report["reselected"]:
        two=run("book","capture","A",sha(png(61)),seed=61)
        note("replacementNewProcessImport",two)
        report["secondImport"]=captured(two,1)
    report["originalsPreserved"]=((witness/"marker").read_bytes()==original and (a/"marker").read_bytes()==replacement
        and (witness/"blocked.png").read_bytes()==png(43)
        and (not report["firstImport"] or (witness/"Screenshot-31.png").read_bytes()==png(31))
        and (not report["secondImport"] or (a/"Screenshot-61.png").read_bytes()==png(61)))
    report["state"]="COMPLETED_SCOPED" if all(report.get(k) for k in ("initialSandboxReadDenied","firstImport",
        "differentDirectoryAtOriginalPath","liveWatcherBlocked","replacementBlocked","absentPathBlocks","reselected","secondImport","originalsPreserved")) else "PARTIAL_BOOKMARK"


def permission(lab,report,files,pid=0):
    marker=b"synthetic protected Documents marker"
    if files:
        documents=Path.home()/"Documents"
        protected=documents/("Riftlet-Files-"+lab.token)
        write_documents_marker(protected,marker)
    phases=report["phases"]
    for action in ("allow","deny"):
        role=("doc" if files else "ae")+action
        probe=lab.exercise(role,"read" if files else "request",expected=sha(marker),action=action,receiver=pid)
        phases[action]=probe
        f=probe["facts"]
        if files:
            outcome=f.get("read",{}).get("state")=="MATCH" if action=="allow" else denied_read(f)
            report[action]="OBSERVED_PROMPT_AND_DECISION" if matched(probe) and pressed(probe) and outcome else (
                "READ_WITHOUT_OBSERVED_PROMPT" if matched(probe) and f.get("read",{}).get("state")=="MATCH" else "NOT_VERIFIED")
        else:
            status=0 if action=="allow" else -1743
            verified=(f.get("receiverVerified") is True and f.get("before")==-1744 and f.get("request")==status and f.get("after")==status)
            report[action]="OBSERVED_PROMPT_AND_DECISION" if matched(probe) and pressed(probe) and verified else "NOT_VERIFIED"
    if report["deny"]=="OBSERVED_PROMPT_AND_DECISION":
        role="docdeny" if files else "aedeny"
        persisted=lab.exercise(role,"read" if files else "passive",expected=sha(marker),receiver=pid)
        phases["freshDeniedProcess"]=persisted
        f=persisted["facts"]
        report["deniedInFreshProcess"]=bool(matched(persisted) and persisted.get("distinctPID") and
            (denied_read(f) if files else f.get("receiverVerified") is True and f.get("before")==f.get("after")==-1743))
        if report["deniedInFreshProcess"]:
            settings=lab.exercise(role,"settings",action="settings",receiver=pid)
            phases["systemSettings"]=settings
            if matched(settings) and settings["facts"].get("openedSettings") and pressed(settings):
                after=lab.exercise(role,"read" if files else "passive",expected=sha(marker),receiver=pid)
                phases["freshAfterSettings"]=after
                f=after["facts"]
                positive=f.get("read",{}).get("state")=="MATCH" if files else f.get("receiverVerified") is True and f.get("before")==f.get("after")==0
                report["recovery"]="OBSERVED_SETTINGS_ACTION_AND_NEW_PROCESS_GRANT" if matched(after) and after.get("distinctPID") and positive else "ACTION_WITHOUT_VERIFIED_GRANT"
    report["state"]="COMPLETED_SCOPED" if (report["allow"]==report["deny"]=="OBSERVED_PROMPT_AND_DECISION" and report["deniedInFreshProcess"]
                      and report["recovery"]=="OBSERVED_SETTINGS_ACTION_AND_NEW_PROCESS_GRANT") else "PARTIAL_CONSENT"


def automation(lab,report):
    with lab.launch("receiver","serve") as (proc,out,exe):
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            rows=events(out,lab.token)
            if rows and rows[-1]["stage"]=="serving" and rows[-1]["pid"] in owned(exe):
                report["ownedTestReceiver"]=True
                return permission(lab,report,False,rows[-1]["pid"])
            if proc.poll() is not None:
                break
            time.sleep(0.15)
        raise Stop("NO_VERIFIED_RUNNING_TEST_RECEIVER")

def write_documents_marker(folder, data):
    # The test driver may have inherited access, or it may itself be unable to
    # prepare the fixture. Bound that independent operation before testing senders.
    code = """import os, pathlib, sys
parent=pathlib.Path.home()/'Documents'
target=pathlib.Path(sys.argv[1])
assert target.parent==parent and target.name.startswith('Riftlet-Files-') and not parent.is_symlink()
target.mkdir(mode=0o700)
with (target/'marker').open('xb') as f:
    f.write(sys.argv[2].encode('ascii'))
"""
    check([sys.executable,"-c",code,folder,data.decode("ascii")], "DOCUMENTS_MARKER_UNAVAILABLE",8)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--product",required=True)
    args=parser.parse_args()
    if (sys.platform!="darwin" or os.getenv("GITHUB_ACTIONS")!="true" or os.getenv("RUNNER_OS")!="macOS"
        or os.getenv("RUNNER_ENVIRONMENT")!="github-hosted" or os.getenv("GITHUB_REPOSITORY")!="haohongfei2001-png/Riftlet"
        or os.getenv("GITHUB_EVENT_NAME")!="workflow_dispatch"):
        print("NOT_RUN_REQUIRES_DISPOSABLE_MANUAL_RUN")
        return 2
    report={"version":1, "product":args.product, "experiment":os.getenv("GITHUB_SHA"), "browserAccess":False,
            "directTCCDatabaseAccess":False, "systemPolicyEdits":False, "systemCapturePreferenceEdits":False,
            "consentEnvironment":"disposable GitHub-hosted console user", "scopedFiles":{}, "protocols":{}}
    code=0
    try:
        actual=check(["git","rev-parse","HEAD"],"NO_CHECKOUT").decode().strip()
        if actual!=os.getenv("GITHUB_SHA") or len(args.product)!=40:
            raise Stop("CHECKOUT_MISMATCH")
        check(["git","merge-base","--is-ancestor",args.product,actual],"WRONG_PRODUCT_ANCESTRY")
        for scope in ("Sources","Package.swift"):
            check(["git","diff","--quiet",args.product,actual,"--",scope],"PRODUCT_SOURCE_MISMATCH")
        if os.stat("/dev/console").st_uid != os.getuid() or os.getuid()==0:
            raise Stop("NO_INDEPENDENT_CONSOLE_USER")
        temp=Path(os.environ["RUNNER_TEMP"]).resolve()
        if not temp.is_dir() or temp.is_symlink():
            raise Stop("RUNNER_TEMP_UNAVAILABLE")
        token=str(uuid4())
        root=temp/("riftlet-scoped-lab-"+token)
        root.mkdir(mode=0o700)
        neutral=Path.home()/("Riftlet-Bookmark-Lab-"+token)
        neutral.mkdir(mode=0o700)
        binary=build(root)
        report["scopedFiles"]={"fixtureBinary":sha(binary.read_bytes()), "observer":sha((root/"observer").read_bytes()),
            "folderOwner":sha((REPO/"Sources/RiftletApp/FirstUsePreferences.swift").read_bytes()), "captureService":sha((REPO/"Sources/RiftletCapture/CaptureService.swift").read_bytes())}
        lab=Lab(root,neutral,token,binary)
        # The previous run already observed these two separate consent protocols.
        # This focused successor only repeats the bookmark sequence with fixed receipt handling.
        report["omittedProtocols"] = ["documents", "automationTestPair"]
        result = {"state": "STARTED", "phases": {}, "initialGrantObserved": False, "firstImport": False, "secondImport": False}
        report["protocols"]["bookmark"] = result
        try:
            bookmark(lab, result)
        except (Stop, identity.HarnessFailure, subprocess.TimeoutExpired, OSError, ValueError) as error:
            result.update(state="STOPPED", cause=str(error) if isinstance(error, (Stop, identity.HarnessFailure)) else type(error).__name__)
        report["state"] = "COMPLETED_SCOPED_BOOKMARK" if result["state"] == "COMPLETED_SCOPED" else "PARTIAL_OR_UNAVAILABLE"
    except Exception as error:
        report.update(state="HARNESS_STOPPED",cause=str(error) if isinstance(error,Stop) else type(error).__name__)
        code=1
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open("x") as stream:
        json.dump(report,stream,indent=2,sort_keys=True)
        stream.write("\n")
    print(report["state"])
    return code


if __name__=="__main__":
    raise SystemExit(main())
