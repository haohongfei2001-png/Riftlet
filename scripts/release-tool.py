#!/usr/bin/env python3
"""Separate release preparation. No install, key export, or implicit network.

Build/verify are local; sign, notarize and staple require explicit execution and
network flags. Missing configured credentials is BLOCKED_CREDENTIALS, not PASS.
Content hashes are identity checks; trust requires a separately obtained pin.
"""
import argparse
import base64
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
SPARKLE = BUNDLE.SPARKLE
SCHEMA = 1
KIND = "riftlet-release-candidate"
PAYLOAD = "Riftlet-Release"
MANIFEST = "release-manifest.json"
APP = "Riftlet.app"
RECEIPT = "Contents/Resources/release-build.json"
SHARED_APP_MODES = "directories-and-main-0755-files-0644"
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


def run(args, *, cwd=None, timeout=120, input=None, log=None, umask=-1):
    # Argument arrays only. Never shell-expand identity, paths or profile names.
    try:
        result = subprocess.run([str(a) for a in args], cwd=cwd, input=input,
                                capture_output=True, timeout=timeout, check=False, umask=umask)
    except subprocess.TimeoutExpired as error:
        if log:
            Path(log).write_bytes((error.stdout or b"") + (error.stderr or b"") + b"\nTIMEOUT\n")
        raise
    if log:
        Path(log).write_bytes(result.stdout + result.stderr)
    require(result.returncode == 0, "command_failed_" + Path(str(args[0])).name)
    return result


def copy_distribution_tree(*args, log=None):
    # On macOS ditto applies the process umask when restoring symlinks. The
    # caller owns a private staging parent; only this child gets distribution
    # creation modes. ZIPs, logs and all other release files stay private.
    return run(["/usr/bin/ditto", *args], log=log, umask=0o022)


def git(repository, *args):
    return run(["git", "-C", repository, *args]).stdout.decode().strip()


def full_sha(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value), "full_source_sha_required")
    return value


def version_values(version, build):
    require(isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+", version), "invalid_version")
    require(isinstance(build, str) and re.fullmatch(r"[1-9]\d*", build), "invalid_build")


def version_label(value):
    require(isinstance(value, str) and value == value.strip() and 1 <= len(value) <= 64
            and all(character.isprintable() for character in value), "invalid_version_label")


def stage_version(info, version, build, label, *, stable=False):
    version_values(version, build); version_label(label)
    keys = ("CFBundleShortVersionString", "CFBundleVersion", "RiftletVersionLabel")
    source = {key: info.get(key) for key in keys}
    version_values(source[keys[0]], source[keys[1]])
    if source[keys[2]] is not None:
        version_label(source[keys[2]])
    if stable:
        require((source[keys[0]], source[keys[1]], source[keys[2]]) == (version, build, "Riftlet")
                and label == "Riftlet", "stable_version_differs_from_source")
    info.update(CFBundleShortVersionString=version, CFBundleVersion=build,
                RiftletVersionLabel=label, RiftletBuildChannel="release" if stable else "release-candidate")
    return source


def hash_value(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def entitlement_policy(value):
    return isinstance(value, dict) and set(value) == set(ENTITLEMENTS) and all(value[k] is True for k in ENTITLEMENTS)


def macho_arches(data, *, filetype=2):
    """Parse actual Mach-O headers/slices, not the packaging host's CPU."""
    require(len(data) >= 8, "truncated_macho")
    magic = bytes(data[:4])
    if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
        require(len(data) >= 32, "truncated_macho")
        cpu = struct.unpack_from(endian + "I", data, 4)[0]
        require(cpu in ARCHES, "unsupported_macho_arch")
        require(struct.unpack_from(endian + "I", data, 12)[0] == filetype, "macho_not_executable")
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
        require(macho_arches(slice_data, filetype=filetype) == [ARCHES[cpu]], "fat_slice_arch_mismatch")
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
    keys = read(["-s", "--", str(path)]).splitlines()
    require(len(keys) == len(set(keys)), "duplicate_xattr_name")
    return {key: sha(bytes.fromhex(read(["-spx", "--", key, str(path)]))) for key in sorted(keys) if key not in TRANSFER_XATTRS}


def inventory(root):
    root = safe_path(root)
    require(root.is_dir(), "missing_payload")
    result, names = {}, set()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == MANIFEST:
            continue
        info = path.lstat()
        linked = stat.S_ISLNK(info.st_mode)
        if linked:
            in_app = relative if root.name == APP else relative.removeprefix(APP + "/")
            require((root.name == APP or relative.startswith(APP + "/"))
                    and SPARKLE.LINKS.get(in_app) == os.readlink(path), "unsafe_payload_entry")
            result[relative] = {"kind": "symlink", "target": os.readlink(path),
                                "mode": stat.S_IMODE(info.st_mode), "xattrs": xattr_hashes(path)}
        else:
            require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode), "unsafe_payload_entry")
        require(relative.casefold() not in names, "case_colliding_payload_entry")
        names.add(relative.casefold())
        if linked:
            continue
        row = {"kind": "directory" if path.is_dir() else "file", "mode": stat.S_IMODE(info.st_mode),
               "xattrs": xattr_hashes(path)}
        if path.is_file():
            require(info.st_nlink == 1, "hard_linked_payload_entry")
            row.update(size=info.st_size, sha256=digest(path))
        result[relative] = row
    return result


def app_modes(files):
    for name, row in files.items():
        if name == APP or name.startswith(APP + "/"):
            binary = name.removeprefix(APP + "/")
            mode = 0o755 if row["kind"] in {"directory", "symlink"} or binary == "Contents/MacOS/Riftlet" or binary in SPARKLE.EXECUTABLES else 0o644
            yield name, row["mode"], mode


def verify_app_modes(files):
    for name, current, expected in app_modes(files):
        require(current == expected, "distribution_app_mode_mismatch:" + name)


def normalize_staged_app(package):
    # inventory validates every entry (including links) before the first chmod.
    # Check nested code independently before clearing execute bits on resources.
    files = inventory(package)
    verify_code_layout(package / APP)
    for name, current, expected in app_modes(files):
        if current != expected:
            if files[name]["kind"] == "symlink":
                os.lchmod(package / name, expected)
            else:
                (package / name).chmod(expected)


def validate_receipt(receipt):
    require(isinstance(receipt, dict) and type(receipt.get("schemaVersion")) is int and receipt["schemaVersion"] == SCHEMA, "invalid_build_receipt")
    version_values(receipt.get("version"), receipt.get("build"))
    if "permissionLanguages" in receipt:
        require(receipt["permissionLanguages"] == list(PERMISSION_LANGUAGES), "invalid_permission_languages")
    if "sharedAppModes" in receipt:
        require(receipt["sharedAppModes"] == SHARED_APP_MODES, "unknown_app_modes")
    # Existing schema-1 receipts remain verifiable; new builds always bind all
    # three version fields. Do not rewrite old preparation evidence.
    if "versionLabel" in receipt or "sourceVersion" in receipt:
        version_label(receipt.get("versionLabel"))
        source_version = receipt.get("sourceVersion")
        require(isinstance(source_version, dict) and set(source_version) == {
            "CFBundleShortVersionString", "CFBundleVersion", "RiftletVersionLabel"}, "invalid_source_version")
        version_values(source_version["CFBundleShortVersionString"], source_version["CFBundleVersion"])
        if source_version["RiftletVersionLabel"] is not None:
            version_label(source_version["RiftletVersionLabel"])
    if "distributionChannel" in receipt:
        require(receipt["distributionChannel"] == "stable"
                and receipt.get("versionLabel") == "Riftlet"
                and receipt.get("sourceVersion") == {
                    "CFBundleShortVersionString": receipt["version"],
                    "CFBundleVersion": receipt["build"],
                    "RiftletVersionLabel": "Riftlet"}, "invalid_stable_release_identity")
    require(receipt.get("bundleIdentifier") == "com.riftlet.app", "wrong_bundle_identifier")
    source = receipt.get("source", {})
    require(isinstance(source, dict) and isinstance(source.get("inputs"), dict), "invalid_source_inputs")
    full_sha(source.get("commit")); full_sha(source.get("tree"))
    has_updater = "sparkleVersion" in receipt
    if has_updater:
        require(receipt["sparkleVersion"] == SPARKLE.VERSION, "unknown_sparkle_version")
    expected_inputs = set(BUILD_INPUTS) | ({"Package.resolved"} if has_updater else set())
    require(set(source["inputs"]) == expected_inputs, "invalid_source_inputs")
    for value in source["inputs"].values():
        full_sha(value)
    arches = receipt.get("architectures")
    require(isinstance(arches, list) and arches == sorted(set(arches)) and arches
            and set(arches) <= set(ARCHES.values()), "invalid_architectures")
    require(receipt.get("dataCompatibility") == "NOT_ASSERTED", "unreviewed_data_compatibility_claim")
    require(receipt.get("minimumMacOS") == "13.0" and receipt.get("buildInfoExecutedOn") in ARCHES.values(), "invalid_build_platform")
    require(hash_value(receipt.get("infoPlistSHA256")), "invalid_plist_hash")
    preparation = receipt.get("preparationInputs", {})
    expected_preparation = set(PREPARATION_INPUTS) | ({"scripts/sparkle_bundle.py"} if has_updater else set())
    require(isinstance(preparation, dict) and set(preparation) == expected_preparation
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
        arch_entries = list(signature["architectures"].values())
        if value["build"].get("sparkleVersion"):
            components = signature.get("sparkle")
            require(isinstance(components, dict) and set(components) == {path for path, _, _ in SPARKLE.COMPONENTS},
                    "invalid_nested_signature_receipt")
            for nested in components.values():
                require(isinstance(nested, dict) and nested.get("teamID") == signature["teamID"]
                        and nested.get("hardenedRuntime") is True and nested.get("entitlements") == {}
                        and isinstance(nested.get("architectures"), dict)
                        and set(nested["architectures"]) == set(ARCHES.values()), "invalid_nested_signature_receipt")
                arch_entries.extend(nested["architectures"].values())
        for entry in arch_entries:
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
        require(isinstance(row, dict) and row.get("kind") in {"directory", "file", "symlink"}
                and type(row.get("mode")) is int and 0 <= row["mode"] <= 0o777, "invalid_inventory_metadata")
        require(isinstance(row.get("xattrs"), dict) and all(isinstance(k, str) and hash_value(v) for k, v in row["xattrs"].items()), "invalid_inventory_xattrs")
        if row["kind"] == "symlink":
            require(value["build"].get("sparkleVersion") and name.startswith(APP + "/")
                    and name[len(APP) + 1:] in SPARKLE.LINKS
                    and row.get("target") == SPARKLE.LINKS[name[len(APP) + 1:]], "invalid_inventory_link")
        if row["kind"] == "file":
            require(type(row.get("size")) is int and row["size"] >= 0 and hash_value(row.get("sha256")), "invalid_inventory_file")

    # Old manifests remain usable for inspecting and rolling back to their exact bytes.
    if value["build"].get("sharedAppModes") and stage != "SIGN_FAILED":
        verify_app_modes(files)


PERMISSION_LANGUAGES = ("en", "zh-Hans")
PERMISSION_KEYS = (*BUNDLE.USAGE_KEYS, "NSScreenCaptureUsageDescription")


def localized_permissions(data, language, info):
    require(data, "missing_localized_permissions")
    try:
        values = plistlib.loads(data)
    except (ValueError, plistlib.InvalidFileException):
        raise ReleaseError("invalid_localized_permissions") from None
    require(isinstance(values, dict) and set(values) == set(PERMISSION_KEYS)
            and all(isinstance(v, str) and 10 <= len(v.strip()) <= 512 for v in values.values()),
            "invalid_localized_permissions")
    if language == "zh-Hans":
        require(all(values[k] == info[k] for k in PERMISSION_KEYS), "localized_purpose_fallback_mismatch")


def copy_permission_localizations(source_resources, destination, info):
    # Earlier source checkpoints did not ship localized purpose strings.
    if not any((source_resources / (language + ".lproj")).exists() for language in PERMISSION_LANGUAGES):
        return False
    for language in PERMISSION_LANGUAGES:
        relative = Path(language + ".lproj") / "InfoPlist.strings"
        source = source_resources / relative
        localized_permissions(source.read_bytes() if source.is_file() else None, language, info)
        (destination / relative.parent).mkdir()
        shutil.copy2(source, destination / relative)
    return True


def validate_release_info(info, receipt):
    require(isinstance(info, dict), "invalid_info_plist")
    expected = {"CFBundleExecutable": "Riftlet", "CFBundleIdentifier": "com.riftlet.app",
                "CFBundleName": "Riftlet", "CFBundleDisplayName": "Riftlet", "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": receipt["version"], "CFBundleVersion": receipt["build"],
                "LSMinimumSystemVersion": "13.0", "LSUIElement": True, "NSHighResolutionCapable": True,
                "LSApplicationCategoryType": "public.app-category.utilities",
                "RiftletBuildChannel": "release" if receipt.get("distributionChannel") == "stable" else "release-candidate"}
    for key, value in expected.items():
        require(type(info.get(key)) is type(value) and info[key] == value, "invalid_release_" + key)
    if receipt.get("sparkleVersion"):
        updater = {"SUFeedURL": "https://riftlet.com/updates/stable.xml", "SURequireSignedFeed": True,
                   "SUSignedFeedFailureExpirationInterval": 0, "SUVerifyUpdateBeforeExtraction": True,
                   "SUEnableAutomaticChecks": True,
                   "SUAutomaticallyUpdate": False, "SUAllowsAutomaticUpdates": False,
                   "SUScheduledCheckInterval": 86400}
        for key, expected_value in updater.items():
            require(type(info.get(key)) == type(expected_value) and info[key] == expected_value,
                    "invalid_updater_" + key)
        public_key = info.get("SUPublicEDKey")
        require(isinstance(public_key, str) and re.fullmatch(r"[A-Za-z0-9+/]{43}=", public_key)
                and len(base64.b64decode(public_key, validate=True)) == 32, "invalid_updater_public_key")
    if "versionLabel" in receipt:
        require(info.get("RiftletVersionLabel") == receipt["versionLabel"], "invalid_release_RiftletVersionLabel")
    require("RiftletDeveloperIDSigned" not in info and "RiftletNotarized" not in info, "plist_cannot_claim_signing_status")
    for key in PERMISSION_KEYS:
        require(isinstance(info.get(key), str) and 10 <= len(info[key].strip()) <= 512, "invalid_usage_description")


def verify_code_layout(app):
    """Admit only the host and the five reviewed universal Sparkle code objects."""
    main = app / "Contents/MacOS/Riftlet"
    magics = {bytes.fromhex(m) for m in ("feedface", "cefaedfe", "feedfacf", "cffaedfe",
                                         "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
    with_updater = (app / "Contents/Frameworks").exists()
    if with_updater:
        SPARKLE.validate_layout(app, require)
    for entry in app.rglob("*"):
        if entry == main or entry.is_symlink() or not entry.is_file():
            continue
        relative = entry.relative_to(app).as_posix()
        if with_updater and relative in SPARKLE.EXECUTABLES:
            filetype = 6 if relative == SPARKLE.BASE + "Sparkle" else 2
            require(macho_arches(entry.read_bytes(), filetype=filetype) == ["arm64", "x86_64"], "invalid_sparkle_architectures")
            continue
        if with_updater and relative in SPARKLE.CODE_PLISTS:
            continue
        reason = "unreviewed_nested_code:" + relative
        require(not entry.stat().st_mode & 0o111, reason)
        with entry.open("rb") as stream:
            require(stream.read(4) not in magics, reason)
        if entry.name == "Info.plist" and entry != app / "Contents/Info.plist":
            info = plistlib.loads(entry.read_bytes())
            require(isinstance(info, dict) and not info.get("CFBundleExecutable"), reason)


TICKET_CARRIER = APP + "/Contents/CodeResources"


def verify_accepted_app_log(workspace, value):
    note = value["notarization"]
    require(value["stage"] in {"NOTARIZED", "STAPLE_FAILED", "STAPLED"} and note["status"] == "Accepted",
            "accepted_app_notary_job_required")
    relative = PurePosixPath(note.get("logPath") or "")
    require(len(relative.parts) == 2 and relative.parts[0].startswith("notary-query-")
            and relative.parts[1] == note["submissionID"] + ".notary-log.json"
            and relative.as_posix() == note.get("logPath"), "invalid_accepted_app_log_path")
    logfile = safe_path(Path(workspace) / relative)
    require(logfile.is_file() and logfile.stat().st_size <= 8 * 1024**2, "invalid_accepted_app_log_file")
    raw = logfile.read_bytes()
    require(sha(raw) == note["logSHA256"], "accepted_app_log_digest_mismatch")
    log = decode_json(raw)
    require(isinstance(log, dict) and log.get("jobId") == note["submissionID"]
            and log.get("status") == "Accepted" and str(log.get("sha256", "")).lower() == note["uploadSHA256"],
            "accepted_app_log_artifact_mismatch")


def check_staple_inventory(original, current, *, native_ticket_rewrite=False):
    if original == current:
        return
    require({k: v for k, v in original.items() if k != TICKET_CARRIER}
            == {k: v for k, v in current.items() if k != TICKET_CARRIER}, "payload_inventory_mismatch")
    carrier = current.get(TICKET_CARRIER, {})
    require(carrier.get("kind") == "file" and carrier["size"] > 0 and not carrier["mode"] & 0o111,
            "invalid_ticket_carrier")
    if TICKET_CARRIER in original:
        prior = original[TICKET_CARRIER]
        # Under the private release umask, Apple's stapler can replace an existing
        # readable ticket with a new 0600 file. Only that transition is resumable;
        # signature, Apple ticket, accepted submission and all other entries are verified.
        same_mode = carrier["mode"] == prior["mode"]
        rewritten = native_ticket_rewrite and (prior["mode"], carrier["mode"]) == (0o644, 0o600)
        require((same_mode or rewritten) and carrier["xattrs"] == prior["xattrs"],
                "ticket_carrier_metadata_changed")


def load_package_for_resume(package, expected_manifest=None, native_team=None):
    """Read the recorded stage without adopting changes or certifying a ticket."""
    return _verify_package(package, expected_manifest, native_team, staple_resume=True)


def verify_package(package, expected_manifest=None, native_team=None):
    return _verify_package(package, expected_manifest, native_team, staple_resume=False)


def _verify_package(package, expected_manifest, native_team, *, staple_resume):
    package = safe_path(package)
    require(package.is_dir() and {p.name for p in package.iterdir()} == {APP, MANIFEST, "INSTALL-zh-CN.txt"}, "invalid_payload_layout")
    require((package / MANIFEST).is_file() and not (package / MANIFEST).is_symlink(), "missing_or_linked_json")
    if expected_manifest:
        require(re.fullmatch(r"[0-9a-f]{64}", expected_manifest) is not None
                and digest(package / MANIFEST) == expected_manifest, "manifest_pin_mismatch")
    value = read_json(package / MANIFEST)
    validate_manifest(value)
    current = inventory(package)
    recovering = staple_resume and value["stage"] in {"NOTARIZED", "STAPLE_FAILED"}
    if recovering:
        verify_accepted_app_log(package.parent, value)
        check_staple_inventory(value["files"], current, native_ticket_rewrite=bool(value["build"].get("sharedAppModes")))
        native_team = native_team or value["signature"]["teamID"]
    else:
        require(value["files"] == current, "payload_inventory_mismatch")
    app = package / APP
    receipt = read_json(app / RECEIPT)
    validate_receipt(receipt)
    require(value.get("build") == receipt, "receipt_manifest_mismatch")
    require(digest(package / "INSTALL-zh-CN.txt") == receipt["preparationInputs"]["packaging/release/INSTALL-zh-CN.txt"], "install_notes_receipt_mismatch")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    validate_release_info(info, receipt)
    for language in receipt.get("permissionLanguages", []):
        path = app / "Contents/Resources" / (language + ".lproj") / "InfoPlist.strings"
        localized_permissions(path.read_bytes() if path.is_file() else None, language, info)
    try:
        BUNDLE.verify_app_icon(app, info)
    except BUNDLE.VerificationError as error:
        require(False, str(error))
    require(sha((app / "Contents/Info.plist").read_bytes()) == receipt.get("infoPlistSHA256"), "plist_receipt_mismatch")
    binary = app / "Contents/MacOS/Riftlet"
    require(binary.stat().st_mode & stat.S_IXUSR, "binary_not_executable")
    require(macho_arches(binary.read_bytes()) == receipt["architectures"], "binary_arch_mismatch")
    require(set(p.name for p in app.iterdir()) == {"Contents"}, "unexpected_app_root")
    contents = {"Info.plist", "MacOS", "Resources", "_CodeSignature"}
    if receipt.get("sparkleVersion"):
        contents.add("Frameworks")
        require((app / SPARKLE.FRAMEWORK).is_dir(), "missing_sparkle_framework")
        require((app / "Contents/Resources/ThirdPartyNotices/Sparkle/LICENSE").is_file(), "missing_sparkle_notice")
    ticket = app / "Contents/CodeResources"
    if (recovering or value["stage"] in {"STAPLED", "STAPLE_FAILED"}) and ticket.exists():
        # stapler can add this ordinary file alongside the original sealed code.
        # Acceptance is verified by stapler, never by the existence of the file.
        require(ticket.is_file() and ticket.stat().st_size > 0, "invalid_ticket_carrier")
        contents.add(ticket.name)
    require(set(p.name for p in (app / "Contents").iterdir()) <= contents, "unexpected_app_contents")
    require(set(p.name for p in (app / "Contents/MacOS").iterdir()) == {"Riftlet"}, "unexpected_executable")
    verify_code_layout(app)
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
    result = verify_code_signature(app, team, arches, "com.riftlet.app", ENTITLEMENTS, deep=True)
    if (app / SPARKLE.FRAMEWORK).exists():
        result["sparkle"] = {component: verify_code_signature(app / component, team, sorted(ARCHES.values()), identifier, {})
                             for component, _, identifier in SPARKLE.COMPONENTS}
    return result


def verify_code_signature(app, team, arches, identifier, expected_entitlements, *, deep=False):
    requirement = ('anchor apple generic and identifier "' + identifier + '" and certificate leaf[subject.OU] = "'
                   + team + '" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and '
                   'certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
    run(["/usr/bin/codesign", "--verify", *(["--deep"] if deep else []), "--strict", "--all-architectures", "-R", "=" + requirement, app])
    result = {"teamID": team, "hardenedRuntime": True, "entitlements": expected_entitlements, "architectures": {}}
    for arch in arches:
        detail = run(["/usr/bin/codesign", "-d", "--verbose=4", "--arch", arch, app]).stderr.decode()
        def field(name):
            matches = re.findall(r"^" + re.escape(name) + r"=(.+)$", detail, re.M)
            require(len(matches) == 1, "missing_signature_" + name)
            return matches[0]
        require(field("Identifier") == identifier and field("TeamIdentifier") == team, "wrong_signature_identity")
        require(re.search(r"^Authority=Developer ID Application:", detail, re.M), "not_developer_id_application")
        require(re.search(r"flags=0x[0-9a-f]+\([^\n)]*runtime[^\n)]*\)", detail), "hardened_runtime_missing")
        timestamp = field("Timestamp")
        require(timestamp not in {"none", "Not set"}, "secure_timestamp_missing")
        cdhash = field("CDHash")
        require(re.fullmatch(r"[0-9a-f]{40}", cdhash), "invalid_cdhash")
        ent = run(["/usr/bin/codesign", "-d", "--entitlements", ":-", "--arch", arch, app]).stdout
        actual = plistlib.loads(ent) if ent else {}
        require(entitlement_policy(actual) if expected_entitlements else actual == {}, "unexpected_entitlements")
        result["architectures"][arch] = {"cdhash": cdhash, "timestamp": timestamp}
    return result


def save_manifest(package, value):
    value["files"] = inventory(package)
    write_json(Path(package) / MANIFEST, value)


def export_source(repository, source, target):
    full_sha(source)
    require(git(repository, "rev-parse", source + "^{commit}") == source, "source_commit_mismatch")
    inputs = list(BUILD_INPUTS)
    if git(repository, "ls-tree", "--name-only", source, "Package.resolved"):
        inputs.append("Package.resolved")
    archive = run(["git", "-C", repository, "archive", source, "--", *inputs]).stdout
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
            "inputs": {key: git(repository, "rev-parse", source + ":" + key) for key in inputs}}


def build_candidate(args):
    require(platform.system() == "Darwin", "macos_build_required", "BLOCKED_PLATFORM")
    full_sha(args.source); version_values(args.version, args.build); version_label(args.label)
    arches = sorted(set(args.arch))
    require(len(arches) == len(args.arch), "duplicate_requested_arch")
    workspace = fresh_workspace(args.workspace)
    package = workspace / PAYLOAD; package.mkdir()
    source_dir = workspace / "source"; source_dir.mkdir()
    source = export_source(args.repository, args.source, source_dir)
    dependencies = decode_json(run(["swift", "package", "--package-path", source_dir, "dump-package"], timeout=120,
                                   log=workspace / "package-inspection.log").stdout)
    uses_updater = (source_dir / "Package.resolved").is_file()
    if uses_updater:
        SPARKLE.require_exact_dependency(dependencies.get("dependencies"), read_json(source_dir / "Package.resolved"))
    else:
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
    has_permission_localizations = copy_permission_localizations(source_dir / "Resources", app / "Contents/Resources",
                                                              plistlib.loads((app / "Contents/Info.plist").read_bytes()))
    if (source_dir / "Resources" / BUNDLE.ICON_NAME).exists():
        shutil.copy2(source_dir / "Resources" / BUNDLE.ICON_NAME, app / "Contents/Resources" / BUNDLE.ICON_NAME)
    # The source export may be a pre-consolidation release. Preserve its original resources.
    if (source_dir / "Resources/Presentation").is_dir():
        for name in BUNDLE.PRESENTATION_NAMES:
            shutil.copy2(source_dir / "Resources/Presentation" / name, app / "Contents/Resources" / name)
    shutil.copytree(source_dir / "ThirdPartyNotices", app / "Contents/Resources/ThirdPartyNotices")
    shutil.copytree(bin_dir / "Riftlet_RiftletAdapters.bundle", app / "Contents/Resources/Riftlet_RiftletAdapters.bundle")
    if uses_updater:
        SPARKLE.embed(workspace / "swift-build", app)
        SPARKLE.fix_host_runpaths(app, arches)
    # Preserve the old verifier's development contract before staging-only changes.
    BUNDLE.verify_bundle(app, source_dir)
    require(macho_arches((app / "Contents/MacOS/Riftlet").read_bytes()) == arches, "built_arch_mismatch")
    ordinary = decode_json(run([app / "Contents/MacOS/Riftlet", "--ordinary-build-info"], timeout=10).stdout)
    BUNDLE.verify_ordinary_build_info(ordinary, "development")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    stable = getattr(args, "stable", False)
    source_version = stage_version(info, args.version, args.build, args.label, stable=stable)
    info.pop("RiftletDeveloperIDSigned"); info.pop("RiftletNotarized")
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=True))
    receipt = {"schemaVersion": SCHEMA, "source": source, "version": args.version, "build": args.build,
               "versionLabel": args.label, "sourceVersion": source_version,
               "bundleIdentifier": "com.riftlet.app", "minimumMacOS": "13.0", "architectures": arches,
               "ordinaryBuildInfo": ordinary, "buildInfoExecutedOn": platform.machine(),
               "infoPlistSHA256": digest(app / "Contents/Info.plist"), "dataCompatibility": "NOT_ASSERTED",
               "preparationInputs": {key: digest(ROOT / key) for key in PREPARATION_INPUTS},
               "swiftVersion": run(["swift", "--version"]).stdout.decode().strip()}
    if uses_updater:
        receipt["sparkleVersion"] = SPARKLE.VERSION
        receipt["preparationInputs"]["scripts/sparkle_bundle.py"] = digest(ROOT / "scripts/sparkle_bundle.py")
    if has_permission_localizations:
        receipt["permissionLanguages"] = list(PERMISSION_LANGUAGES)
    if stable:
        receipt["distributionChannel"] = "stable"
    receipt["sharedAppModes"] = SHARED_APP_MODES
    write_json(app / RECEIPT, receipt)
    normalize_staged_app(package)
    shutil.copy2(ROOT / "packaging/release/INSTALL-zh-CN.txt", package / "INSTALL-zh-CN.txt")
    manifest = {"schemaVersion": SCHEMA, "kind": KIND, "stage": "PREPARED", "build": receipt,
                "sourceAdmission": "INDEPENDENT_REVIEW_REQUIRED", "signature": None, "notarization": None}
    save_manifest(package, manifest); verify_package(package)
    return {"status": "PREPARED", "workspace": str(workspace), "credentials": "NOT_USED",
            "source": args.source, "architectures": arches, "version": args.version, "build": args.build,
            "versionLabel": args.label}


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
        if value["build"].get("sparkleVersion"):
            SPARKLE.verify_upstream(package / APP / SPARKLE.FRAMEWORK)
            for index, (component, _, identifier) in enumerate(SPARKLE.COMPONENTS):
                run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--options", "runtime",
                     "--timestamp", "--identifier", identifier, package / APP / component],
                    timeout=180, log=workspace / ("sign-sparkle-" + str(index) + ".log"))
        run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--options", "runtime", "--timestamp",
             "--entitlements", entitlements, package / APP], timeout=180, log=workspace / "sign.log")
        if value["build"].get("sharedAppModes"):
            # codesign can create or replace the signature resources under the private umask.
            normalize_staged_app(package)
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
    require(not os.path.lexists(archive), "notary_archive_already_exists")
    attempt = Path(tempfile.mkdtemp(prefix="notary-prepare-", dir=workspace))
    candidate = attempt / "candidate.zip"
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", package / APP, candidate],
        log=attempt / "package.log")
    archive_pin = verify_notary_upload(candidate, value, workspace)
    # notarytool accepts a file path. Give it a separate private, read-only file:
    # a later write or replacement at the canonical archive cannot change this inode.
    upload = attempt / "submission.zip"
    shutil.copyfile(candidate, upload)
    upload.chmod(0o400)
    claim = candidate.lstat()
    upload_identity = upload.lstat()
    # Keep each attempt for diagnosis. Atomically claim the already verified inode;
    # competing submissions cannot overwrite it or reach the Apple invocation.
    try:
        os.link(candidate, archive, follow_symlinks=False)
    except FileExistsError:
        raise ReleaseError("notary_archive_already_exists") from None
    value["notarization"] = {"status": "SubmissionUnknown", "submissionID": None,
                              "uploadSHA256": archive_pin, "stapled": False, "preparation": attempt.name}
    value["stage"] = "NOTARY_SUBMITTING"; save_manifest(package, value)
    try:
        require(os.path.samestat(archive.lstat(), claim) and digest(archive) == archive_pin
                and os.path.samestat(upload.lstat(), upload_identity) and digest(upload) == archive_pin,
                "notary_archive_changed_before_submit")
    except (OSError, ReleaseError) as error:
        # No client was invoked. Retain the attempt and its independent copy.
        # A different claimant's path/state must never be removed or overwritten.
        write_json(attempt / "not-submitted.json", {"status": "NOT_SUBMITTED", "uploadSHA256": archive_pin,
                   "clientInvoked": False, "reason": "notary_archive_changed_before_submit"})
        if read_json(package / MANIFEST) == value:
            value.update(stage="SIGNED", notarization=None)
            write_json(package / MANIFEST, value)
            try:
                if os.path.samestat(archive.lstat(), claim):
                    archive.unlink()
            except FileNotFoundError:
                pass
        raise ReleaseError("notary_archive_changed_before_submit", "NOT_SUBMITTED") from error
    try:
        reply = run(["xcrun", "notarytool", "submit", upload, "--keychain-profile", args.profile, "--output-format", "json"], timeout=180,
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
    value = load_package_for_resume(package)
    require(value["stage"] in {"NOTARIZED", "STAPLE_FAILED"}, "staple_requires_accepted_job")
    recorded = value["files"]
    shared = bool(value["build"].get("sharedAppModes"))
    actual = inventory(package)
    check_staple_inventory(recorded, actual, native_ticket_rewrite=shared)
    attempt = Path(tempfile.mkdtemp(prefix="app-staple-", dir=workspace))
    original_manifest = (package / MANIFEST).read_bytes()
    require(decode_json(original_manifest) == value, "app_manifest_changed_before_stapling")
    (attempt / "input-manifest.json").write_bytes(original_manifest)
    try:
        # An interruption can leave a ticket for the original Accepted job on
        # disk. Validate that carrier first; a failed validation leaves an
        # explicit STAPLE_FAILED retry instead of silently replacing it.
        if recorded == actual:
            run(["xcrun", "stapler", "staple", "-v", package / APP], log=attempt / "staple.log")
        validated = inventory(package)
        check_staple_inventory(recorded, validated, native_ticket_rewrite=shared)
        if shared:
            if TICKET_CARRIER in validated and validated[TICKET_CARRIER]["mode"] != 0o644:
                (package / TICKET_CARRIER).chmod(0o644)
                validated = inventory(package)
                check_staple_inventory(recorded, validated)
            verify_app_modes(validated)
        run(["xcrun", "stapler", "validate", "-v", package / APP], log=attempt / "staple-validate.log")
        require(verify_signature(package / APP, value["signature"]["teamID"], value["build"]["architectures"]) == value["signature"], "staple_changed_code_identity")
        verify_accepted_app_log(workspace, value)
        final = inventory(package)
        require(final == validated, "payload_changed_after_staple_validation")
    except Exception:
        failed = inventory(package)
        check_staple_inventory(recorded, failed, native_ticket_rewrite=shared)
        # Never pin an unreadable ticket left by an interrupted write or replacement.
        if shared and failed.get(TICKET_CARRIER, {}).get("mode", 0o644) != 0o644:
            failed = recorded
        value.update(stage="STAPLE_FAILED", files=failed)
        write_json(package / MANIFEST, value)
        raise
    value.update(stage="STAPLED", files=final)
    value["notarization"]["stapled"] = True
    write_json(package / MANIFEST, value)
    return {"status": "STAPLED", "gatekeeper": "NOT_RUN"}


def package_candidate(args):
    require(platform.system() == "Darwin", "macos_packaging_required", "BLOCKED_PLATFORM")
    workspace, package = payload(args.workspace)
    value = verify_package(package)
    require(value["stage"] == "STAPLED", "distribution_requires_stapled_candidate")
    verify_package(package, native_team=value["signature"]["teamID"])
    manifest_pin = digest(package / MANIFEST)
    distribution = workspace / "distribution"
    require(not distribution.exists(), "distribution_already_exists")
    distribution.mkdir()
    build = value["build"]
    arch = "universal" if len(build["architectures"]) == 2 else build["architectures"][0]
    archive = distribution / ("Riftlet-" + build["version"] + "-" + build["build"] + "-" + arch + ".zip")
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", package, archive])
    archive_pin = verify_distribution_zip(archive, manifest_pin, workspace, value["signature"]["teamID"])
    require(verify_package(package, manifest_pin) == value, "candidate_changed_during_packaging")
    identity = {"schemaVersion": SCHEMA, "archive": archive.name, "sha256": archive_pin, "bytes": archive.stat().st_size,
                "manifestSHA256": manifest_pin, "version": build["version"], "build": build["build"],
                "source": build["source"]["commit"], "architectures": build["architectures"],
                "teamID": value["signature"]["teamID"], "stage": "STAPLED", "gatekeeper": "NOT_RUN",
                "publicReleaseApproval": "NOT_GRANTED_BY_TOOL"}
    require(digest(archive) == archive_pin, "archive_changed_after_verification")
    write_json(distribution / "release-artifact.json", identity)
    return {"status": "PACKAGED_NOT_PUBLISHED", **identity}


def verify_review_dmg(image, manifest_pin, workspace):
    """Inspect only our newly created image, read-only, without Finder or App launch."""
    run(["/usr/bin/hdiutil", "verify", image], log=workspace / "review-dmg-verify.log")
    mount = Path(tempfile.mkdtemp(prefix="review-mount-", dir=workspace))
    attached = False
    try:
        reply = run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                     "-mountpoint", mount, "-plist", image], log=workspace / "review-dmg-attach.log")
        attached = True
        description = plistlib.loads(reply.stdout)
        points = [entry.get("mount-point") for entry in description.get("system-entities", [])
                  if entry.get("mount-point")]
        require(points == [str(mount)] and os.path.ismount(mount), "review_dmg_wrong_mount")
        value = verify_package(mount / PAYLOAD, manifest_pin)
        require(value["stage"] == "PREPARED", "review_dmg_stage_changed")
        require((mount / "REVIEW-ONLY.txt").read_bytes() == REVIEW_NOTICE, "review_dmg_notice_mismatch")
    finally:
        # An unsuccessful attach can still leave its owned mount behind. Never
        # force-eject or detach another volume; failure keeps logs and prevents a
        # successful artifact receipt.
        if attached or os.path.ismount(mount):
            run(["/usr/bin/hdiutil", "detach", mount], log=workspace / "review-dmg-detach.log")
        require(not os.path.ismount(mount), "review_dmg_still_mounted")


REVIEW_NOTICE = ("Riftlet — local personal review only\n"
                 "This PREPARED App is not Developer ID signed or notarized.\n"
                 "This image is not a public distribution or an installer.\n"
                 "Do not disable Gatekeeper or remove quarantine to bypass a warning.\n"
                 "No App launch, installation, data migration or rollback is performed.\n"
                 "Preserve the installed App and its data; follow the reviewed handoff.\n").encode("utf-8")


def package_review(args):
    require(platform.system() == "Darwin", "macos_packaging_required", "BLOCKED_PLATFORM")
    require(hash_value(args.manifest_sha256), "trusted_manifest_pin_required")
    workspace, package = payload(args.workspace)
    value = verify_package(package, args.manifest_sha256)
    require(value["stage"] == "PREPARED", "review_package_requires_prepared_candidate")
    distribution = workspace / "review-distribution"
    require(not distribution.exists(), "review_distribution_already_exists")
    distribution.mkdir(mode=0o700)
    build = value["build"]
    arch = "universal" if len(build["architectures"]) == 2 else build["architectures"][0]
    stem = "Riftlet-REVIEW-NOT-NOTARIZED-" + build["version"] + "-" + build["build"] + "-" + arch
    archive = distribution / (stem + ".zip")
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", package, archive],
        log=workspace / "review-zip.log")
    archive_pin = verify_distribution_zip(archive, args.manifest_sha256, workspace)
    image_root = workspace / "review-image-source"
    require(not image_root.exists(), "review_image_source_already_exists")
    image_root.mkdir(mode=0o700)
    copy_distribution_tree("--rsrc", "--extattr", package, image_root / PAYLOAD,
                           log=workspace / "review-dmg-copy.log")
    verify_package(image_root / PAYLOAD, args.manifest_sha256)
    (image_root / "REVIEW-ONLY.txt").write_bytes(REVIEW_NOTICE)
    image = distribution / (stem + ".dmg")
    run(["/usr/bin/hdiutil", "create", "-format", "UDZO", "-fs", "HFS+", "-volname", "Riftlet Review",
         "-srcfolder", image_root, image], timeout=300, log=workspace / "review-dmg-create.log")
    verify_review_dmg(image, args.manifest_sha256, workspace)
    # Package preparation is a read-only operation on the candidate. A changed
    # source invalidates both containers, even if an earlier copy was intact.
    verify_package(package, args.manifest_sha256)
    require(digest(archive) == archive_pin, "archive_changed_after_verification")
    identity = {"schemaVersion": SCHEMA, "status": "REVIEW_ONLY", "recordedStage": "PREPARED",
                "manifestSHA256": args.manifest_sha256, "source": build["source"]["commit"],
                "version": build["version"], "build": build["build"],
                "versionLabel": build.get("versionLabel", "LEGACY_RECEIPT_NOT_RECORDED"),
                "architectures": build["architectures"], "packagerSHA256": digest(Path(__file__)),
                "artifacts": {"zip": {"name": archive.name, "sha256": archive_pin, "bytes": archive.stat().st_size},
                              "dmg": {"name": image.name, "sha256": digest(image), "bytes": image.stat().st_size}},
                "zipContents": "NATIVE_EXTRACTED_CONTENTS_MATCH", "dmgMountedContents": "MATCH_READ_ONLY_DETACHED",
                "reproducibility": "PINNED_INPUTS_AND_EXTRACTED_CONTENTS; NOT_BYTE_IDENTICAL_BUILD_OR_CONTAINER",
                "developerID": "NOT_SIGNED", "notarization": "NOT_NOTARIZED", "gatekeeper": "NOT_RUN",
                "installation": "NOT_RUN", "applicationLaunch": "NOT_RUN", "network": "NOT_USED",
                "dataCompatibility": "NOT_ASSERTED", "publicReleaseApproval": "NOT_GRANTED_BY_TOOL"}
    write_json(distribution / "review-artifacts.json", identity)
    return identity


def checked_zip_members(archive, root):
    """Check every path and type before native extraction, including metadata sidecars."""
    rows, names, links, total = {}, set(), set(), 0
    require(len(archive.infolist()) <= 20000, "too_many_archive_entries")
    for item in archive.infolist():
        p = PurePosixPath(item.filename)
        require(not p.is_absolute() and ".." not in p.parts and "\\" not in item.filename
                and p.parts and p.parts[0] in {root, "__MACOSX"}
                and item.filename == p.as_posix() + ("/" if item.is_dir() else "")
                and "\x00" not in item.filename, "unsafe_archive_path")
        canonical = p.as_posix().casefold()
        require(canonical not in names, "duplicate_archive_path")
        names.add(canonical)
        mode = item.external_attr >> 16
        require(not item.flag_bits & 1, "unsafe_archive_entry")
        if stat.S_ISLNK(mode):
            app_root = PurePosixPath(root, APP) if root == PAYLOAD else PurePosixPath(APP)
            target = SPARKLE.LINKS.get(p.relative_to(app_root).as_posix()) if p.is_relative_to(app_root) else None
            require(target is not None and item.file_size == len(target) and archive.read(item) == target.encode(),
                    "unsafe_archive_entry")
            links.add(canonical)
        else:
            require(stat.S_IFMT(mode) in {0, stat.S_IFREG, stat.S_IFDIR}, "unsafe_archive_entry")
        total += item.file_size
        require(total <= 2 * 1024**3, "archive_expansion_too_large")
        require(len(p.parts) != 1 or item.is_dir(), "archive_root_is_not_directory")
        if p.parts[0] == root:
            rows[p.as_posix()] = item
    # An archive cannot introduce files under any approved symlink alias.
    for name in names:
        require(not any(str(parent) in links for parent in PurePosixPath(name).parents), "archive_member_beneath_symlink")
    return rows


def extract_checked_zip(archive, root, destination):
    copy_distribution_tree("-x", "-k", "--rsrc", "--extattr", archive, destination)
    require({p.name for p in destination.iterdir()} == {root}, "extracted_archive_root_mismatch")


def verify_notary_upload(archive, value, workspace):
    archive_pin = digest(archive)
    expected = {name: row for name, row in value["files"].items()
                if name == APP or name.startswith(APP + "/")}
    with zipfile.ZipFile(archive) as contents:
        members = checked_zip_members(contents, APP)
        require(set(members) == set(expected), "notary_archive_app_entries_mismatch")
    with tempfile.TemporaryDirectory(prefix="notary-zip-check-", dir=workspace) as directory:
        extracted = Path(directory)
        extract_checked_zip(archive, APP, extracted)
        require(inventory(extracted) == expected, "notary_archive_app_inventory_mismatch")
    require(digest(archive) == archive_pin, "archive_changed_during_verification")
    return archive_pin


def verify_distribution_zip(archive, manifest_pin, workspace, team=None):
    # Structural verification is read-only. Only our packaging operation extracts
    # the new ZIP to verify what macOS actually restores, including stable xattrs.
    archive_pin = digest(archive)
    verify_archive(archive, archive_pin, manifest_pin)
    with tempfile.TemporaryDirectory(prefix="distribution-zip-check-", dir=workspace) as directory:
        extracted = Path(directory)
        extract_checked_zip(archive, PAYLOAD, extracted)
        verify_package(extracted / PAYLOAD, manifest_pin, native_team=team)
        if team:
            run(["xcrun", "stapler", "validate", "-v", extracted / PAYLOAD / APP],
                log=workspace / "distribution-zip-staple-validate.log")
    require(digest(archive) == archive_pin, "archive_changed_during_verification")
    return archive_pin


def verify_archive(path, expected_sha, expected_manifest=None):
    path = safe_path(path)
    require(path.is_file(), "archive_file_required")
    require(re.fullmatch(r"[0-9a-f]{64}", expected_sha or "") is not None, "trusted_archive_pin_required")
    require(digest(path) == expected_sha, "archive_pin_mismatch")
    with zipfile.ZipFile(path) as archive:
        members = checked_zip_members(archive, PAYLOAD)
        rows = {name[len(PAYLOAD) + 1:]: item for name, item in members.items() if name != PAYLOAD}
        require(MANIFEST in rows, "archive_manifest_missing")
        require(rows[MANIFEST].file_size <= 8 * 1024 * 1024, "oversized_json")
        manifest_bytes = archive.read(rows.pop(MANIFEST))
        if expected_manifest is not None:
            require(hash_value(expected_manifest), "trusted_manifest_pin_required")
            require(sha(manifest_bytes) == expected_manifest, "archive_manifest_pin_mismatch")
        manifest = decode_json(manifest_bytes)
        validate_manifest(manifest)
        require(set(rows) == set(manifest.get("files", {})), "archive_inventory_mismatch")
        require({PurePosixPath(name).parts[0] for name in rows} == {APP, "INSTALL-zh-CN.txt"}, "archive_payload_layout_mismatch")
        for name, item in rows.items():
            expected = manifest["files"][name]
            kind = "symlink" if stat.S_ISLNK(item.external_attr >> 16) else "directory" if item.is_dir() else "file"
            require(expected["kind"] == kind, "archive_entry_type_mismatch")
            require(stat.S_IMODE(item.external_attr >> 16) == expected["mode"], "archive_mode_mismatch")
            if kind == "symlink":
                require(archive.read(item) == expected["target"].encode(), "invalid_archive_link")
            if kind == "file":
                require(item.file_size == expected["size"] and sha(archive.read(item)) == expected["sha256"], "archive_file_mismatch")
        receipt = decode_json(archive.read(PAYLOAD + "/" + APP + "/" + RECEIPT))
        validate_receipt(receipt)
        require(receipt == manifest.get("build"), "archive_build_mismatch")
        plist_bytes = archive.read(PAYLOAD + "/" + APP + "/Contents/Info.plist")
        info = plistlib.loads(plist_bytes)
        validate_release_info(info, receipt)
        for language in receipt.get("permissionLanguages", []):
            name = APP + "/Contents/Resources/" + language + ".lproj/InfoPlist.strings"
            localized_permissions(archive.read(rows[name]) if name in rows else None, language, info)
        icon_name = APP + "/Contents/Resources/" + BUNDLE.ICON_NAME
        try:
            BUNDLE.verify_icon_data(info, archive.read(rows[icon_name]) if icon_name in rows else None)
        except BUNDLE.VerificationError as error:
            require(False, str(error))
        require(sha(plist_bytes) == receipt["infoPlistSHA256"], "archive_plist_receipt_mismatch")
        require(sha(archive.read(PAYLOAD + "/INSTALL-zh-CN.txt")) == receipt["preparationInputs"]["packaging/release/INSTALL-zh-CN.txt"], "archive_install_notes_mismatch")
        binary_name = APP + "/Contents/MacOS/Riftlet"
        require(rows[binary_name].external_attr >> 16 & stat.S_IXUSR, "archive_binary_not_executable")
        require(macho_arches(archive.read(PAYLOAD + "/" + binary_name)) == receipt["architectures"], "archive_arch_mismatch")
        require({name for name in rows if name.startswith(APP + "/Contents/MacOS/")} == {binary_name}, "archive_unexpected_executable")
        return {"status": "OFFLINE_ARCHIVE_IDENTITY_MATCH", "source": receipt["source"]["commit"],
                "manifestSHA256": sha(manifest_bytes),
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
    c.add_argument("--stable", action="store_true", help="Require version and build to match the product source")
    c.add_argument("--label", required=True, help="Explicit display label, e.g. Beta 3; never inherited from old source metadata")
    c.add_argument("--arch", action="append", choices=sorted(ARCHES.values()), required=True); c.add_argument("--workspace", type=Path, required=True)
    for command in ("sign", "notary-submit", "notary-status", "staple", "package"):
        c = commands.add_parser(command); c.add_argument("--workspace", type=Path, required=True)
        if command != "package": execute(c)
        if command == "sign": credentials(c, signing=True)
        if command.startswith("notary-"): credentials(c, notary=True)
        if command == "notary-status": c.add_argument("--submission-id")
    c = commands.add_parser("package-review"); c.add_argument("--workspace", type=Path, required=True)
    c.add_argument("--manifest-sha256", required=True, help="Trusted PREPARED manifest pin; produces local review ZIP/DMG only")
    c = commands.add_parser("verify"); c.add_argument("--package", type=Path, required=True)
    c.add_argument("--manifest-sha256"); c.add_argument("--team", help="Also perform offline native Developer ID validation on macOS")
    c = commands.add_parser("verify-archive"); c.add_argument("--archive", type=Path, required=True); c.add_argument("--sha256", required=True)
    c.add_argument("--manifest-sha256", help="Also bind the embedded manifest to an independently recorded candidate pin")
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
        elif args.command == "verify-archive": result = verify_archive(args.archive, args.sha256, args.manifest_sha256)
        else:
            result = {"preflight": preflight, "build": build_candidate, "sign": sign_candidate,
                      "notary-submit": notary_submit, "notary-status": notary_status,
                      "staple": staple_candidate, "package": package_candidate, "package-review": package_review,
                      "update-plan": update_plan}[args.command](args)
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
