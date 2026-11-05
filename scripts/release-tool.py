#!/usr/bin/env python3
"""Separate release preparation. No install, key export, or implicit network.

Build/verify are local; sign, notarize and staple require explicit execution and
network flags. Missing configured credentials is BLOCKED_CREDENTIALS, not PASS.
Content hashes are identity checks; trust requires a separately obtained pin.
"""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("release_legacy_bundle", ROOT / "scripts/verify-app-bundle.py")
BUNDLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLE)
SCHEMA = 1
KIND = "riftlet-release-candidate"
PAYLOAD = "Riftlet-Release"
MANIFEST = "release-manifest.json"
APP = "Riftlet.app"
RECEIPT = "Contents/Resources/release-build.json"
BUILD_INPUTS = ("Package.swift", "Sources", "Tests", "Resources", "ThirdPartyNotices")
ARCHES = {0x01000007: "x86_64", 0x0100000C: "arm64"}
ENTITLEMENTS = {"com.apple.security.automation.apple-events": True}
TRANSFER_XATTRS = {"com.apple.quarantine", "com.apple.metadata:kMDItemWhereFroms",
                  "com.apple.lastuseddate#PS", "com.apple.macl", "com.apple.provenance"}
STAGES = {"PREPARED", "SIGNED", "SIGN_FAILED", "NOTARY_SUBMITTING", "NOTARY_SUBMISSION_UNKNOWN",
          "NOTARY_IN_PROGRESS", "NOTARY_REJECTED", "NOTARIZED", "STAPLE_FAILED", "STAPLED"}
PREPARATION_INPUTS = ("scripts/release-tool.py", "scripts/verify-app-bundle.py",
                      "packaging/release/Entitlements.plist", "packaging/release/INSTALL-zh-CN.txt")


class ReleaseError(Exception):
    def __init__(self, code, status="FAIL"):
        super().__init__(code)
        self.code, self.status = code, status


def require(condition, code, status="FAIL"):
    if not condition:
        raise ReleaseError(code, status)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate_json_key")
        result[key] = value
    return result


def decode_json(data):
    require(len(data) <= 8 * 1024 * 1024, "oversized_json")
    return json.loads(data, object_pairs_hook=unique_object)


def read_json(path):
    require(Path(path).is_file() and not Path(path).is_symlink(), "missing_or_linked_json")
    require(Path(path).stat().st_size <= 8 * 1024 * 1024, "oversized_json")
    return decode_json(Path(path).read_bytes())


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def write_json(path, value):
    path = Path(path)
    require(not path.is_symlink(), "linked_output")
    fd, name = tempfile.mkstemp(prefix=".release-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(encoded(value)); stream.flush(); os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def safe_path(path):
    path = Path(os.path.abspath(path))
    require(not any(p.is_symlink() for p in (path, *path.parents)), "linked_path")
    return path


def fresh_workspace(path):
    path = safe_path(path)
    require(not path.exists(), "output_already_exists")
    installed = (Path("/Applications"), Path.home() / "Applications")
    require(not any(path == p or p in path.parents for p in installed), "installed_app_location_forbidden")
    require(not any(p.suffix == ".app" for p in (path, *path.parents)), "app_output_location_forbidden")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.mkdir(mode=0o700)
    return path


def run(args, *, cwd=None, timeout=120, input=None, log=None):
    # Argument arrays only. Never shell-expand identity, paths or profile names.
    try:
        result = subprocess.run([str(a) for a in args], cwd=cwd, input=input,
                                capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        if log:
            Path(log).write_bytes((error.stdout or b"") + (error.stderr or b"") + b"\nTIMEOUT\n")
        raise
    if log:
        Path(log).write_bytes(result.stdout + result.stderr)
    require(result.returncode == 0, "command_failed_" + Path(str(args[0])).name)
    return result


def git(repository, *args):
    return run(["git", "-C", repository, *args]).stdout.decode().strip()


def full_sha(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value), "full_source_sha_required")
    return value


def version_values(version, build):
    require(isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+", version), "invalid_version")
    require(isinstance(build, str) and re.fullmatch(r"[1-9]\d*", build), "invalid_build")


def hash_value(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def entitlement_policy(value):
    return isinstance(value, dict) and set(value) == set(ENTITLEMENTS) and all(value[k] is True for k in ENTITLEMENTS)


def macho_arches(data):
    """Parse actual Mach-O headers/slices, not the packaging host's CPU."""
    require(len(data) >= 8, "truncated_macho")
    magic = bytes(data[:4])
    if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
        require(len(data) >= 32, "truncated_macho")
        cpu = struct.unpack_from(endian + "I", data, 4)[0]
        require(cpu in ARCHES, "unsupported_macho_arch")
        require(struct.unpack_from(endian + "I", data, 12)[0] == 2, "macho_not_executable")
        return [ARCHES[cpu]]
    formats = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
               b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    require(magic in formats, "invalid_macho")
    endian, wide = formats[magic]
    count = struct.unpack_from(endian + "I", data, 4)[0]
    stride = 32 if wide else 20
    require(1 <= count <= 2 and len(data) >= 8 + count * stride, "invalid_fat_header")
    result, ranges = [], []
    for i in range(count):
        cursor = 8 + i * stride
        cpu = struct.unpack_from(endian + "I", data, cursor)[0]
        offset, size = struct.unpack_from(endian + ("QQ" if wide else "II"), data, cursor + 8)
        require(cpu in ARCHES and offset >= 8 + count * stride and size >= 32
                and offset + size <= len(data), "invalid_fat_slice")
        require(all(offset + size <= start or offset >= end for start, end in ranges), "overlapping_fat_slices")
        slice_data = data[offset:offset + size]
        require(slice_data[:4] in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"), "nested_fat_slice")
        require(macho_arches(slice_data) == [ARCHES[cpu]], "fat_slice_arch_mismatch")
        require(ARCHES[cpu] not in result, "duplicate_macho_arch")
        result.append(ARCHES[cpu]); ranges.append((offset, offset + size))
    return sorted(result)


def xattr_hashes(path):
    if hasattr(os, "listxattr"):
        return {key: sha(os.getxattr(path, key, follow_symlinks=False))
                for key in sorted(os.listxattr(path, follow_symlinks=False)) if key not in TRANSFER_XATTRS}
    # CPython on macOS need not expose the Linux os.*xattr APIs. Do not silently
    # drop resource-fork/signature/ticket metadata on the actual release host.
    require(platform.system() == "Darwin" and Path("/usr/bin/xattr").is_file(), "xattr_verification_unavailable", "BLOCKED_PLATFORM")
    def read(arguments):
        value = subprocess.run(["/usr/bin/xattr", *arguments], capture_output=True, timeout=30, check=False)
        require(value.returncode == 0, "xattr_read_failed")
        return value.stdout.decode("utf-8")
    keys = read(["--", str(path)]).splitlines()
    require(len(keys) == len(set(keys)), "duplicate_xattr_name")
    return {key: sha(bytes.fromhex(read(["-px", "--", key, str(path)]))) for key in sorted(keys) if key not in TRANSFER_XATTRS}


def inventory(root):
    root = safe_path(root)
    require(root.is_dir(), "missing_payload")
    result, names = {}, set()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == MANIFEST:
            continue
        info = path.lstat()
        require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode), "unsafe_payload_entry")
        require(relative.casefold() not in names, "case_colliding_payload_entry")
        names.add(relative.casefold())
        row = {"kind": "directory" if path.is_dir() else "file", "mode": stat.S_IMODE(info.st_mode),
               "xattrs": xattr_hashes(path)}
        if path.is_file():
            require(info.st_nlink == 1, "hard_linked_payload_entry")
            row.update(size=info.st_size, sha256=digest(path))
        result[relative] = row
    return result


def validate_receipt(receipt):
    require(isinstance(receipt, dict) and type(receipt.get("schemaVersion")) is int and receipt["schemaVersion"] == SCHEMA, "invalid_build_receipt")
    version_values(receipt.get("version"), receipt.get("build"))
    require(receipt.get("bundleIdentifier") == "com.riftlet.app", "wrong_bundle_identifier")
    source = receipt.get("source", {})
    require(isinstance(source, dict) and isinstance(source.get("inputs"), dict), "invalid_source_inputs")
    full_sha(source.get("commit")); full_sha(source.get("tree"))
    require(set(source.get("inputs", {})) == set(BUILD_INPUTS), "invalid_source_inputs")
    for value in source["inputs"].values():
        full_sha(value)
    arches = receipt.get("architectures")
    require(isinstance(arches, list) and arches == sorted(set(arches)) and arches
            and set(arches) <= set(ARCHES.values()), "invalid_architectures")
    require(receipt.get("dataCompatibility") == "NOT_ASSERTED", "unreviewed_data_compatibility_claim")
    require(receipt.get("minimumMacOS") == "13.0" and receipt.get("buildInfoExecutedOn") in ARCHES.values(), "invalid_build_platform")
    require(hash_value(receipt.get("infoPlistSHA256")), "invalid_plist_hash")
    preparation = receipt.get("preparationInputs", {})
    require(isinstance(preparation, dict) and set(preparation) == set(PREPARATION_INPUTS)
            and all(hash_value(v) for v in preparation.values()), "invalid_preparation_inputs")
    require(isinstance(receipt.get("swiftVersion"), str) and receipt["swiftVersion"].strip(), "missing_swift_version")
    BUNDLE.verify_ordinary_build_info(receipt.get("ordinaryBuildInfo"), "development")


def validate_manifest(value):
    require(isinstance(value, dict) and type(value.get("schemaVersion")) is int and value["schemaVersion"] == SCHEMA
            and value.get("kind") == KIND and value.get("stage") in STAGES, "invalid_manifest")
    require(value.get("sourceAdmission") == "INDEPENDENT_REVIEW_REQUIRED", "manifest_cannot_admit_source")
    validate_receipt(value.get("build"))
    stage, signature, notary = value["stage"], value.get("signature"), value.get("notarization")
    if stage in {"PREPARED", "SIGN_FAILED"}:
        require(signature is None and notary is None, "unsigned_stage_has_signing_claim")
    else:
        require(isinstance(signature, dict) and signature.get("hardenedRuntime") is True
                and entitlement_policy(signature.get("entitlements")), "invalid_signature_receipt")
        require(isinstance(signature.get("teamID"), str) and re.fullmatch(r"[A-Z0-9]{10}", signature["teamID"]), "invalid_signature_team")
        require(isinstance(signature.get("architectures"), dict) and set(signature["architectures"]) == set(value["build"]["architectures"]), "signature_arch_mismatch")
        for entry in signature["architectures"].values():
            require(isinstance(entry, dict) and isinstance(entry.get("cdhash"), str)
                    and re.fullmatch(r"[0-9a-f]{40}", entry["cdhash"])
                    and isinstance(entry.get("timestamp"), str) and entry["timestamp"] not in {"", "none", "Not set"}, "invalid_signature_arch_receipt")
        if stage == "SIGNED":
            require(notary is None, "signed_stage_has_notary_claim")
        else:
            require(isinstance(notary, dict) and hash_value(notary.get("uploadSHA256"))
                    and type(notary.get("stapled")) is bool, "invalid_notary_receipt")
            identifier = notary.get("submissionID")
            if stage in {"NOTARY_SUBMITTING", "NOTARY_SUBMISSION_UNKNOWN"}:
                require(identifier is None and notary.get("status") == "SubmissionUnknown", "invalid_uncertain_submission")
            else:
                require(isinstance(identifier, str) and str(uuid.UUID(identifier)) == identifier, "invalid_notary_id")
                status_value = "In Progress" if stage == "NOTARY_IN_PROGRESS" else "Invalid" if stage == "NOTARY_REJECTED" else "Accepted"
                require(notary.get("status") == status_value, "notary_stage_status_mismatch")
                if status_value != "In Progress":
                    require(hash_value(notary.get("logSHA256")), "terminal_notary_log_missing")
            require(notary["stapled"] is (stage == "STAPLED"), "staple_stage_mismatch")
    files = value.get("files")
    require(isinstance(files, dict) and files, "invalid_file_inventory")
    folded = set()
    for name, row in files.items():
        path = PurePosixPath(name)
        require(name != MANIFEST and path.parts and not path.is_absolute() and ".." not in path.parts
                and path.as_posix() == name and "\\" not in name and "\x00" not in name
                and name.casefold() not in folded, "invalid_inventory_path")
        folded.add(name.casefold())
        require(isinstance(row, dict) and row.get("kind") in {"directory", "file"}
                and type(row.get("mode")) is int and 0 <= row["mode"] <= 0o777, "invalid_inventory_metadata")
        require(isinstance(row.get("xattrs"), dict) and all(isinstance(k, str) and hash_value(v) for k, v in row["xattrs"].items()), "invalid_inventory_xattrs")
        if row["kind"] == "file":
            require(type(row.get("size")) is int and row["size"] >= 0 and hash_value(row.get("sha256")), "invalid_inventory_file")


def validate_release_info(info, receipt):
    require(isinstance(info, dict), "invalid_info_plist")
    expected = {"CFBundleExecutable": "Riftlet", "CFBundleIdentifier": "com.riftlet.app",
                "CFBundleName": "Riftlet", "CFBundleDisplayName": "Riftlet", "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": receipt["version"], "CFBundleVersion": receipt["build"],
                "LSMinimumSystemVersion": "13.0", "LSUIElement": True, "NSHighResolutionCapable": True,
                "LSApplicationCategoryType": "public.app-category.utilities", "RiftletBuildChannel": "release-candidate"}
    for key, value in expected.items():
        require(type(info.get(key)) is type(value) and info[key] == value, "invalid_release_" + key)
    require("RiftletDeveloperIDSigned" not in info and "RiftletNotarized" not in info, "plist_cannot_claim_signing_status")
    for key in (*BUNDLE.USAGE_KEYS, "NSScreenCaptureUsageDescription"):
        require(isinstance(info.get(key), str) and 10 <= len(info[key].strip()) <= 512, "invalid_usage_description")


def verify_package(package, expected_manifest=None, native_team=None):
    package = safe_path(package)
    require(package.is_dir() and {p.name for p in package.iterdir()} == {APP, MANIFEST, "INSTALL-zh-CN.txt"}, "invalid_payload_layout")
    require((package / MANIFEST).is_file() and not (package / MANIFEST).is_symlink(), "missing_or_linked_json")
    if expected_manifest:
        require(re.fullmatch(r"[0-9a-f]{64}", expected_manifest) is not None
                and digest(package / MANIFEST) == expected_manifest, "manifest_pin_mismatch")
    value = read_json(package / MANIFEST)
    validate_manifest(value)
    require(value.get("files") == inventory(package), "payload_inventory_mismatch")
    app = package / APP
    receipt = read_json(app / RECEIPT)
    validate_receipt(receipt)
    require(value.get("build") == receipt, "receipt_manifest_mismatch")
    require(digest(package / "INSTALL-zh-CN.txt") == receipt["preparationInputs"]["packaging/release/INSTALL-zh-CN.txt"], "install_notes_receipt_mismatch")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    validate_release_info(info, receipt)
    require(sha((app / "Contents/Info.plist").read_bytes()) == receipt.get("infoPlistSHA256"), "plist_receipt_mismatch")
    binary = app / "Contents/MacOS/Riftlet"
    require(binary.stat().st_mode & stat.S_IXUSR, "binary_not_executable")
    require(macho_arches(binary.read_bytes()) == receipt["architectures"], "binary_arch_mismatch")
    require(set(p.name for p in app.iterdir()) == {"Contents"}, "unexpected_app_root")
    require(set(p.name for p in (app / "Contents").iterdir()) <= {"Info.plist", "MacOS", "Resources", "_CodeSignature"}, "unexpected_app_contents")
    require(set(p.name for p in (app / "Contents/MacOS").iterdir()) == {"Riftlet"}, "unexpected_executable")
    for name in BUNDLE.RESOURCE_NAMES:
        matches = list((app / "Contents/Resources/Riftlet_RiftletAdapters.bundle").rglob(name))
        require(len(matches) == 1 and matches[0].is_file() and matches[0].stat().st_size > 0, "missing_adapter_resource")
    for name in BUNDLE.NOTICE_NAMES:
        require((app / "Contents/Resources/ThirdPartyNotices" / name).is_file(), "missing_notice")
    if native_team:
        signature = verify_signature(app, native_team, receipt["architectures"])
        require(signature == value.get("signature"), "signature_manifest_mismatch")
    return value


def team_value(team):
    require(isinstance(team, str) and re.fullmatch(r"[A-Z0-9]{10}", team), "developer_team_required", "BLOCKED_CREDENTIALS")


def network_execution(args):
    require(args.execute and args.allow_network, "explicit_execution_and_network_flags_required", "PLAN_ONLY")
    require(platform.system() == "Darwin", "macos_required", "BLOCKED_PLATFORM")


def credential_values(identity=None, team=None, profile=None, signing=False, notary=False):
    if signing:
        team_value(team)
        require(isinstance(identity, str) and re.fullmatch(r"[0-9A-Fa-f]{40}", identity), "developer_id_fingerprint_required", "BLOCKED_CREDENTIALS")
    if notary:
        require(isinstance(profile, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,128}", profile), "notary_keychain_profile_required", "BLOCKED_CREDENTIALS")


def identity_available(identity, team):
    identities = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout.decode()
    require(re.search(re.escape(identity) + r'\s+"Developer ID Application:[^\n]+\(' + re.escape(team) + r'\)"', identities, re.I),
            "configured_developer_id_identity_unavailable", "BLOCKED_CREDENTIALS")


def verify_signature(app, team, arches):
    team_value(team)
    require(platform.system() == "Darwin", "native_signature_check_requires_macos", "BLOCKED_PLATFORM")
    requirement = 'anchor apple generic and identifier "com.riftlet.app" and certificate leaf[subject.OU] = "' + team + '"'
    run(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R", requirement, app])
    result = {"teamID": team, "hardenedRuntime": True, "entitlements": ENTITLEMENTS, "architectures": {}}
    for arch in arches:
        detail = run(["/usr/bin/codesign", "-d", "--verbose=4", "--arch", arch, app]).stderr.decode()
        def field(name):
            matches = re.findall(r"^" + re.escape(name) + r"=(.+)$", detail, re.M)
            require(len(matches) == 1, "missing_signature_" + name)
            return matches[0]
        require(field("Identifier") == "com.riftlet.app" and field("TeamIdentifier") == team, "wrong_signature_identity")
        require(re.search(r"^Authority=Developer ID Application:", detail, re.M), "not_developer_id_application")
        require(re.search(r"flags=0x[0-9a-f]+\([^\n)]*runtime[^\n)]*\)", detail), "hardened_runtime_missing")
        timestamp = field("Timestamp")
        require(timestamp not in {"none", "Not set"}, "secure_timestamp_missing")
        cdhash = field("CDHash")
        require(re.fullmatch(r"[0-9a-f]{40}", cdhash), "invalid_cdhash")
        ent = run(["/usr/bin/codesign", "-d", "--entitlements", ":-", "--arch", arch, app]).stdout
        require(entitlement_policy(plistlib.loads(ent)), "unexpected_entitlements")
        result["architectures"][arch] = {"cdhash": cdhash, "timestamp": timestamp}
    return result


def save_manifest(package, value):
    value["files"] = inventory(package)
    write_json(Path(package) / MANIFEST, value)


def export_source(repository, source, target):
    full_sha(source)
    require(git(repository, "rev-parse", source + "^{commit}") == source, "source_commit_mismatch")
    archive = run(["git", "-C", repository, "archive", source, "--", *BUILD_INPUTS]).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for item in tar.getmembers():
            name = PurePosixPath(item.name)
            require(not name.is_absolute() and ".." not in name.parts and (item.isdir() or item.isfile()), "unsafe_source_archive")
            path = target.joinpath(*name.parts)
            if item.isdir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(tar.extractfile(item).read()); path.chmod(item.mode & 0o777)
    return {"commit": source, "tree": git(repository, "rev-parse", source + "^{tree}"),
            "inputs": {key: git(repository, "rev-parse", source + ":" + key) for key in BUILD_INPUTS}}


def build_candidate(args):
    require(platform.system() == "Darwin", "macos_build_required", "BLOCKED_PLATFORM")
    full_sha(args.source); version_values(args.version, args.build)
    arches = sorted(set(args.arch))
    require(len(arches) == len(args.arch), "duplicate_requested_arch")
    workspace = fresh_workspace(args.workspace)
    package = workspace / PAYLOAD; package.mkdir()
    source_dir = workspace / "source"; source_dir.mkdir()
    source = export_source(args.repository, args.source, source_dir)
    dependencies = decode_json(run(["swift", "package", "--package-path", source_dir, "dump-package"], timeout=120,
                                   log=workspace / "package-inspection.log").stdout)
    require(dependencies.get("dependencies") == [], "external_dependencies_require_separate_offline_policy")
    command = ["swift", "build", "--package-path", source_dir, "--scratch-path", workspace / "swift-build",
               "--configuration", "release", "--product", "Riftlet", "--disable-automatic-resolution", "--skip-update"]
    for arch in arches:
        command += ["--arch", arch]
    run(command, timeout=1200, log=workspace / "build.log")
    bin_dir = Path(run([*command, "--show-bin-path"]).stdout.decode().strip())
    require((workspace / "swift-build").resolve() in bin_dir.resolve().parents, "binary_output_outside_workspace")
    app = package / APP
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources").mkdir()
    shutil.copy2(bin_dir / "Riftlet", app / "Contents/MacOS/Riftlet")
    shutil.copy2(source_dir / "Resources/Info.plist", app / "Contents/Info.plist")
    shutil.copytree(source_dir / "ThirdPartyNotices", app / "Contents/Resources/ThirdPartyNotices")
    shutil.copytree(bin_dir / "Riftlet_RiftletAdapters.bundle", app / "Contents/Resources/Riftlet_RiftletAdapters.bundle")
    # Preserve the old verifier's development contract before staging-only changes.
    BUNDLE.verify_bundle(app, source_dir)
    require(macho_arches((app / "Contents/MacOS/Riftlet").read_bytes()) == arches, "built_arch_mismatch")
    ordinary = decode_json(run([app / "Contents/MacOS/Riftlet", "--ordinary-build-info"], timeout=10).stdout)
    BUNDLE.verify_ordinary_build_info(ordinary, "development")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    info.update(CFBundleShortVersionString=args.version, CFBundleVersion=args.build, RiftletBuildChannel="release-candidate")
    info.pop("RiftletDeveloperIDSigned"); info.pop("RiftletNotarized")
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=True))
    receipt = {"schemaVersion": SCHEMA, "source": source, "version": args.version, "build": args.build,
               "bundleIdentifier": "com.riftlet.app", "minimumMacOS": "13.0", "architectures": arches,
               "ordinaryBuildInfo": ordinary, "buildInfoExecutedOn": platform.machine(),
               "infoPlistSHA256": digest(app / "Contents/Info.plist"), "dataCompatibility": "NOT_ASSERTED",
               "preparationInputs": {key: digest(ROOT / key) for key in PREPARATION_INPUTS},
               "swiftVersion": run(["swift", "--version"]).stdout.decode().strip()}
    write_json(app / RECEIPT, receipt)
    shutil.copy2(ROOT / "packaging/release/INSTALL-zh-CN.txt", package / "INSTALL-zh-CN.txt")
    manifest = {"schemaVersion": SCHEMA, "kind": KIND, "stage": "PREPARED", "build": receipt,
                "sourceAdmission": "INDEPENDENT_REVIEW_REQUIRED", "signature": None, "notarization": None}
    save_manifest(package, manifest); verify_package(package)
    return {"status": "PREPARED", "workspace": str(workspace), "credentials": "NOT_USED",
            "source": args.source, "architectures": arches, "version": args.version, "build": args.build}


def payload(workspace):
    workspace = safe_path(workspace)
    require(workspace.is_dir() and not any(p.suffix == ".app" for p in (workspace, *workspace.parents)), "invalid_workspace")
    return workspace, workspace / PAYLOAD


def sign_candidate(args):
    credential_values(args.identity, args.team, signing=True); network_execution(args)
    identity_available(args.identity, args.team)
    workspace, package = payload(args.workspace)
    value = verify_package(package)
    require(value["stage"] == "PREPARED", "sign_requires_prepared_workspace")
    entitlements = ROOT / "packaging/release/Entitlements.plist"
    require(entitlement_policy(plistlib.loads(entitlements.read_bytes()))
            and digest(entitlements) == value["build"]["preparationInputs"]["packaging/release/Entitlements.plist"], "entitlement_policy_mismatch")
    try:
        run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--options", "runtime", "--timestamp",
             "--entitlements", entitlements, package / APP], timeout=180, log=workspace / "sign.log")
        value["signature"] = verify_signature(package / APP, args.team, value["build"]["architectures"])
        value["stage"] = "SIGNED"
    except Exception:
        value["stage"] = "SIGN_FAILED"; save_manifest(package, value)
        raise
    save_manifest(package, value)
    return {"status": "SIGNED", "teamID": args.team, "notarization": "NOT_RUN"}


def notary_submit(args):
    credential_values(profile=args.profile, notary=True); network_execution(args)
    workspace, package = payload(args.workspace)
    value = verify_package(package)
    require(value["stage"] == "SIGNED", "submit_requires_signed_once")
    verify_package(package, native_team=value["signature"]["teamID"])
    archive = workspace / "notary-upload.zip"
    require(not archive.exists(), "notary_archive_already_exists")
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", package / APP, archive])
    value["notarization"] = {"status": "SubmissionUnknown", "submissionID": None,
                              "uploadSHA256": digest(archive), "stapled": False}
    value["stage"] = "NOTARY_SUBMITTING"; save_manifest(package, value)
    try:
        reply = run(["xcrun", "notarytool", "submit", archive, "--keychain-profile", args.profile, "--output-format", "json"], timeout=180,
                    log=workspace / "notary-submit.log")
        (workspace / "notary-submit.json").write_bytes(reply.stdout)
        response = decode_json(reply.stdout)
        identifier = str(uuid.UUID(response["id"]))
        value["notarization"].update(submissionID=identifier, status="In Progress")
        value["stage"] = "NOTARY_IN_PROGRESS"
    except Exception:
        value["stage"] = "NOTARY_SUBMISSION_UNKNOWN"; save_manifest(package, value)
        raise ReleaseError("submission_uncertain_query_original_job_do_not_resubmit", "NOTARY_SUBMISSION_UNKNOWN")
    save_manifest(package, value)
    return {"status": value["stage"], "submissionID": identifier, "automaticResubmit": False}


def notary_status(args):
    credential_values(profile=args.profile, notary=True); network_execution(args)
    workspace, package = payload(args.workspace)
    value = verify_package(package)
    require(value["stage"] in {"NOTARY_SUBMITTING", "NOTARY_SUBMISSION_UNKNOWN", "NOTARY_IN_PROGRESS"}, "notary_status_wrong_stage")
    old = value["notarization"]["submissionID"]
    require(args.submission_id or old, "original_submission_id_required_no_resubmit", "BLOCKED_RECONCILIATION")
    identifier = str(uuid.UUID(args.submission_id or old))
    require(old is None or old == identifier, "cannot_switch_notary_job")
    attempt = Path(tempfile.mkdtemp(prefix="notary-query-", dir=workspace))
    response = decode_json(run(["xcrun", "notarytool", "info", identifier, "--keychain-profile", args.profile, "--output-format", "json"],
                               log=attempt / "info-command.log").stdout)
    require(isinstance(response, dict), "invalid_notary_response")
    require(response.get("id") == identifier, "notary_job_mismatch")
    status_value = response.get("status")
    require(status_value in {"Accepted", "Invalid", "In Progress"}, "unexpected_notary_status")
    write_json(attempt / "info.json", response)
    if status_value == "In Progress":
        return {"status": "NOTARY_IN_PROGRESS", "submissionID": identifier, "identityBound": old is not None}
    log_path = attempt / (identifier + ".notary-log.json")
    run(["xcrun", "notarytool", "log", identifier, "--keychain-profile", args.profile, log_path], log=attempt / "log-command.log")
    log = read_json(log_path)
    require(isinstance(log, dict), "invalid_notary_log")
    require(log.get("jobId") == identifier and log.get("sha256", "").lower() == value["notarization"]["uploadSHA256"], "notary_log_artifact_mismatch")
    require(log.get("status") == status_value, "notary_log_status_mismatch")
    value["notarization"].update(status=status_value, submissionID=identifier, logSHA256=digest(log_path), logPath=log_path.relative_to(workspace).as_posix())
    value["stage"] = "NOTARIZED" if status_value == "Accepted" else "NOTARY_REJECTED"
    save_manifest(package, value)
    return {"status": value["stage"], "submissionID": identifier, "stapled": False}


def staple_candidate(args):
    network_execution(args)
    workspace, package = payload(args.workspace)
    value = verify_package(package)
    require(value["stage"] == "NOTARIZED" and value["notarization"]["status"] == "Accepted", "staple_requires_accepted_job")
    verify_package(package, native_team=value["signature"]["teamID"])
    try:
        run(["xcrun", "stapler", "staple", "-v", package / APP], log=workspace / "staple.log")
        run(["xcrun", "stapler", "validate", "-v", package / APP], log=workspace / "staple-validate.log")
        require(verify_signature(package / APP, value["signature"]["teamID"], value["build"]["architectures"]) == value["signature"], "staple_changed_code_identity")
        value["stage"] = "STAPLED"; value["notarization"]["stapled"] = True
    except Exception:
        value["stage"] = "STAPLE_FAILED"; save_manifest(package, value)
        raise
    save_manifest(package, value)
    return {"status": "STAPLED", "gatekeeper": "NOT_RUN"}


def package_candidate(args):
    require(platform.system() == "Darwin", "macos_packaging_required", "BLOCKED_PLATFORM")
    workspace, package = payload(args.workspace)
    value = verify_package(package)
    require(value["stage"] == "STAPLED", "distribution_requires_stapled_candidate")
    verify_package(package, native_team=value["signature"]["teamID"])
    distribution = workspace / "distribution"
    require(not distribution.exists(), "distribution_already_exists")
    distribution.mkdir()
    build = value["build"]
    arch = "universal" if len(build["architectures"]) == 2 else build["architectures"][0]
    archive = distribution / ("Riftlet-" + build["version"] + "-" + build["build"] + "-" + arch + ".zip")
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", package, archive])
    verify_archive(archive, digest(archive))
    identity = {"schemaVersion": SCHEMA, "archive": archive.name, "sha256": digest(archive), "bytes": archive.stat().st_size,
                "manifestSHA256": digest(package / MANIFEST), "version": build["version"], "build": build["build"],
                "source": build["source"]["commit"], "architectures": build["architectures"],
                "teamID": value["signature"]["teamID"], "stage": "STAPLED", "gatekeeper": "NOT_RUN",
                "publicReleaseApproval": "NOT_GRANTED_BY_TOOL"}
    write_json(distribution / "release-artifact.json", identity)
    return {"status": "PACKAGED_NOT_PUBLISHED", **identity}


def verify_archive(path, expected_sha):
    path = safe_path(path)
    require(path.is_file(), "archive_file_required")
    require(re.fullmatch(r"[0-9a-f]{64}", expected_sha or "") is not None, "trusted_archive_pin_required")
    require(digest(path) == expected_sha, "archive_pin_mismatch")
    with zipfile.ZipFile(path) as archive:
        rows, names, total = {}, set(), 0
        require(len(archive.infolist()) <= 20000, "too_many_archive_entries")
        for item in archive.infolist():
            p = PurePosixPath(item.filename)
            require(not p.is_absolute() and ".." not in p.parts and "\\" not in item.filename
                    and p.parts and p.parts[0] in {PAYLOAD, "__MACOSX"}
                    and item.filename == p.as_posix() + ("/" if item.is_dir() else "")
                    and "\x00" not in item.filename, "unsafe_archive_path")
            canonical = p.as_posix().casefold()
            require(canonical not in names, "duplicate_archive_path")
            names.add(canonical)
            mode = item.external_attr >> 16
            require(not item.flag_bits & 1 and not stat.S_ISLNK(mode)
                    and (stat.S_IFMT(mode) in {0, stat.S_IFREG, stat.S_IFDIR}), "unsafe_archive_entry")
            total += item.file_size
            require(total <= 2 * 1024**3, "archive_expansion_too_large")
            require(len(p.parts) != 1 or item.is_dir(), "archive_root_is_not_directory")
            if p.parts[0] == PAYLOAD and len(p.parts) > 1:
                rows[PurePosixPath(*p.parts[1:]).as_posix()] = item
        require(MANIFEST in rows, "archive_manifest_missing")
        require(rows[MANIFEST].file_size <= 8 * 1024 * 1024, "oversized_json")
        manifest = decode_json(archive.read(rows.pop(MANIFEST)))
        validate_manifest(manifest)
        require(set(rows) == set(manifest.get("files", {})), "archive_inventory_mismatch")
        require({PurePosixPath(name).parts[0] for name in rows} == {APP, "INSTALL-zh-CN.txt"}, "archive_payload_layout_mismatch")
        for name, item in rows.items():
            expected = manifest["files"][name]
            require(expected["kind"] == ("directory" if item.is_dir() else "file"), "archive_entry_type_mismatch")
            require(stat.S_IMODE(item.external_attr >> 16) == expected["mode"], "archive_mode_mismatch")
            if not item.is_dir():
                require(item.file_size == expected["size"] and sha(archive.read(item)) == expected["sha256"], "archive_file_mismatch")
        receipt = decode_json(archive.read(PAYLOAD + "/" + APP + "/" + RECEIPT))
        validate_receipt(receipt)
        require(receipt == manifest.get("build"), "archive_build_mismatch")
        plist_bytes = archive.read(PAYLOAD + "/" + APP + "/Contents/Info.plist")
        validate_release_info(plistlib.loads(plist_bytes), receipt)
        require(sha(plist_bytes) == receipt["infoPlistSHA256"], "archive_plist_receipt_mismatch")
        require(sha(archive.read(PAYLOAD + "/INSTALL-zh-CN.txt")) == receipt["preparationInputs"]["packaging/release/INSTALL-zh-CN.txt"], "archive_install_notes_mismatch")
        binary_name = APP + "/Contents/MacOS/Riftlet"
        require(rows[binary_name].external_attr >> 16 & stat.S_IXUSR, "archive_binary_not_executable")
        require(macho_arches(archive.read(PAYLOAD + "/" + binary_name)) == receipt["architectures"], "archive_arch_mismatch")
        require({name for name in rows if name.startswith(APP + "/Contents/MacOS/")} == {binary_name}, "archive_unexpected_executable")
        return {"status": "OFFLINE_ARCHIVE_IDENTITY_MATCH", "source": receipt["source"]["commit"],
                "version": receipt["version"], "build": receipt["build"], "architectures": receipt["architectures"],
                "recordedStage": manifest.get("stage"), "nativeSignatureCheck": "NOT_RUN", "gatekeeper": "NOT_RUN",
                "xattrs": "transport_bound_by_whole_archive_pin; not extracted or applied"}


def update_plan(args):
    require(args.manifest_sha256, "trusted_manifest_pin_required")
    candidate = verify_package(args.package, args.manifest_sha256, args.team)
    require(candidate["stage"] == "STAPLED" and args.team, "manual_update_requires_stapled_identity")
    current = safe_path(args.current_app)
    require(current.suffix == ".app" and current.is_dir(), "current_app_required")
    current_info = safe_path(current / "Contents/Info.plist")
    current_binary = safe_path(current / "Contents/MacOS/Riftlet")
    require(current_info.is_file() and current_binary.is_file(), "current_app_identity_files_required")
    info = plistlib.loads(current_info.read_bytes())
    require(info.get("CFBundleIdentifier") == "com.riftlet.app", "current_bundle_identifier_mismatch")
    version_values(info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"))
    current_arches = macho_arches(current_binary.read_bytes())
    build = candidate["build"]
    require(platform.machine() in build["architectures"], "candidate_cannot_run_natively_on_this_host")
    direction = "upgrade" if int(build["build"]) > int(info["CFBundleVersion"]) else "rollback" if int(build["build"]) < int(info["CFBundleVersion"]) else "same-build"
    return {"status": "MANUAL_PLAN_ONLY", "direction": direction, "currentVersion": info["CFBundleShortVersionString"],
            "currentBuild": info["CFBundleVersion"], "currentArchitectures": current_arches,
            "candidateVersion": build["version"], "candidateBuild": build["build"], "candidateSource": build["source"]["commit"],
            "currentAppTrust": "NOT_ASSERTED_BY_READING_ITS_PLIST", "dataCompatibility": "REVIEW_REQUIRED",
            "rollback": "BLOCKED_UNTIL_CURRENT_DATA_COMPATIBILITY_IS_PROVEN" if direction != "upgrade" else "retain_previous_app; do_not_restore_old_database",
            "actionsPerformed": [], "instructions": ["Quit Riftlet and verify all writers have stopped.",
                "Retain the current App and a consistent full data backup; do not export Keychain secrets.",
                "Manually replace only after independent source/release/data review; never run both against one data root.",
                "Do not delete, downgrade, reset or replay queue, media, UNKNOWN or Feedback state."]}


def preflight(args):
    credential_values(args.identity, args.team, args.profile, signing=True, notary=True)
    require(platform.system() == "Darwin", "macos_required", "BLOCKED_PLATFORM")
    for tool in ("swift", "codesign", "ditto", "security"):
        require(shutil.which(tool) is not None, "tool_missing_" + tool, "BLOCKED_TOOLCHAIN")
    for tool in ("notarytool", "stapler"):
        run(["xcrun", "--find", tool])
    identity_available(args.identity, args.team)
    return {"status": "LOCAL_PREREQUISITES_READY", "teamID": args.team,
            "notaryCredentialValidation": "NOT_CONTACTED", "signing": "NOT_RUN", "network": "NOT_USED"}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    commands = p.add_subparsers(dest="command", required=True)
    def credentials(c, signing=False, notary=False):
        if signing:
            c.add_argument("--identity"); c.add_argument("--team")
        if notary:
            c.add_argument("--profile", help="Existing notarytool Keychain profile name; never a password")
    def execute(c):
        c.add_argument("--execute", action="store_true"); c.add_argument("--allow-network", action="store_true")
    c = commands.add_parser("preflight"); credentials(c, True, True)
    c = commands.add_parser("build"); c.add_argument("--repository", type=Path, default=ROOT)
    c.add_argument("--source", required=True); c.add_argument("--version", required=True); c.add_argument("--build", required=True)
    c.add_argument("--arch", action="append", choices=sorted(ARCHES.values()), required=True); c.add_argument("--workspace", type=Path, required=True)
    for command in ("sign", "notary-submit", "notary-status", "staple", "package"):
        c = commands.add_parser(command); c.add_argument("--workspace", type=Path, required=True)
        if command != "package": execute(c)
        if command == "sign": credentials(c, signing=True)
        if command.startswith("notary-"): credentials(c, notary=True)
        if command == "notary-status": c.add_argument("--submission-id")
    c = commands.add_parser("verify"); c.add_argument("--package", type=Path, required=True)
    c.add_argument("--manifest-sha256"); c.add_argument("--team", help="Also perform offline native Developer ID validation on macOS")
    c = commands.add_parser("verify-archive"); c.add_argument("--archive", type=Path, required=True); c.add_argument("--sha256", required=True)
    c = commands.add_parser("update-plan"); c.add_argument("--package", type=Path, required=True)
    c.add_argument("--manifest-sha256", required=True); c.add_argument("--team", required=True); c.add_argument("--current-app", type=Path, required=True)
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if args.command == "verify":
            value = verify_package(args.package, args.manifest_sha256, args.team)
            result = {"status": "OFFLINE_CONTENTS_MATCH", "recordedStage": value["stage"],
                      "manifestPin": "MATCH" if args.manifest_sha256 else "NOT_PROVIDED_NOT_AUTHENTICATED",
                      "nativeSignatureCheck": "PASS" if args.team else "NOT_RUN", "gatekeeper": "NOT_RUN"}
        elif args.command == "verify-archive": result = verify_archive(args.archive, args.sha256)
        else:
            result = {"preflight": preflight, "build": build_candidate, "sign": sign_candidate,
                      "notary-submit": notary_submit, "notary-status": notary_status,
                      "staple": staple_candidate, "package": package_candidate, "update-plan": update_plan}[args.command](args)
    except ReleaseError as error:
        print(json.dumps({"status": error.status, "code": error.code}, sort_keys=True))
        return 3 if error.status.startswith("BLOCKED_") else 2
    except (OSError, ValueError, TypeError, KeyError, plistlib.InvalidFileException, subprocess.TimeoutExpired, zipfile.BadZipFile, BUNDLE.VerificationError) as error:
        print(json.dumps({"status": "FAIL", "code": "invalid_input_or_tool_result", "errorType": type(error).__name__}, sort_keys=True))
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
