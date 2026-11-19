"""Rebuild the layered camera key by drawing Riftlet's tagged AppKit implementation offscreen."""
import argparse
from pathlib import Path
import subprocess
import tempfile

TAG = "939e3af47ba18d4850311528130934c586cfcb76"
UI = "Sources/RiftletUI/"

def read_source(repo, filename):
    return subprocess.check_output(
        ["git", "-C", str(repo), "show", f"{TAG}:{UI}{filename}"], text=True
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        # The release surface keeps the actual drawing routine private. Isolate its
        # original declaration in a read-only build with the minimum support types.
        tray_source = read_source(args.repo, "RiftTraySurfaceView.swift")
        button, _ = tray_source.split("/// The original screenshot records", 1)
        button = button.replace("import RiftletCapture", "enum ScreenshotMode { case window, region, fullScreen }")
        glass_source = read_source(args.repo, "RiftTrayGlass.swift")
        palette = glass_source.split("@MainActor\nfinal class RiftTrayGlass", 1)[0]
        config = read_source(args.repo, "RiftConfiguration.swift")
        colors = config[config.index("enum RiftTrayColors:"):].split("\n}", 1)[0] + "\n}"
        driver = (Path(__file__).with_name("PlateDriver.swift")).read_text()
        unit = work / "Plate.swift"
        unit.write_text(button + "\n" + colors + "\n" + palette + "\n" + driver)
        runner = work / "plate"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(work / "modules"),
                        str(unit), "-o", str(runner)], check=True)
        subprocess.run([str(runner), str(args.directory.resolve() / "camera.png")], check=True)

if __name__ == "__main__":
    main()
