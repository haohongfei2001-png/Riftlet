"""Package the design deliverable, never product source or user data."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parent
EXPORT = ROOT / "exports"
MANIFEST = ROOT / "DELIVERY_MANIFEST.json"
EXPORT.mkdir(exist_ok=True)

def included(path):
    relative = path.relative_to(ROOT)
    return path.is_file() and path != MANIFEST and not any(
        part in {"exports", "dist", ".openai", "__pycache__"} for part in relative.parts
    ) and not path.name.endswith((".partial.mp4", ".pyc"))

files = sorted(path for path in ROOT.rglob("*") if included(path))
entries = [{"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size,
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
data = {"scope": "Riftlet design simulation and implementation specification",
        "base": "1920e0562db893a3292af89a89270a26ddb46a5f",
        "entry": "START-HERE.html", "standalonePrototype": "Riftlet-Product-Prototype.html",
        "nativeSourcesIncluded": False, "manifestExcludesItself": True,
        "fileCountExcludingManifest": len(files), "files": entries}
MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
package = EXPORT / "Riftlet-Quiet-Edge-Design.zip"
with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for p in files + [MANIFEST]:
        info = zipfile.ZipInfo("Riftlet-Quiet-Edge/" + str(p.relative_to(ROOT)), (2026, 10, 28, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, p.read_bytes())
with zipfile.ZipFile(package) as archive:
    assert archive.testzip() is None
    assert len(archive.infolist()) == len(files) + 1
digest = hashlib.sha256(package.read_bytes()).hexdigest()
(EXPORT / "SHA256SUMS.txt").write_text(digest + "  " + package.name + "\n")
print(json.dumps({"file": str(package), "bytes": package.stat().st_size,
                  "sha256": digest, "entries": len(files) + 1}, indent=2))
