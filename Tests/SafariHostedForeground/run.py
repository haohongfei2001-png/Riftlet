"""Known local-only foreground check; no user agent override or public site."""
import http.server
import subprocess
import tempfile
import threading
from pathlib import Path

class Handler(http.server.BaseHTTPRequestHandler):
    hits = 0
    def do_GET(self):
        if self.path != "/riftlet-qa" or self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
            self.send_error(404)
            return
        content = b"<!doctype html><title>Riftlet owned QA window</title><textarea>QA DRAFT</textarea>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Content-Security-Policy", "default-src 'none'; form-action 'none'")
        self.end_headers()
        self.wfile.write(content)
        Handler.hits += 1

    def log_message(self, *_):
        pass

with tempfile.TemporaryDirectory(prefix="riftlet-host-qa-") as tmp:
    probe = Path(tmp) / "probe"
    subprocess.run(["sw_vers"], check=True, timeout=5)
    subprocess.run(["uname", "-m"], check=True, timeout=5)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R",
                    'anchor apple and identifier "com.apple.Safari"', "/Applications/Safari.app"],
                   check=True, timeout=15)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(Path(__file__).with_name("Probe.swift")),
                    "-o", str(probe)], check=True, timeout=60)
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        serving = threading.Thread(target=server.serve_forever, daemon=True)
        serving.start()
        try:
            subprocess.run([str(probe), f"http://127.0.0.1:{server.server_port}/riftlet-qa"],
                           check=True, timeout=40)
            if Handler.hits < 1:
                raise RuntimeError("Foreground window observed, but owned loopback load not confirmed")
            print("ownedLoopbackGET=PASS", flush=True)
        finally:
            server.shutdown()
            serving.join()
