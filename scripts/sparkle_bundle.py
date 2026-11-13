"""Layout and identities of the Sparkle distribution pinned by Package.resolved."""
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
import plistlib
import shutil
import stat
import sys

VERSION = "2.10.1"
REVISION = "ab7d71291238df6e0492143b120c9b696a35f603"
URL = "https://github.com/sparkle-project/Sparkle.git"
# Path, entry type and content of the macOS framework from the SwiftPM artifact.
# The upstream ZIP SHA-256 is 4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a.
FRAMEWORK_DIGEST = "98935f330f94a80826b9a7cfc00a55b480a6d47bf93d82a18da6eff2cba12c20"
FRAMEWORK = "Contents/Frameworks/Sparkle.framework"
BASE = FRAMEWORK + "/Versions/B/"
LINKS = {FRAMEWORK + "/" + name: "Versions/Current/" + name for name in (
    "Autoupdate", "Headers", "Modules", "PrivateHeaders", "Resources", "Sparkle", "Updater.app", "XPCServices")}
LINKS[FRAMEWORK + "/Versions/Current"] = "B"
# Sign children before their enclosing bundles. No global recursion or inherited
# host entitlements. The upstream Downloader for this exact revision has no entitlements.
COMPONENTS = (
    (BASE + "XPCServices/Installer.xpc", "Contents/MacOS/Installer", "org.sparkle-project.InstallerLauncher"),
    (BASE + "XPCServices/Downloader.xpc", "Contents/MacOS/Downloader", "org.sparkle-project.DownloaderService"),
    (BASE + "Autoupdate", "", "org.sparkle-project.Sparkle.Autoupdate"),
    (BASE + "Updater.app", "Contents/MacOS/Updater", "org.sparkle-project.Sparkle.Updater"),
    (FRAMEWORK, "Versions/B/Sparkle", "org.sparkle-project.Sparkle"),
)
EXECUTABLES = {(component + "/" + binary if binary else component)
               for component, binary, _ in COMPONENTS}
CODE_PLISTS = {(FRAMEWORK + "/Versions/B/Resources/Info.plist" if path == FRAMEWORK
                else path + "/Contents/Info.plist"): (Path(binary).name, identifier)
               for path, binary, identifier in COMPONENTS if binary}


def validate_layout(app, require):
    folder = app / FRAMEWORK
    require(folder.is_dir() and not folder.is_symlink(), "missing_sparkle_framework")
    require({p.name for p in folder.parent.iterdir()} == {"Sparkle.framework"}, "unexpected_framework")
    for name, target in LINKS.items():
        link = app / name
        require(link.is_symlink() and os.readlink(link) == target and link.exists(), "invalid_sparkle_link")
    for name in EXECUTABLES:
        binary = app / name
        require(binary.is_file() and not binary.is_symlink() and binary.stat().st_mode & 0o111,
                "missing_sparkle_executable")
    for name, (binary, identifier) in CODE_PLISTS.items():
        path = app / name
        require(path.is_file() and not path.is_symlink(), "missing_sparkle_info")
        info = plistlib.loads(path.read_bytes())
        require(info.get("CFBundleIdentifier") == identifier and info.get("CFBundleExecutable") == binary
                and info.get("CFBundleShortVersionString") == VERSION, "wrong_sparkle_component_identity")


def require_exact_dependency(dependencies, lock):
    try:
        (entry,) = dependencies
        (package,) = entry["sourceControl"]
        (remote,) = package["location"]["remote"]
        (pin,) = lock["pins"]
        valid = (package["identity"] == "sparkle" and remote["urlString"] == URL
                 and package["requirement"] == {"exact": [VERSION]} and pin == {
                     "identity": "sparkle", "kind": "remoteSourceControl", "location": URL,
                     "state": {"revision": REVISION, "version": VERSION}})
    except (KeyError, TypeError, ValueError):
        valid = False
    if not valid:
        raise ValueError("unexpected_release_dependency")


def fix_host_runpaths(app, arches):
    """Discard SwiftPM's build-only search paths before signing the relocatable App."""
    binary = app / "Contents/MacOS/Riftlet"
    framework = "@rpath/Sparkle.framework/Versions/B/Sparkle"
    allowed = {"@executable_path/../Frameworks", "/usr/lib/swift"}
    def paths(arch):
        commands = subprocess.check_output(["/usr/bin/otool", "-arch", arch, "-l", binary], text=True)
        return set(re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset", commands))
    extra = set()
    for arch in arches:
        linked = subprocess.check_output(["/usr/bin/otool", "-arch", arch, "-L", binary], text=True)
        if not any(line.strip().startswith(framework + " (") for line in linked.splitlines()):
            raise ValueError("sparkle_not_linked")
        runpaths = paths(arch)
        if "@executable_path/../Frameworks" not in runpaths:
            raise ValueError("missing_embedded_framework_runpath")
        extra.update(runpaths - allowed)
    if extra:
        args = [arg for path in sorted(extra) for arg in ("-delete_rpath", path)]
        subprocess.run(["/usr/bin/install_name_tool", *args, binary], check=True)
        for arch in arches:
            if paths(arch) - allowed:
                raise ValueError("unexpected_packaged_runpath")
        # arm64 requires a valid code signature for the pre-sign identity check.
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", binary], check=True)


def framework_digest(source):
    rows = []
    for path in sorted(source.rglob("*")):
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            kind, value = "symlink", os.readlink(path)
        elif stat.S_ISDIR(mode):
            kind, value = "directory", ""
        elif stat.S_ISREG(mode):
            kind, value = "file", hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            raise ValueError("unexpected_sparkle_entry")
        rows.append([path.relative_to(source).as_posix(), kind, value])
    return hashlib.sha256(json.dumps(rows, separators=(",", ":")).encode()).hexdigest()


def verify_upstream(source):
    if framework_digest(source) != FRAMEWORK_DIGEST:
        raise ValueError("sparkle_framework_content_mismatch")


def embed(scratch, app):
    source = scratch / "artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    verify_upstream(source)
    target = app / FRAMEWORK
    target.parent.mkdir()
    shutil.copytree(source, target, symlinks=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: sparkle_bundle.py SWIFTPM_SCRATCH APP")
    app = Path(sys.argv[2])
    embed(Path(sys.argv[1]), app)
    arches = subprocess.check_output(["/usr/bin/lipo", "-archs", app / "Contents/MacOS/Riftlet"], text=True).split()
    fix_host_runpaths(app, arches)
