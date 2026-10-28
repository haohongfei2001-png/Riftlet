#!/usr/bin/env python3
"""Verify the unified internal package without launching it or requesting permissions."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import stat
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location("bundle_check", Path(__file__).with_name("verify-app-bundle.py"))
BUNDLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLE)
ENTRY = "Start-Riftlet-Internal-Beta.command"
README = "README-zh-CN.txt"
INPUTS = ("Sources", "Tests", "Resources", "Package.swift", "scripts", "packaging",
          ".github", "services/feedback", "ThirdPartyNotices", "research",
          "engineering/evidence/2026-10-27-real-mac-round2",
          "engineering/evidence/2026-10-27-real-mac-round3",
          "engineering/evidence/2026-10-27-real-mac-round5",
          "engineering/evidence/2026-10-28-system-screenshot-stage2")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, code):
    if not condition:
        raise ValueError(code)


def git(repository, *args):
    return subprocess.check_output(["git", "-C", str(repository), *args], text=True).strip()


def package_hashes(package):
    app = package / "Riftlet.app"
    result = {ENTRY: digest(package / ENTRY), README: digest(package / README),
              "Riftlet.app/Contents/MacOS/Riftlet": digest(app / "Contents/MacOS/Riftlet"),
              "Riftlet.app/Contents/Info.plist": digest(app / "Contents/Info.plist")}
    for name in BUNDLE.RESOURCE_NAMES:
        matches = list((app / "Contents/Resources/Riftlet_RiftletAdapters.bundle").rglob(name))
        require(len(matches) == 1, "ambiguous_adapter_resource")
        result[matches[0].relative_to(package).as_posix()] = digest(matches[0])
    return result


def create_manifest(package, repository, source_head):
    require(source_head == "HEAD" or re.fullmatch(r"[0-9a-f]{40}", source_head), "invalid_source_head")
    checkout = git(repository, "rev-parse", "HEAD")
    head = git(repository, "rev-parse", source_head + "^{commit}")
    subprocess.run(["git", "-C", str(repository), "merge-base", "--is-ancestor", head, checkout], check=True)
    # CI may check out a PR merge. Bind every relevant build/test input to the
    # delivered source head instead of labelling the synthetic merge as that head.
    objects = {}
    for path in INPUTS:
        value = git(repository, "rev-parse", checkout + ":" + path)
        require(value == git(repository, "rev-parse", head + ":" + path), "head_input_mismatch_" + path)
        objects[path] = value
    subprocess.run(["git", "-C", str(repository), "diff", "--exit-code", "HEAD", "--", *INPUTS], check=True)
    run = os.environ.get("GITHUB_RUN_ID")
    require(run is None or run.isdigit(), "invalid_ci_run")
    return {"schemaVersion": 1, "kind": "internal-beta-development", "sourceHeadSHA": head,
            "checkoutSHA": checkout, "ciRunID": run, "architecture": platform.machine(),
            "launchArgument": "--system-screenshot-candidate",
            "ordinaryAppDefault": "capture-upload-disabled",
            "dataDirectory": "Riftlet-System-Screenshot-Candidate",
            "feedbackEndpointConfigured": False, "feedbackDelivery": "local-outbox-only",
            "realAcceptanceSourceSHA": "e421e6687651c2fac1441410c1af2bd5b8151e55",
            "realAcceptanceEvidenceSHA": "c177174e400064d8ec8bb79685c33d01c4e93b89",
            "realAcceptanceScope": "prebound-software-CGEvent-one-new-PNG; not a new combined-App Mac run",
            "buildInputObjects": objects, "sha256": package_hashes(package)}


def verify_package(package, repository=None):
    package = Path(package)
    require(package.is_dir() and not package.is_symlink(), "invalid_package_root")
    require({p.name for p in package.iterdir()} == {"Riftlet.app", ENTRY, README, "build-info.json"}, "unexpected_package_entry")
    for path in package.rglob("*"):
        mode = path.lstat().st_mode
        require(stat.S_ISREG(mode) or stat.S_ISDIR(mode), "unsafe_package_entry")
    BUNDLE.verify_bundle(package / "Riftlet.app", repository)
    require(bool((package / ENTRY).stat().st_mode & stat.S_IXUSR), "launcher_not_executable")
    require((package / ENTRY).read_bytes().startswith(b"#!/bin/bash\n"), "invalid_launcher")
    require((package / README).stat().st_size > 0, "empty_readme")
    if repository is not None:
        for name in (ENTRY, README):
            require((package / name).read_bytes() == (Path(repository) / "packaging/internal-beta" / name).read_bytes(), "package_source_mismatch_" + name)
    manifest = json.loads((package / "build-info.json").read_text())
    require(manifest.get("schemaVersion") == 1 and manifest.get("kind") == "internal-beta-development", "invalid_manifest")
    for key in ("sourceHeadSHA", "checkoutSHA", "realAcceptanceSourceSHA", "realAcceptanceEvidenceSHA"):
        require(isinstance(manifest.get(key), str) and re.fullmatch(r"[0-9a-f]{40}", manifest[key]), "invalid_manifest_commit")
    require(manifest.get("launchArgument") == "--system-screenshot-candidate"
            and manifest.get("ordinaryAppDefault") == "capture-upload-disabled"
            and manifest.get("dataDirectory") == "Riftlet-System-Screenshot-Candidate", "invalid_launch_profile")
    require(manifest.get("feedbackEndpointConfigured") is False
            and manifest.get("feedbackDelivery") == "local-outbox-only", "invalid_feedback_boundary")
    require(manifest.get("sha256") == package_hashes(package), "package_hash_mismatch")
    require(isinstance(manifest.get("buildInputObjects"), dict) and set(manifest["buildInputObjects"]) == set(INPUTS)
            and all(re.fullmatch(r"[0-9a-f]{40}", v) for v in manifest["buildInputObjects"].values()), "invalid_build_inputs")
    if repository is not None:
        for path, value in manifest["buildInputObjects"].items():
            require(git(repository, "rev-parse", manifest["checkoutSHA"] + ":" + path) == value
                    and git(repository, "rev-parse", manifest["sourceHeadSHA"] + ":" + path) == value, "manifest_input_mismatch")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--repository", type=Path)
    parser.add_argument("--write-manifest", action="store_true")
    parser.add_argument("--source-head", default="HEAD")
    args = parser.parse_args()
    try:
        if args.write_manifest:
            require(args.repository is not None, "repository_required")
            BUNDLE.verify_bundle(args.package / "Riftlet.app", args.repository)
            (args.package / "build-info.json").write_text(json.dumps(create_manifest(args.package, args.repository, args.source_head), ensure_ascii=False, indent=2) + "\n")
        manifest = verify_package(args.package, args.repository)
    except (ValueError, OSError, TypeError, subprocess.CalledProcessError, BUNDLE.VerificationError) as error:
        print("RIFTLET_INTERNAL_BETA_CHECK_FAIL: " + type(error).__name__, file=sys.stderr)
        return 1
    print("RIFTLET_INTERNAL_BETA_CHECK_PASS: source=" + manifest["sourceHeadSHA"] + "; checkout=" + manifest["checkoutSHA"] + "; explicit candidate; local Feedback; GUI_NOT_RUN; GATEKEEPER_NOT_RUN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
