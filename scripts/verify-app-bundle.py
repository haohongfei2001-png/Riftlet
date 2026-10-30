#!/usr/bin/env python3
"""Validate the development bundle layout; this is not a Gatekeeper assessment.

With --repository, also compare every shipped notice and adapter resource with
the source tree. No network, application launch or permission request occurs.
The build separately runs codesign --verify and packaged executable self-checks.
"""

import argparse
from pathlib import Path
import plistlib
import re
import stat
import sys
from xml.parsers.expat import ExpatError


class VerificationError(Exception):
    pass


RESOURCE_NAMES = ("chatgpt-web-20261027.js", "legacy-web-observe.js")
NOTICE_NAMES = (
    "Screenshoss/LICENSE", "Sukurini/LICENSE", "Sukurini/NOTICE", "Tendedero/LICENSE"
)
USAGE_KEYS = (
    "NSAppleEventsUsageDescription", "NSDesktopFolderUsageDescription",
    "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription",
)
# 64-bit Mach-O and universal containers. Actual architecture/loadability is
# verified by the native build and packaged executable self-check, not magic.
MACHO_MAGIC = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
               b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
               b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def require(condition, code):
    if not condition:
        raise VerificationError(code)


def read_nonempty(path, code):
    require(path.is_file() and not path.is_symlink(), code)
    try:
        data = path.read_bytes()
    except OSError as error:
        raise VerificationError(code) from error
    require(bool(data), code)
    return data


ORDINARY_ACCEPTANCE_OVERRIDES = {
    "CFBundleIdentifier": "com.riftlet.ordinary-acceptance",
    "CFBundleName": "Riftlet Ordinary Test",
    "CFBundleDisplayName": "Riftlet Ordinary Test",
    "RiftletBuildChannel": "ordinary-acceptance",
    "NSAppleEventsUsageDescription": "Riftlet Ordinary Test 是隔离的内部普通入口验收构建，仅在你点击后向已授权 Chrome 的当前受支持 ChatGPT 草稿附加系统截图，绝不自动发送消息。普通产品上传、安全重试与未决多附件并行仍未开放。",
}


def ordinary_acceptance_plist(source):
    return {**source, **ORDINARY_ACCEPTANCE_OVERRIDES}


def verify_ordinary_build_info(info, channel="ordinary-acceptance"):
    require(channel in {"development", "ordinary-acceptance"}, "invalid_expected_channel")
    internal = channel == "ordinary-acceptance"
    expected = {"internalAcceptance": internal, "mode": "capture",
                "dataDirectory": "Riftlet-Ordinary-Acceptance" if internal else "Riftlet", "input": internal,
                "start": internal, "completion": internal, "safeRetry": False, "continuation": False}
    require(isinstance(info, dict) and set(info) == set(expected), "invalid_ordinary_build_info")
    require(all(type(info[key]) is type(value) and info[key] == value for key, value in expected.items()),
            "invalid_ordinary_build_info")


def verify_bundle(app, repository=None, channel="development"):
    require(channel in {"development", "ordinary-acceptance"}, "invalid_expected_channel")
    app = Path(app)
    require(app.suffix == ".app" and app.is_dir() and not app.is_symlink(), "invalid_app_root")
    # Reject links and special files so a packaged dependency cannot escape the
    # bundle. No link is required by this deliberately small native application.
    for path in app.rglob("*"):
        info = path.lstat()
        require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode), "unsafe_bundle_entry")

    contents = app / "Contents"
    require(contents.is_dir(), "missing_contents")
    require(set(p.name for p in app.iterdir()) == {"Contents"}, "unexpected_bundle_root_entry")
    require(set(p.name for p in contents.iterdir()) <= {
        "Info.plist", "MacOS", "Resources", "_CodeSignature"
    }, "unexpected_contents_entry")
    try:
        info = plistlib.loads(read_nonempty(contents / "Info.plist", "missing_info_plist"))
    except (plistlib.InvalidFileException, ValueError, TypeError, ExpatError) as error:
        raise VerificationError("invalid_info_plist") from error
    require(isinstance(info, dict), "invalid_info_plist")
    exact_values = {
        "CFBundleExecutable": "Riftlet", "CFBundleIdentifier": "com.riftlet.app",
        "CFBundleName": "Riftlet", "CFBundleDisplayName": "Riftlet",
        "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "13.0",
        "LSApplicationCategoryType": "public.app-category.utilities",
        "RiftletBuildChannel": "development",
    }
    if channel == "ordinary-acceptance":
        exact_values.update(ORDINARY_ACCEPTANCE_OVERRIDES)
    for key, value in exact_values.items():
        require(info.get(key) == value, "invalid_" + key)
    for key, value in {"LSUIElement": True, "NSHighResolutionCapable": True,
                       "RiftletDeveloperIDSigned": False, "RiftletNotarized": False}.items():
        require(info.get(key) is value, "invalid_" + key)
    require(isinstance(info.get("CFBundleShortVersionString"), str) and
            re.fullmatch(r"\d+\.\d+\.\d+", info["CFBundleShortVersionString"]) is not None,
            "invalid_version")
    require(isinstance(info.get("CFBundleVersion"), str) and
            re.fullmatch(r"[1-9]\d*", info["CFBundleVersion"]) is not None, "invalid_build")
    for key in USAGE_KEYS:
        text = info.get(key)
        require(isinstance(text, str) and 10 <= len(text.strip()) <= 512, "invalid_" + key)

    binary = contents / "MacOS" / "Riftlet"
    executable = read_nonempty(binary, "missing_executable")
    require(executable[:4] in MACHO_MAGIC, "invalid_executable_format")
    require(bool(binary.stat().st_mode & stat.S_IXUSR), "executable_not_executable")
    require(set(p.name for p in binary.parent.iterdir()) == {"Riftlet"}, "unexpected_executable")

    resources = contents / "Resources"
    resource_bundle = resources / "Riftlet_RiftletAdapters.bundle"
    require(resource_bundle.is_dir(), "missing_adapter_bundle")
    packaged_resources = {}
    for name in RESOURCE_NAMES:
        matches = list(resource_bundle.rglob(name))
        require(len(matches) == 1 and matches[0].is_file(), "missing_or_ambiguous_" + name)
        # SwiftPM uses one of these two layouts, depending on the host platform.
        require(matches[0].relative_to(resource_bundle).as_posix() in {
            name, "Contents/Resources/" + name
        }, "misplaced_" + name)
        data = read_nonempty(matches[0], "empty_" + name)
        require(len(data) <= 128 * 1024, "oversized_" + name)
        try:
            data.decode("utf-8")
        except UnicodeError as error:
            raise VerificationError("invalid_utf8_" + name) from error
        packaged_resources[name] = data

    notices = resources / "ThirdPartyNotices"
    for name in NOTICE_NAMES:
        read_nonempty(notices / name, "missing_notice_" + name)

    if repository is not None:
        repository = Path(repository)
        source_plist = read_nonempty(repository / "Resources/Info.plist", "missing_source_plist")
        if channel == "ordinary-acceptance":
            # Only these fixed internal-channel substitutions are permitted.
            # Comparing the complete dictionary rejects added/removed keys too.
            require(info == ordinary_acceptance_plist(plistlib.loads(source_plist)), "plist_differs_from_source")
        else:
            require((contents / "Info.plist").read_bytes() == source_plist, "plist_differs_from_source")
        source_resources = repository / "Sources/RiftletAdapters/Resources"
        for name, data in packaged_resources.items():
            require(data == read_nonempty(source_resources / name, "missing_source_resource"),
                    "resource_differs_from_source_" + name)
        source_notices = repository / "ThirdPartyNotices"
        expected = {p.relative_to(source_notices).as_posix(): p.read_bytes()
                    for p in source_notices.rglob("*") if p.is_file()}
        actual = {p.relative_to(notices).as_posix(): p.read_bytes()
                  for p in notices.rglob("*") if p.is_file()}
        require(actual == expected, "notices_differ_from_source")
    return {"channel": channel, "version": info["CFBundleShortVersionString"],
            "minimum_macos": info["LSMinimumSystemVersion"],
            "developer_id_signed": False, "notarized": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--repository", type=Path)
    parser.add_argument("--channel", choices=("development", "ordinary-acceptance"), default="development")
    args = parser.parse_args()
    try:
        result = verify_bundle(args.app, args.repository, args.channel)
    except (VerificationError, OSError) as error:
        # Do not expose machine paths in CI artifacts or future diagnostics.
        code = str(error) if isinstance(error, VerificationError) else "bundle_io_error"
        print("RIFTLET_BUNDLE_CHECK_FAIL: " + code, file=sys.stderr)
        return 1
    print("RIFTLET_BUNDLE_CHECK_PASS: layout, permissions text, resources, notices; "
          + result["channel"] + " " + result["version"] + "; NOT_NOTARIZED; GATEKEEPER_NOT_RUN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
