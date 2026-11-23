#!/usr/bin/env python3
"""Build immutable production source plus a test-only AppKit/WKWebView transport."""

import argparse, difflib, hashlib, json, shutil, subprocess, tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def replace(s, a, b):
    if s.count(a) != 1:
        raise ValueError("source seam changed: " + a)
    return s.replace(a, b)


def body(s, signature, repl):
    start = s.index(signature)
    opening = s.index("{", start)
    end = s.index("\n    }", opening)
    return s[: opening + 1] + "\n        " + repl + s[end:]


def build(src, out, sparkle):
    out.mkdir(mode=0o700, parents=True, exist_ok=True)
    work = out / "source"
    if not work.exists():
        work.mkdir()
        ar = out / "source.tar"
        if src == "working":
            tracked = (
                subprocess.check_output(
                    [
                        "git",
                        "-C",
                        str(REPO),
                        "ls-files",
                        "-z",
                        "Sources",
                        "Package.swift",
                        "Package.resolved",
                    ]
                )
                .decode()
                .split("\0")
            )
            with tarfile.open(ar, "w") as t:
                for name in filter(None, tracked):
                    t.add(REPO / name, arcname=name, recursive=False)
        else:
            with ar.open("wb") as f:
                subprocess.run(
                    [
                        "git",
                        "-C",
                        str(REPO),
                        "archive",
                        src,
                        "Sources",
                        "Package.swift",
                        "Package.resolved",
                    ],
                    stdout=f,
                    check=True,
                )
        with tarfile.open(ar) as t:
            t.extractall(work, filter="data")
    else:
        if (out / "requested-source").read_text() != src:
            raise RuntimeError("new source requires a new directory")
        subprocess.run(
            ["tar", "xf", str(out / "source.tar"), "-C", str(work)], check=True
        )
    (out / "requested-source").write_text(src)
    fx = work / "Tests/ProductRecoveryAcceptance/Fixture"
    shutil.copytree(HERE / "Fixture", fx, dirs_exist_ok=True)
    if not (out / "page/index.html").exists():
        subprocess.run(["node", str(fx / "bridge.cjs"), str(out / "page")], check=True)
    raw = (work / "Sources/RiftletApp/RiftletMain.swift").read_text()
    main = replace(
        raw,
        "FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!",
        "FixtureMailbox.privateSupport",
    )
    main = replace(
        main,
        'qaOriginalTab = try QAOriginalBrowserTab.decode(ProcessInfo.processInfo.environment["RIFTLET_QA_NATIVE_ROUTE"])',
        'precondition(FixtureMailbox.native["sessionID"] is String)',
    )
    a = main.index("let chromeExecutor = mode.usesWebAdapter ?")
    b = main.index("let composition =", a)
    main = (
        main[:a]
        + "let chromeExecutor: FixtureExecutor? = FixtureExecutor(owner: owner.preparationOwner)\n        "
        + main[b:]
    )
    a = main.index("            // Process identity only, not permission")
    b = main.index("            prepareBrowser()", a)
    main = main[:a] + main[b:]
    main = body(
        main,
        "private func prepareBrowser(invalidate:",
        "guard !terminating && !userHidden else { return }\n        clickAdapter?.prepareForUpcomingClick(invalidate: invalidate, maintain: arriving || !visibleIDs.isEmpty)",
    )
    main = body(
        main, "private func inspectAutomationPermission(reason:", "return .granted"
    )
    main = body(
        main,
        "private func accessToOriginalReceiver(",
        'guard !terminating, target.sessionID == FixtureMailbox.native["sessionID"] as? String else { return .unavailable }; return .granted',
    )
    main = replace(
        main,
        "        initialized = true",
        """        initialized = true
        FixtureUI.shared.start(binding: { [weak chromeExecutor] in chromeExecutor?.preparedBinding }, approach: { [weak self] in self?.prepareBrowser(invalidate: true) }) { [weak self] in
            self?.statusItem?.button?.performClick(nil)
        }""",
    )
    p = work / "Sources/RiftletApp/RiftletMain.swift"
    p.write_text(main)
    (out / "composition.diff").write_text(
        "".join(
            difflib.unified_diff(
                raw.splitlines(True),
                main.splitlines(True),
                fromfile="frozen/RiftletMain.swift",
                tofile="controlled/RiftletMain.swift",
            )
        )
    )
    for f in ["FixtureExecutor.swift", "FixtureUI.swift"]:
        shutil.copy2(HERE / f, p.parent / f)
    pkg = (work / "Package.swift").read_text()
    pkg = replace(
        pkg,
        '.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")',
        "",
    )
    pkg = replace(pkg, '.product(name: "Sparkle", package: "Sparkle")', '"Sparkle"')
    pkg = replace(
        pkg,
        "targets: [\n        .systemLibrary",
        'targets: [\n        .binaryTarget(name:"Sparkle",path:"Sparkle.xcframework"),\n        .systemLibrary',
    )
    if not (work / "Sparkle.xcframework").exists():
        shutil.copytree(sparkle, work / "Sparkle.xcframework", symlinks=True)
    for name in [
        "RiftletFeedbackTests",
        "RiftletFeedbackUITests",
        "RiftletCoreTests",
        "RiftletCaptureTests",
        "RiftletUITests",
        "RiftletAppTests",
        "RiftletAdaptersTests",
    ]:
        t = work / "Tests" / name
        t.mkdir(exist_ok=True)
        (t / "Empty.swift").touch()
    (work / "Tests/RiftletAdaptersTests/Fixtures").mkdir(exist_ok=True)
    (work / "Package.swift").write_text(pkg)
    subprocess.run(
        [
            "swiftc",
            "-swift-version",
            "5",
            str(HERE / "PageHost.swift"),
            "-o",
            str(out / "page-host"),
        ],
        check=True,
    )
    subprocess.run(
        [
            "swift",
            "build",
            "--package-path",
            str(work),
            "--jobs",
            "6",
            "--product",
            "Riftlet",
        ],
        check=True,
    )
    exe = (work / ".build/debug/Riftlet").resolve()
    print(exe)
    files = [
        out / "source.tar",
        exe,
        out / "page-host",
        out / "composition.diff",
        out / "page/shipping-adapter.js",
        work / "Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js",
        HERE / "FixtureExecutor.swift",
        HERE / "FixtureUI.swift",
        HERE / "PageHost.swift",
        HERE / "build.py",
    ]
    (out / "manifest.json").write_text(
        json.dumps(
            {
                "source": src,
                "literalSignedPackage": False,
                "product": str(exe),
                "sha256": {str(x): sha(x) for x in files},
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("source")
    a.add_argument("out", type=Path)
    a.add_argument(
        "--sparkle",
        type=Path,
        required=True,
    )
    v = a.parse_args()
    build(v.source, v.out, v.sparkle)
