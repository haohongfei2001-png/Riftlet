"""Build the fixed local QA probe from the frozen native sources in a private scratch package."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
FROZEN = "49b9204974088c1983cda469910d9a78d8f4c43b"
TRANSPORT_SHA = "00b1f7b637aad2ce00cc9b766c923ad5c4f25c3d0d08e8cf7306983ddb386140"
FIXTURE = Path("Tests/PreClickLease/g4/main-world-bootstrap/fixture.html")
PACKAGE = """// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LocalBootstrapAudit", platforms: [.macOS(.v13)], targets: [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
    .target(name: "RiftletCore", dependencies: ["CSQLite"]),
    .target(name: "RiftletAdapters", dependencies: ["RiftletCore"], resources: [.process("Resources")],
            swiftSettings: [.define("ORIGINAL_DRAFT_OBSERVER")]),
    .executableTarget(name: "LocalBootstrapAudit", dependencies: ["RiftletAdapters"])
])
"""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scratch", type=Path, help="A new, empty, private temporary directory.")
    args = parser.parse_args()
    scratch = args.scratch.resolve(strict=True)
    if (scratch.parent != Path("/private/tmp") or not scratch.name.startswith("riftlet61-owned-native-")
            or scratch.stat().st_mode & 0o077 or any(scratch.iterdir())):
        parser.error("An empty private riftlet61-owned-native-* directory in /private/tmp is required")
    os.umask(0o077)
    pkg = scratch / "package"
    pkg.mkdir()
    dirs = ["Sources/CSQLite", "Sources/RiftletCore", "Sources/RiftletAdapters"]
    archive = subprocess.check_output(["git", "archive", FROZEN, *dirs], cwd=REPO)
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        for entry in files:
            if entry.isdir():
                continue
            path = Path(entry.name)
            if not entry.isfile() or path.is_absolute() or ".." in path.parts:
                raise ValueError("Unexpected frozen-source entry")
            target = pkg / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(files.extractfile(entry).read())
    (pkg / "Package.swift").write_text(PACKAGE)
    adapter = pkg / dirs[-1]
    transport = adapter / "ChromeAppleEventsExecutor.swift"
    if digest(transport) != TRANSPORT_SHA:
        raise ValueError("Frozen native transport source changed")
    fixture = HERE / "fixture.html"
    for family in ("chrome", "edge"):
        file = scratch / family / FIXTURE
        file.parent.mkdir(parents=True)
        shutil.copyfile(fixture, file)
    config = ("\nenum PinnedLocalBootstrapFixture {\n"
              + "    static let work = " + json.dumps(str(scratch)) + "\n"
              + "    static let sha = " + json.dumps(digest(fixture)) + "\n}\n")
    # The native transport is file-private. Append the closed QA entry point in the
    # scratch module, preserving every byte of the original file as an audited prefix.
    with transport.open("ab") as out:
        out.write(config.encode())
        out.write((HERE / "NativeCheck.swift").read_bytes())
    for name in ("identity.swift", "owned.swift", "press.swift"):
        data = subprocess.check_output(
            ["git", "show", FROZEN + ":Tests/PreClickLease/native/" + name], cwd=REPO)
        (adapter / ("LocalQA_" + name)).write_bytes(data.replace(b"@testable import RiftletAdapters", b""))
    main_dir = pkg / "Sources/LocalBootstrapAudit"
    main_dir.mkdir()
    (main_dir / "Entry.swift").write_text(
        "import RiftletAdapters\nimport Darwin\n"
        "@main enum Entry { @MainActor static func main() { exit(OwnedNativeBootstrap.main()) } }\n")
    build = scratch / "build"
    cmd = ["xcrun", "swift", "build", "--package-path", str(pkg), "--scratch-path", str(build),
           "--cache-path", str(scratch / "cache"), "--config-path", str(scratch / "config"),
           "--security-path", str(scratch / "security"), "-j", "4", "--product", "LocalBootstrapAudit"]
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(scratch / "modules"))
    with (scratch / "build.log").open("wb") as log:
        subprocess.run(cmd, check=True, env=env, stdout=log, stderr=subprocess.STDOUT)
    matches = [p for p in build.rglob("LocalBootstrapAudit") if p.is_file() and os.access(p, os.X_OK)]
    if len(matches) != 1:
        raise ValueError("One QA executable required")
    exe = scratch / "local-bootstrap-audit"
    shutil.copy2(matches[0], exe)
    record = {"frozenCommit": FROZEN, "transportPrefixSHA256": TRANSPORT_SHA,
              "compiledSourceSHA256": digest(transport), "executableSHA256": digest(exe),
              "fixtureSHA256": digest(fixture), "runnerSHA256": digest(HERE / "NativeCheck.swift"),
              "builderSHA256": digest(Path(__file__))}
    (scratch / "build-manifest.json").write_text(json.dumps(record, sort_keys=True, indent=2) + "\n")
    print(json.dumps(record))


if __name__ == "__main__":
    main()
