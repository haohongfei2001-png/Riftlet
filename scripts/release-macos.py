#!/usr/bin/env python3
"""Prepare or resume a direct-download release. Production website publication is separate."""
import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import tempfile
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("riftlet_release", HERE / "release-tool.py")
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)
POLL_INTERVAL = 30


def select_signer(identity, team):
    if identity:
        R.require(re.fullmatch(r"[a-fA-F0-9]{40}", identity), "invalid_certificate_fingerprint")
    if team:
        R.team_value(team)
    response = R.run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"]).stdout.decode()
    identities = sorted(set(re.findall(r'^\s*\d+\)\s+([0-9a-fA-F]{40})\s+"Developer ID Application:[^"\n]+ \(([A-Z0-9]{10})\)"\s*$',
                                       response, re.MULTILINE)))
    matches = [(fp, owner) for fp, owner in identities
               if (not identity or fp.upper() == identity.upper()) and (not team or team == owner)]
    R.require(len(matches) == 1, "select_one_developer_id_identity" if matches else "developer_id_identity_unavailable",
              "BLOCKED_CREDENTIALS")
    return matches[0]


@contextlib.contextmanager
def release_lock(workspace):
    workspace.parent.mkdir(exist_ok=True, parents=True)
    lock = workspace.with_name("." + workspace.name + ".release.lock")
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise R.ReleaseError("release_workspace_busy") from None
        yield
    finally:
        os.close(fd)


def prepared_package(args, workspace):
    R.full_sha(args.source)
    R.version_values(args.version, args.build)
    R.version_label(args.label)
    arches = sorted(args.arch or ["arm64", "x86_64"])
    R.require(arches and len(set(arches)) == len(arches), "duplicate_requested_arch")
    if not workspace.exists():
        # An interrupted compilation leaves its trace in an attempt directory.
        attempt = Path(tempfile.mkdtemp(prefix="." + workspace.name + "-build-", dir=workspace.parent))
        build = SimpleNamespace(source=args.source, version=args.version, build=args.build,
                                label=args.label, arch=arches, repository=R.ROOT, workspace=attempt / "out")
        R.build_candidate(build)
        R.require(not os.path.lexists(workspace), "workspace_appeared_during_build")
        build.workspace.rename(workspace)
        attempt.rmdir()
    package = R.payload(workspace)[1]
    value = R.load_package_for_resume(package)
    b = value["build"]
    R.require((b["source"]["commit"], b["version"], b["build"], b.get("versionLabel"), b["architectures"])
              == (args.source, args.version, args.build, args.label, arches), "workspace_belongs_to_another_release")
    return package, value


def dmg_step(phase, workspace, pin, signer, team, profile, original_id=None):
    command = [sys.executable, "-B", str(HERE / "release-dmg.py"), phase, "--workspace", str(workspace),
               "--manifest-sha256", pin, "--team", team, "--execute", "--allow-network"]
    if phase == "create":
        command += ["--identity", signer]
    if phase in {"submit", "status"}:
        command += ["--profile", profile]
    if phase == "status" and original_id:
        command += ["--submission-id", original_id]
    response = subprocess.run(command, capture_output=True, timeout=1200)
    data = R.decode_json(response.stdout)
    if response.returncode:
        raise R.ReleaseError(data.get("code", "dmg_step_failed"), data.get("status", "FAIL"))
    return data


def wait_for_notary(query, deadline):
    while True:
        response = query()
        stage = response.get("stage") or response.get("status")
        if stage not in {"NOTARY_IN_PROGRESS", "IN_PROGRESS"} and response.get("queryStatus") != "In Progress":
            return response
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return {"status": "PENDING_NOTARIZATION", "submissionID": response.get("submissionID") or response.get("queriedSubmissionID")}
        time.sleep(min(POLL_INTERVAL, remaining))


def prepare_app(workspace, package, stage, signer, team, profile, original_id, deadline):
    options = SimpleNamespace(workspace=workspace, identity=signer, team=team, profile=profile,
                              execute=True, allow_network=True, submission_id=original_id)
    if stage == "PREPARED":
        R.require(not original_id, "unexpected_original_app_submission_id")
        R.sign_candidate(options)
        stage = "SIGNED"
    else:
        value = R.load_package_for_resume(package)
        if value.get("signature"):
            R.require(value["signature"]["teamID"] == team, "release_team_changed")
    if stage == "SIGNED":
        R.require(not original_id, "unexpected_original_app_submission_id")
        R.notary_submit(options)
        stage = "NOTARY_IN_PROGRESS"
    if stage in {"NOTARY_SUBMITTING", "NOTARY_SUBMISSION_UNKNOWN", "NOTARY_IN_PROGRESS"}:
        response = wait_for_notary(lambda: R.notary_status(options), deadline)
        if response.get("status") == "PENDING_NOTARIZATION":
            return response
        stage = response["status"]
    if stage in {"NOTARIZED", "STAPLE_FAILED"}:
        R.staple_candidate(options)
        stage = "STAPLED"
    R.require(stage == "STAPLED", "app_release_stopped_at_" + stage)
    stapled = R.verify_package(package, native_team=team)
    R.verify_accepted_app_log(workspace, stapled)
    return None


def signer_fingerprint(artifact, workspace, arch=None):
    # codesign exports only the public DER certificate chain.
    with tempfile.TemporaryDirectory(prefix="signer-", dir=workspace) as tmp:
        prefix = Path(tmp) / "cert-"
        options = ["--arch", arch] if arch else []
        R.run(["/usr/bin/codesign", "--display", *options, "--extract-certificates=" + str(prefix), artifact])
        leaf = Path(str(prefix) + "0")
        R.require(leaf.is_file(), "missing_developer_id_leaf_certificate")
        return hashlib.sha1(leaf.read_bytes()).hexdigest().upper()


def release(args):
    workspace = R.safe_path(args.workspace)
    R.require(workspace.name and not any(p.suffix == ".app" for p in (workspace, *workspace.parents))
              and not any(p == workspace or p in workspace.parents for p in (Path("/Applications"), Path.home() / "Applications")),
              "use_an_isolated_release_workspace")
    R.require(0 <= args.wait_seconds <= 86400, "invalid_wait_limit")
    with release_lock(workspace):
        package, manifest = prepared_package(args, workspace)
        if args.prepare_only:
            return {"status": "PREPARATION_VERIFIED", "stage": manifest["stage"], "workspace": str(workspace),
                    "manifestSHA256": R.digest(package / R.MANIFEST), "architectures": manifest["build"]["architectures"]}
        state_file = workspace / "formal-dmg/state.json"
        state = R.read_json(state_file) if state_file.exists() else None
        profile = args.profile
        validated = False

        def authenticate():
            nonlocal validated
            if not validated:
                R.credential_values(profile=profile, notary=True)
                try:
                    R.run(["xcrun", "notarytool", "history", "--keychain-profile", profile, "--output-format", "json"], timeout=60)
                except R.ReleaseError:
                    raise R.ReleaseError("cannot_validate_notary_profile_or_service", "BLOCKED_NOTARY_AUTH_OR_SERVICE") from None
                validated = True

        signer = None
        if manifest["stage"] == "PREPARED":
            signer, team = select_signer(args.identity, args.team)
        else:
            R.require(manifest.get("signature") is not None, "app_release_stopped_at_" + manifest["stage"])
            team = manifest["signature"]["teamID"]
            R.require(args.team in (None, team), "release_team_changed")
        if state:
            R.require(manifest["stage"] == "STAPLED", "dmg_workspace_app_stage_mismatch")
        if manifest["stage"] in {"PREPARED", "SIGNED", "NOTARY_SUBMITTING", "NOTARY_SUBMISSION_UNKNOWN", "NOTARY_IN_PROGRESS"}:
            authenticate()
        deadline = time.monotonic() + args.wait_seconds
        response = prepare_app(workspace, package, manifest["stage"], signer, team, profile, args.app_submission_id, deadline)
        if response:
            return {**response, "component": "App"}
        pin = R.digest(package / R.MANIFEST)
        if state is None:
            if not signer:
                signer, _ = select_signer(args.identity, team)
            state = dmg_step("create", workspace, pin, signer, team, profile)
        if state["stage"] == "SIGNED":
            authenticate()
            R.require(not args.dmg_submission_id, "unexpected_original_dmg_submission_id")
            state = dmg_step("submit", workspace, pin, signer, team, profile)
        if state["stage"] in {"SUBMITTING", "SUBMISSION_UNKNOWN", "IN_PROGRESS"}:
            authenticate()
            state = wait_for_notary(lambda: dmg_step("status", workspace, pin, signer, team, profile,
                                                      args.dmg_submission_id), deadline)
            if state.get("status") == "PENDING_NOTARIZATION":
                return {**state, "component": "DMG"}
        R.require(state["stage"] in {"ACCEPTED", "PUBLISHING", "VERIFIED_STAPLED_DMG"}, "dmg_release_stopped_at_" + state["stage"])
        receipt = dmg_step("finish", workspace, pin, signer, team, profile)
        path = workspace / "formal-dmg" / receipt["archive"]
        R.require(receipt["stage"] == "VERIFIED_STAPLED_DMG" and R.digest(path) == receipt["sha256"],
                  "final_dmg_identity_mismatch")
        result = {"status": "VERIFIED_FOR_PUBLICATION_REVIEW", "artifact": str(path), "sha256": receipt["sha256"],
                  "bytes": path.stat().st_size, "version": args.version, "build": args.build, "source": args.source,
                  "architectures": receipt["architectures"], "teamID": team,
                  "dmgCertificateFingerprint": signer_fingerprint(path, workspace),
                  "appCertificateFingerprints": {arch: signer_fingerprint(package / R.APP, workspace, arch)
                                                 for arch in receipt["architectures"]},
                  "appSubmissionID": receipt["appSubmissionID"], "dmgSubmissionID": receipt["submissionID"],
                  "receipt": str(path.parent / "dmg-receipt.json"), "published": False}
        R.write_json(workspace / "website-release.json", result)
        return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--source", required=True, help="Full reviewed source commit SHA")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--label", default="Riftlet")
    parser.add_argument("--arch", action="append", choices=["arm64","x86_64"], help="Default: universal")
    parser.add_argument("--identity", help="Optional SHA-1 fingerprint of a valid Developer ID Application identity")
    parser.add_argument("--team", help="Optional Team ID to select between identities")
    parser.add_argument("--profile", default="Riftlet-Notary", help="Existing notarytool Keychain profile name")
    parser.add_argument("--app-submission-id", help="Original App job if its submission acknowledgement was lost")
    parser.add_argument("--dmg-submission-id", help="Original DMG job if its submission acknowledgement was lost")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--wait-seconds", type=int, default=1800)
    args = parser.parse_args(argv)
    os.umask(0o077)
    try:
        result = release(args)
    except R.ReleaseError as error:
        print(json.dumps({"status": error.status, "code": error.code, "workspace": str(args.workspace)}))
        return 3 if error.status.startswith("BLOCKED_") else 2
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, R.BUNDLE.VerificationError) as error:
        print(json.dumps({"status":"FAIL", "type":type(error).__name__, "workspace":str(args.workspace)}))
        return 1
    print(json.dumps(result, indent=2))
    return 3 if result.get("status") == "PENDING_NOTARIZATION" else 0


if __name__ == "__main__":
    raise SystemExit(main())
