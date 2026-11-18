"""Fingerprint same-size canvas serialization of explicitly selected, hash-pinned PNGs.

This offline probe runs a fresh headless browser with private fixtures. It reads
no profile, HAR or site state. Compare output digests with separately obtained
original-card digests. Matching wire length alone does not establish identity.
"""
import argparse
import base64
import hashlib
import http.server
import queue
import secrets
import threading
import json
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import tempfile

PNG = b"\x89PNG\r\n\x1a\n"
MAX_BYTES = 8 * 1024 * 1024
MAX_PIXELS = 4096 * 1024
MAX_FILES = 4
HERE = Path(__file__).resolve().parent
OBSERVER = HERE.parents[1] / "Sources/RiftletAdapters/Resources/edge-encoded-preview.js"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_source(path, expected):
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or not 0 < path.stat().st_size <= MAX_BYTES:
        raise ValueError("invalid source size or expected SHA-256")
    data = path.read_bytes()
    if digest(data) != expected:
        raise ValueError("source digest mismatch")
    if len(data) < 33 or data[:16] != PNG + b"\0\0\0\rIHDR":
        raise ValueError("invalid PNG header")
    width, height = struct.unpack(">II", data[16:24])
    if not width or not height or width * height > MAX_PIXELS:
        raise ValueError("source dimensions outside probe budget")
    return data, width, height


def probe(browser, sources, software=False):
    if not 1 <= len(sources) <= MAX_FILES or len({sha for sha, _ in sources}) != len(sources):
        raise ValueError("expected one to four distinct hash-pinned PNGs")
    originals = [read_source(Path(path), expected) for expected, path in sources]
    with tempfile.TemporaryDirectory(prefix="riftlet-canvas-fingerprint-") as tmp:
        folder = Path(tmp)
        script = folder / "canvas.js"
        # Scope identity is a fixture. Browser File/Bitmap/Canvas/DOM and crypto are real.
        observer = OBSERVER.read_text()
        script.write_text("const watchProbe = (function(location, navigation) {return (\n" + observer
                          + "\n);})({href:'https://chatgpt.com/?temporary-chat=true'},"
                          + "{currentEntry:{id:'isolated-fixture'}});\n"
                          + (HERE / "edge_png_roundtrip.js").read_text())
        # Keep original bytes in the private fixture, never in results or logs.
        inputs = "".join("document.write('<img src=\"data:image/png;base64,"
                         + base64.b64encode(data).decode("ascii") + "\">');\n" for data, _, _ in originals)
        (folder / "inputs.js").write_text(inputs)
        page = folder / "probe.html"
        page.write_text("""<!doctype html><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; img-src data:; connect-src 'self'; base-uri 'none'; form-action 'none'">
<script src="canvas.js"></script><script src="inputs.js"></script>""")
        token = "/" + secrets.token_hex(24) + "/"
        results = queue.Queue(maxsize=1)
        served = set()
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                allowed = {token+f.name: f for f in (page, script, folder / "inputs.js")}
                if self.path not in allowed:
                    self.send_error(404)
                    return
                path = allowed[self.path]
                served.add(path.name)
                body = path.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html" if path == page else "text/javascript")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                size = int(self.headers.get("Content-Length", "-1"))
                if self.path != token+"result" or not 0 < size <= 32768:
                    self.send_error(400)
                    return
                data = self.rfile.read(size)
                if not results.full():
                    results.put_nowait(data)
                self.send_response(204)
                self.end_headers()

        with http.server.ThreadingHTTPServer(("127.0.0.1",0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            url = f"http://127.0.0.1:{server.server_port}{token}{page.name}"
            command = [str(browser), "--headless", "--disable-renderer-backgrounding", "--disable-background-timer-throttling", "--disable-extensions",
                       "--disable-background-networking", "--disable-component-update",
                       "--disable-sync", "--no-first-run", "--no-default-browser-check",
                       "--disable-features=msEdgeFirstRunExperience", "--no-proxy-server",
                       "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1", "--user-data-dir=" + str(folder / "profile"), url]
            if software:
                command.insert(2, "--disable-gpu")
            process = None
            try:
                process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                           start_new_session=True)
                samples = json.loads(results.get(timeout=25))
            except queue.Empty:
                raise RuntimeError("isolated renderer timed out, served: " + str(sorted(served))) from None
            finally:
                if process is not None and process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=4)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=4)
                server.shutdown()
                thread.join(timeout=2)
    if isinstance(samples, dict):
        raise RuntimeError("renderer error: "+str(samples.get("error")))
    if len(samples) != len(originals):
        raise ValueError("missing source image result")
    output = []
    for sample, (data, width, height) in zip(samples, originals):
        if (sample["width"], sample["height"]) != (width, height):
            raise ValueError("rendered dimensions changed")
        variants = sample["variants"]
        if len(variants) != 12 or any(
            len(v) != 3 or type(v[0]) is not int or not 0 < v[0] <= MAX_BYTES * 2 or
            not all(re.fullmatch("[a-f0-9]{64}", h) for h in v[1:]) for v in variants.values()
        ):
            raise ValueError("incomplete renderer output")
        if sample["checks"] != {"samePNG":"matched", "samePixelsDifferentPNG":"mismatch"}:
            raise ValueError("real browser witness controls failed")
        output.append(dict(sourceSHA256=digest(data), sourceBytes=len(data), width=width, height=height,
                           encodings=variants, productObserver=sample["checks"]))
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", type=Path, required=True, help="installed Chromium-family executable")
    parser.add_argument("--source", nargs=2, action="append", metavar=("SHA256", "PNG"), required=True)
    parser.add_argument("--software", action="store_true", help="disable GPU acceleration in this probe")
    args = parser.parse_args()
    print(json.dumps(probe(args.browser.resolve(strict=True), args.source, args.software), indent=2))
