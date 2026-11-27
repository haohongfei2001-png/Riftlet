#!/usr/bin/env python3
"""Loopback-only Safari drag receiver. This is not a signed-app or site check."""
import argparse
import hashlib
import http.client
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import struct
import subprocess
import sys
from threading import Thread
import zlib

DMG_SHA256 = "9f654539619b87ead785828e83cde631896089abc055602bed805588544511f1"

def image_fixture():
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data)))
    rows = b"".join(b"\x00" + b"\x0a\xa4\x99" * 8 + b"\xd9\x85\x28" * 8 for _ in range(16))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))

SCRIPT = """
'use strict';
const editor = document.getElementById('original');
const draft = editor.value;
const receiver = document.getElementById('receiver');
const output = document.getElementById('result');
let drops = 0, sends = 0, inputs = 0, changes = 0, submits = 0;
function paint(extra = {}) {
  output.textContent = JSON.stringify({drops, sends, inputs, changes, submits,
    sameDraft: editor.isConnected && editor === document.getElementById('original') && editor.value === draft,
    ...extra}, null, 2);
}
document.addEventListener('submit', e => { e.preventDefault(); submits++; paint(); });
editor.addEventListener('input', () => { inputs++; paint(); });
editor.addEventListener('change', () => { changes++; paint(); });
document.getElementById('send').addEventListener('click', () => { sends++; paint(); });
receiver.addEventListener('dragover', e => e.preventDefault());
receiver.addEventListener('drop', async e => {
  e.preventDefault(); drops++;
  const files = Array.from(e.dataTransfer.files);
  if (files.length !== 1 || files[0].size > 2 * 1024 * 1024) { paint({fileCount: files.length, rejected: true}); return; }
  try {
    const file = files[0];
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', await file.arrayBuffer()));
    const sha256 = Array.from(digest, b => b.toString(16).padStart(2, '0')).join('');
    const card = document.getElementById('card');
    card.textContent = file.name;
    paint({fileCount: 1, fileName: file.name, sha256, matchesFixture: sha256 === EXPECTED});
  } catch (_) { paint({rejected: true, reason: 'digestUnavailable'}); }
});
paint();
""".strip()
# No production browser or Riftlet admission checks are disabled. No website
# requests, forms, upload destinations, third-party scripts, or account data.
INDEX = b"""<!doctype html><meta charset=utf-8><title>Riftlet Safari local fixture</title>
<h1>Riftlet Safari local fixture</h1><form><label>Original draft
<textarea id=original>RIFTLET LOCAL QA DRAFT</textarea></label>
<button id=send type=submit>Send (local counter only)</button></form>
<p id=receiver style="border:2px solid #888;padding:36px">Drop one synthetic QA image here</p>
<div id=card></div><pre id=result></pre><script src=/fixture.js></script>
"""

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
            self.send_error(400)
            return
        payload = {
            "/": ("text/html; charset=utf-8", INDEX),
            "/fixture.js": ("application/javascript; charset=utf-8",
                ("const EXPECTED = " + json.dumps(self.server.expected_sha)
                 + ";\n" + SCRIPT).encode()),
        }.get(self.path)
        if payload is None:
            self.send_error(404)
            return
        mime, data = payload
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy",
            "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        # Never record request contents, paths, or account information.
        pass

def server(expected_sha=None):
    instance = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    instance.expected_sha = expected_sha or hashlib.sha256(image_fixture()).hexdigest()
    return instance

def self_test():
    fixture = image_fixture()
    assert fixture.startswith(b"\x89PNG\r\n\x1a\n") and len(fixture) < 4096
    with server() as s:
        thread = Thread(target=s.serve_forever, daemon=True)
        thread.start()
        c = http.client.HTTPConnection("127.0.0.1", s.server_port, timeout=4)
        try:
            c.request("GET", "/")
            r = c.getresponse()
            assert r.status == 200 and b'id=receiver' in r.read()
            assert "form-action 'none'" in r.getheader("Content-Security-Policy")
            c.request("GET", "/fixture.js")
            r = c.getresponse()
            assert r.status == 200 and hashlib.sha256(fixture).hexdigest().encode() in r.read()
            c.request("GET", "/", headers={"Host": "localhost.invalid"})
            r = c.getresponse()
            assert r.status == 400
            r.read()
            c.request("POST", "/")
            assert c.getresponse().status == 501
        finally:
            c.close()
            s.shutdown()
            thread.join()
    print(json.dumps({"status": "PASS", "scope": "LOOPBACK_HTTP_AND_SEED_ONLY",
          "signedMacOSSetup": "NOT_RUN", "signedSafariNativeDrag": "NOT_RUN", "liveWebsiteClick": "NOT_RUN"}))

def preflight(dmg):
    receipt = {"signedMacOSSetup": "NOT_RUN", "signedSafariNativeDrag": "NOT_RUN", "liveWebsiteClick": "NOT_RUN"}
    if sys.platform != "darwin":
        receipt.update(status="BLOCKED_ENV", blocker="macOS_REQUIRED")
    elif dmg is None or not dmg.is_file():
        receipt.update(status="BLOCKED_ENV", blocker="EXACT_SIGNED_DMG_REQUIRED")
    else:
        with dmg.open("rb") as handle:
            sha = hashlib.file_digest(handle, "sha256").hexdigest()
        receipt["dmgSHA256"] = sha
        if sha != DMG_SHA256:
            receipt.update(status="BLOCKED_ENV", blocker="EXACT_SIGNED_DMG_REQUIRED")
        else:
            try:
                result = subprocess.run(["/usr/bin/xcrun", "swift", "-e",
                    "import AppKit; guard !NSScreen.screens.isEmpty else { fatalError() }; print(\"DISPLAY_PRESENT\")"],
                    capture_output=True, timeout=30, check=True, text=True)
                display = result.stdout.strip() == "DISPLAY_PRESENT"
            except (OSError, subprocess.SubprocessError):
                display = False
            receipt.update(status="READY_FOR_INTERACTIVE_SETUP" if display else "BLOCKED_ENV",
                           blocker=None if display else "DISPLAY_OR_SWIFT_UNAVAILABLE")
            receipt["displayPresent"] = display
            receipt["interactiveSettingsAndAutomationConsentVerified"] = False
    print(json.dumps(receipt))
    return 2 if receipt["status"] == "BLOCKED_ENV" else 0

def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--preflight", action="store_true")
    modes.add_argument("--serve", type=Path, metavar="ISOLATED_QA_PNG")
    modes.add_argument("--receive", metavar="EXACT_SYNTHETIC_SCREENSHOT_SHA256")
    parser.add_argument("--dmg", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.preflight:
        return preflight(args.dmg)
    else:
        digest = args.receive
        if digest is not None and not re.fullmatch(r"[a-f0-9]{64}", digest):
            parser.error("--receive requires a lowercase SHA-256 digest")
        if args.serve is not None:
            with args.serve.open("xb") as out:
                out.write(image_fixture())
        with server(digest) as s:
            print(f"http://127.0.0.1:{s.server_port}/", flush=True)
            print(f"Fixture SHA-256: {s.expected_sha}", flush=True)
            s.serve_forever()
    return 0

if __name__ == "__main__":
    sys.exit(main())
