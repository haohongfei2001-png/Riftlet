#!/usr/bin/env python3
"""Build and verify the notarized outer DMG of an already stapled Riftlet release."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid

spec = importlib.util.spec_from_file_location("riftlet_release", Path(__file__).with_name("release-tool.py"))
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)
require = R.require
DMG_ID = "com.riftlet.app.distribution-dmg"


def new_attempt(folder, prefix):
    return Path(tempfile.mkdtemp(prefix=prefix, dir=folder))


def same_bytes(path, pin):
    require(path.is_file() and not path.is_symlink() and R.digest(path) == pin, "dmg_bytes_mismatch")


def ticket(path, log):
    R.run(["xcrun", "stapler", "validate", "-v", path], log=log)


def assess(path, kind, attempt):
    enabled = R.run(["/usr/sbin/spctl", "--status"], log=attempt / ("gatekeeper-" + kind + "-status.log"))
    require(enabled.stdout.strip() == b"assessments enabled", "gatekeeper_assessment_disabled")
    cmd = ["/usr/sbin/spctl", "--assess", "--type", kind, "--raw"]
    if kind == "open": cmd += ["--context", "context:primary-signature"]
    result = R.run([*cmd, path], log=attempt / ("gatekeeper-" + kind + ".log"))
    require(plistlib.loads(result.stdout).get("assessment:verdict") is True, "gatekeeper_verdict_not_accepted")


def verify_app_tree(app, manifest):
    require(app.is_dir() and not app.is_symlink(), "dmg_app_missing_or_linked")
    expected = {name[len(R.APP) + 1:]: row for name, row in manifest["files"].items()
                if name.startswith(R.APP + "/")}
    root = manifest["files"][R.APP]
    require(root["kind"] == "directory" and root["mode"] == stat.S_IMODE(app.stat().st_mode)
            and root["xattrs"] == R.xattr_hashes(app), "dmg_app_root_mismatch")
    # inventory() exempts the manifest at the root of a *release package*. An
    # extra file by the same name in the actual App is not a release manifest.
    require(not os.path.lexists(app / R.MANIFEST) and R.inventory(app) == expected,
            "dmg_app_inventory_mismatch")
    R.verify_app_modes(manifest["files"])


def image_signature(image, team, log):
    req = ('anchor apple generic and identifier "' + DMG_ID + '" and certificate leaf[subject.OU] = "' +
           team + '" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and '
           'certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
    R.run(["/usr/bin/codesign", "--verify", "--strict", "-R", "=" + req, image], log=log / "dmg-signature-check.log")
    text = R.run(["/usr/bin/codesign", "-d", "--verbose=4", image],
                 log=log / "dmg-signature-details.log").stderr.decode()
    def field(key):
        values = re.findall("^" + key + "=(.+)$", text, re.M)
        require(len(values) == 1, "dmg_missing_signature_" + key)
        return values[0]
    timestamp, cdhash = field("Timestamp"), field("CDHash")
    require(field("Identifier") == DMG_ID and field("TeamIdentifier") == team
            and re.search(r"^Authority=Developer ID Application:", text, re.M)
            and timestamp not in {"none", "Not set"} and re.fullmatch(r"[0-9a-f]{40}", cdhash),
            "dmg_developer_id_signature_mismatch")
    return {"identifier": DMG_ID, "teamID": team, "cdhash": cdhash, "timestamp": timestamp}


def build_image(app, manifest, image, attempt):
    source = attempt / "image-source"
    source.mkdir(mode=0o700)
    R.run(["/usr/bin/ditto", "--rsrc", "--extattr", app, source / R.APP], log=attempt / "copy.log")
    verify_app_tree(source / R.APP, manifest)
    (source / "Applications").symlink_to("/Applications")
    # The source directory becomes the mounted volume root. Its parent is the
    # private attempt directory; do not change any workspace or submission modes.
    source.chmod(0o755)
    os.lchmod(source / "Applications", 0o755)
    R.run(["/usr/bin/hdiutil", "create", "-format", "UDZO", "-fs", "HFS+", "-volname", "Riftlet",
           "-srcfolder", source, image], timeout=300, log=attempt / "image-create.log")


def inspect_image(image, manifest, attempt):
    R.run(["/usr/bin/hdiutil", "verify", image], log=attempt / "image-verify.log")
    mount = new_attempt(attempt, "mount-")
    try:
        reply = R.run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                       "-mountpoint", mount, "-plist", image], log=attempt / "mount.log")
        points = [e["mount-point"] for e in plistlib.loads(reply.stdout)["system-entities"] if e.get("mount-point")]
        require(points == [str(mount)] and os.path.ismount(mount)
                and os.statvfs(mount).f_flag & os.ST_RDONLY, "dmg_wrong_or_writable_mount")
        require(stat.S_IMODE(mount.stat().st_mode) == 0o755, "dmg_volume_root_mode_mismatch")
        entries = {p.name for p in mount.iterdir()}
        require(entries == {R.APP, "Applications"}, "dmg_unexpected_root_entries")
        link = mount / "Applications"
        require(link.is_symlink() and os.readlink(link) == "/Applications", "dmg_applications_link_mismatch")
        require(stat.S_IMODE(link.lstat().st_mode) == 0o755, "dmg_applications_link_mode_mismatch")
        app = mount / R.APP
        verify_app_tree(app, manifest)
        signature = manifest["signature"]
        require(R.verify_signature(app, signature["teamID"], manifest["build"]["architectures"]) == signature,
                "dmg_embedded_app_signature_mismatch")
        ticket(app, attempt / "embedded-ticket.log")
        assess(app, "execute", attempt)
    finally:
        if os.path.ismount(mount):
            R.run(["/usr/bin/hdiutil", "detach", mount], log=attempt / "detach.log")
        require(not os.path.ismount(mount), "dmg_mount_still_attached")


def create(args, folder, package, manifest, identity):
    R.credential_values(args.identity, args.team, signing=True)
    R.identity_available(args.identity, args.team)
    require(not (folder / "state.json").exists(), "dmg_state_already_exists")
    attempt = new_attempt(folder, "create-")
    image = attempt / identity["name"]
    build_image(package / R.APP, manifest, image, attempt)
    R.run(["/usr/bin/codesign", "--sign", args.identity, "--timestamp", "--identifier", DMG_ID, image],
          timeout=180, log=attempt / "dmg-sign.log")
    signature = image_signature(image, args.team, attempt)
    inspect_image(image, manifest, attempt)
    state = {**identity, "stage": "SIGNED", "signedImage": str(image.relative_to(folder)),
             "signedSHA256": R.digest(image), "signature": signature, "submissionID": None}
    R.verify_package(package, args.manifest_sha256, args.team)
    R.write_json(folder / "state.json", state)
    return state


def signed_image(folder, state):
    relative = Path(state["signedImage"])
    require(len(relative.parts) == 2 and relative.parts[0].startswith("create-")
            and relative.name == state["name"], "invalid_signed_dmg_location")
    image = R.safe_path(folder / relative)
    same_bytes(image, state["signedSHA256"])
    return image


def submit(args, folder, state):
    R.credential_values(profile=args.profile, notary=True)
    require(state["stage"] == "SIGNED", "dmg_submit_requires_signed_once")
    source = signed_image(folder, state)
    attempt = new_attempt(folder, "submit-")
    require(image_signature(source, args.team, attempt) == state["signature"], "dmg_signature_changed")
    upload = attempt / state["name"]
    shutil.copyfile(source, upload)
    upload.chmod(0o400)
    same_bytes(upload, state["signedSHA256"])
    state.update(stage="SUBMITTING", submissionCopy=str(upload.relative_to(folder)))
    R.write_json(folder / "state.json", state)
    try:
        same_bytes(source, state["signedSHA256"])
        same_bytes(upload, state["signedSHA256"])
    except (OSError, R.ReleaseError) as error:
        R.write_json(attempt / "not-submitted.json", {"clientInvoked": False, "reason": "pre_submit_dmg_changed"})
        state.update(stage="SIGNED", submissionID=None)
        R.write_json(folder / "state.json", state)
        raise R.ReleaseError("pre_submit_dmg_changed", "NOT_SUBMITTED") from error
    try:
        output = R.run(["xcrun", "notarytool", "submit", upload, "--keychain-profile", args.profile,
                        "--output-format", "json"], timeout=180, log=attempt / "submit.log")
        reply = R.decode_json(output.stdout)
        identifier = str(uuid.UUID(reply["id"]))
        require(identifier != state["appSubmissionID"], "dmg_requires_independent_notary_job")
    except Exception as error:
        state["stage"] = "SUBMISSION_UNKNOWN"
        R.write_json(folder / "state.json", state)
        raise R.ReleaseError("dmg_submission_uncertain_query_original_job", "NOTARY_SUBMISSION_UNKNOWN") from error
    state.update(stage="IN_PROGRESS", submissionID=identifier)
    R.write_json(folder / "state.json", state)
    return state


def verify_log(log, identifier, pin, status):
    require(isinstance(log, dict) and log.get("jobId") == identifier and log.get("status") == status
            and str(log.get("sha256", "")).lower() == pin, "dmg_notary_log_artifact_mismatch")


def status(args, folder, state):
    R.credential_values(profile=args.profile, notary=True)
    require(state["stage"] in {"SUBMITTING", "SUBMISSION_UNKNOWN", "IN_PROGRESS"}, "dmg_query_wrong_stage")
    old = state["submissionID"]
    require(old or args.submission_id, "original_dmg_submission_id_required", "BLOCKED_RECONCILIATION")
    identifier = str(uuid.UUID(args.submission_id or old))
    require(identifier != state["appSubmissionID"] and (not old or old == identifier), "dmg_wrong_notary_job")
    attempt = new_attempt(folder, "query-")
    output = R.run(["xcrun", "notarytool", "info", identifier, "--keychain-profile", args.profile,
                    "--output-format", "json"], log=attempt / "info.log")
    info = R.decode_json(output.stdout)
    require(info.get("id") == identifier and info.get("status") in {"Accepted", "Invalid", "In Progress"},
            "dmg_notary_info_mismatch")
    if info["status"] == "In Progress":
        # An ID supplied after a lost reply is not bound to this DMG until the
        # terminal Apple log confirms its exact uploaded SHA-256.
        return {**state, "queriedSubmissionID": identifier, "queryStatus": "In Progress"}
    logfile = attempt / "notary-log.json"
    R.run(["xcrun", "notarytool", "log", identifier, "--keychain-profile", args.profile, logfile],
          log=attempt / "log-command.log")
    verify_log(R.read_json(logfile), identifier, state["signedSHA256"], info["status"])
    state.update(stage="ACCEPTED" if info["status"] == "Accepted" else "REJECTED", submissionID=identifier,
                 notaryLog=str(logfile.relative_to(folder)), notaryLogSHA256=R.digest(logfile))
    R.write_json(folder / "state.json", state)
    return state


def finish(args, folder, package, manifest, state):
    require(state["stage"] in {"ACCEPTED", "PUBLISHING", "VERIFIED_STAPLED_DMG"}, "dmg_finish_requires_accepted_job")
    logfile = R.safe_path(folder / state["notaryLog"])
    require(logfile.is_relative_to(folder) and logfile.name == "notary-log.json", "invalid_dmg_log_path")
    same_bytes(logfile, state["notaryLogSHA256"])
    verify_log(R.read_json(logfile), state["submissionID"], state["signedSHA256"], "Accepted")
    require(state["submissionID"] != state["appSubmissionID"], "dmg_requires_independent_notary_job")
    source = signed_image(folder, state)
    attempt = new_attempt(folder, "finish-")
    if state["stage"] == "ACCEPTED":
        image = attempt / state["name"]
        shutil.copyfile(source, image)
        same_bytes(image, state["signedSHA256"])
        R.run(["xcrun", "stapler", "staple", "-v", image], log=attempt / "staple.log")
        pin = R.digest(image)
    else:
        candidate = Path(state["finalCandidate"])
        require(len(candidate.parts) == 2 and candidate.parts[0].startswith("finish-")
                and candidate.name == state["name"], "invalid_final_dmg_location")
        image = R.safe_path(folder / candidate)
        pin = state["finalSHA256"]
        same_bytes(image, pin)
    ticket(image, attempt / "dmg-ticket.log")
    require(image_signature(image, args.team, attempt) == state["signature"], "staple_changed_dmg_identity")
    assess(image, "open", attempt)
    inspect_image(image, manifest, attempt)
    R.verify_package(package, args.manifest_sha256, args.team)
    same_bytes(image, pin)
    if state["stage"] == "ACCEPTED":
        # Commit the exact validated candidate before exposing either output.
        # A crash between either link and the final state write is recoverable.
        state.update(stage="PUBLISHING", finalCandidate=str(image.relative_to(folder)), finalSHA256=pin)
        R.write_json(folder / "state.json", state)
    final = folder / state["name"]
    receipt_path = folder / "dmg-receipt.json"
    if state["stage"] == "VERIFIED_STAPLED_DMG":
        require(os.path.lexists(final) and os.path.lexists(receipt_path), "completed_dmg_outputs_missing")
    try: os.link(image, final, follow_symlinks=False)
    except FileExistsError:
        require(not final.is_symlink() and final.samefile(image), "conflicting_final_dmg")
    receipt = {**state, "stage": "VERIFIED_STAPLED_DMG", "archive": final.name,
               "sha256": pin, "bytes": final.stat().st_size, "appInventory": "PINNED_FULL_TREE_MATCH",
               "mountedReadOnlyDetached": True, "applicationsLink": "/Applications",
               "embeddedAppSignature": manifest["signature"], "embeddedAppTicket": "VALID",
               "embeddedAppGatekeeperExecute": "ACCEPTED", "dmgTicket": "VALID", "dmgGatekeeperOpen": "ACCEPTED",
               "notaryStatus": "Accepted", "published": False, "installedOrLaunched": False,
               "cleanDownloadedMachineTest": "NOT_RUN_BY_TOOL"}
    staged_receipt = attempt / "verified-receipt.json"
    R.write_json(staged_receipt, receipt)
    same_bytes(final, pin)
    try: os.link(staged_receipt, receipt_path, follow_symlinks=False)
    except FileExistsError:
        require(not receipt_path.is_symlink() and R.read_json(receipt_path) == receipt, "conflicting_dmg_receipt")
    same_bytes(final, pin)
    state["stage"] = "VERIFIED_STAPLED_DMG"
    R.write_json(folder / "state.json", state)
    return receipt


def operate(args):
    R.network_execution(args)
    R.team_value(args.team)
    require(R.hash_value(args.manifest_sha256), "trusted_stapled_manifest_pin_required")
    ws, package = R.payload(args.workspace)
    manifest = R.verify_package(package, args.manifest_sha256, args.team)
    require(manifest["stage"] == "STAPLED", "formal_dmg_requires_stapled_app")
    R.verify_accepted_app_log(ws, manifest)
    folder = R.safe_path(ws / "formal-dmg")
    if args.command == "create":
        folder.mkdir(mode=0o700, exist_ok=True)
    require(folder.is_dir(), "dmg_workspace_missing")
    lock = os.open(folder / ".operation-lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise R.ReleaseError("dmg_operation_already_running") from None
        build = manifest["build"]
        arch = "universal" if len(build["architectures"]) > 1 else build["architectures"][0]
        if build.get("distributionChannel") == "stable":
            suffix = "" if arch == "universal" else "-" + arch
            filename = f"Riftlet-{build['version']}{suffix}.dmg"
        else:
            filename = f"Riftlet-{build['version']}-{build['build']}-{arch}.dmg"
        identity = {"schema": 1, "manifestSHA256": args.manifest_sha256, "teamID": args.team,
                    "name": filename,
                    "version": build["version"], "build": build["build"], "architectures": build["architectures"],
                    "source": build["source"]["commit"], "appSubmissionID": manifest["notarization"]["submissionID"]}
        if args.command == "create":
            ticket(package / R.APP, folder / "source-ticket.log")
            return create(args, folder, package, manifest, identity)
        state = R.read_json(R.safe_path(folder / "state.json"))
        require(all(state.get(k) == v for k, v in identity.items()), "dmg_workspace_identity_mismatch")
        if args.command == "submit": return submit(args, folder, state)
        if args.command == "status": return status(args, folder, state)
        return finish(args, folder, package, manifest, state)
    finally:
        os.close(lock)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("create", "submit", "status", "finish"):
        cmd = commands.add_parser(name)
        cmd.add_argument("--workspace", type=Path, required=True)
        cmd.add_argument("--manifest-sha256", required=True)
        cmd.add_argument("--team", required=True)
        cmd.add_argument("--execute", action="store_true")
        cmd.add_argument("--allow-network", action="store_true")
        if name == "create": cmd.add_argument("--identity", required=True)
        if name in {"submit", "status"}: cmd.add_argument("--profile", required=True)
        if name == "status": cmd.add_argument("--submission-id")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(operate(args), indent=2, sort_keys=True))
    except R.ReleaseError as error:
        print(json.dumps({"status": error.status, "code": error.code}))
        return 3 if error.status.startswith("BLOCKED_") else 2
    except (OSError, ValueError, TypeError, KeyError, subprocess.TimeoutExpired, plistlib.InvalidFileException, R.BUNDLE.VerificationError) as error:
        print(json.dumps({"status": "FAIL", "errorType": type(error).__name__}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
