import plistlib


def make_framework(app, sparkle):
    # Synthetic framework for structural tests. Native CI embeds the pinned
    # SwiftPM binary and launches the signed host's build-info entry point.
    for relative, (executable, identifier) in sparkle.CODE_PLISTS.items():
        path = app / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier, "CFBundleExecutable": executable,
                                         "CFBundleShortVersionString": sparkle.VERSION}))
    for relative in sparkle.EXECUTABLES:
        path = app / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\xcf\xfa\xed\xfeSYNTHETIC-NONEXECUTABLE-FIXTURE")
        path.chmod(0o755)
    for relative, target in sparkle.LINKS.items():
        path = app / relative
        if path.parent.name != "Versions":
            dest = app / sparkle.BASE / path.name
            if not dest.exists():
                dest.mkdir()
        path.symlink_to(target)
