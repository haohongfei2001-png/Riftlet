#!/usr/bin/env python3
"""Isolated local Edge (no extensions, driver, debugger, account, external URLs or prompts)."""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import secrets
import signal
import struct
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
import zlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
APP = Path('/Applications/Microsoft Edge.app')
NATIVE_SOURCES = ['ApplicationHostAdapter.swift', 'ChromeActiveTabDescriptor.swift', 'ChromeProcessIdentity.swift', 'EdgeApplicationHost.swift', 'EdgeJavaScriptEvent.swift']


def png(rgb):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    header = struct.pack('!IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(b'\0' + rgb)) + chunk(b'IEND', b'')


def dictionary_check():
    xml = ET.parse(APP / 'Contents/Resources/scripting.sdef')
    win = xml.find(".//class[@code='cwin']")
    tab = xml.find(".//class[@code='CrTb']")
    assert win is not None and tab is not None
    assert win.find("property[@code='ID  '][@type='text']") is not None
    assert win.find("property[@code='acTa'][@type='tab']") is not None
    assert tab.find("property[@code='ID  '][@type='text']") is not None
    assert tab.find("property[@code='URL '][@type='text']") is not None
    assert xml.find(".//command[@code='CrSuExJa']/parameter[@code='JvSc'][@type='text']") is not None


def run(mode, gui):
    if not APP.is_dir():
        print('NOT_RUN_EDGE_NOT_INSTALLED')
        return 77
    dictionary_check()
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.microsoft.edgemac'
    print('EDGE_DICTIONARY_MATCH', info['CFBundleShortVersionString'], flush=True)
    draft = secrets.token_hex(16)
    ids = [secrets.token_hex(16) for _ in range(6)]
    images = {ids[0]: png(b'\x80\x00\x00'), ids[1]: png(b'\x00\x80\x00')}
    page_config = {'images': [{'operation': op, 'bytes': base64.b64encode(value).decode()} for op, value in images.items()],
                   'changed': ids[2], 'duplicate': ids[3], 'rejected': ids[4], 'uncertain': ids[5]}
    expected = dict(images)
    if mode == 'headless':
        expected.update({ids[4]: images[ids[1]], ids[5]: images[ids[1]]})
    received, invalid = [], []
    summary = []
    loaded, done = threading.Event(), threading.Event()
    lock = threading.Lock()
    runner = ''
    if mode == 'headless':
        body = (HERE / 'fixture-command.js').read_text() + '\n' + (HERE / 'headless.js').read_text().replace('__CONFIG__', json.dumps(page_config))
        runner = '<script>' + body + '</script>'
    html = (HERE / 'fixture.html').read_text().replace('<!--RUNNER-->', runner).encode()

    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # Never record URLs, tokens, images or process paths.
        def reply(self, status, data=b'', mime='text/plain'):
            self.send_response(status)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)
        def do_GET(self):
            if self.path != '/draft/' + draft:
                self.reply(404)
                return
            self.reply(200, html, 'text/html; charset=utf-8')
            loaded.set()
        def do_POST(self):
            count = int(self.headers.get('Content-Length', '0'))
            if count <= 0 or count > 1024:
                self.reply(400)
                return
            body = self.rfile.read(count)
            if self.path == '/proof/' + draft:
                summary.append(body == b'RIFTLET_EDGE_FIXTURE_COMPLETE')
                self.reply(200)
                done.set()
                return
            operation = self.path.split('/')[-1]
            with lock:
                if self.path != f'/upload/{draft}/{operation}' or expected.get(operation) != body or operation in received:
                    invalid.append(True)
                    self.reply(400)
                    return
                # Bytes arrived at the independent receiver before it issues its final reply.
                received.append(operation)
            time.sleep(0.08)
            if operation == ids[5]:
                self.close_connection = True
                return  # Exact body at receiver, zero acknowledgement at client.
            self.reply(422 if operation == ids[4] else 201, operation.encode())

    with ThreadingHTTPServer(('127.0.0.1', 0), Fixture) as server, tempfile.TemporaryDirectory(prefix='riftlet-edge-fixture-') as temp:
        url = f'http://127.0.0.1:{server.server_port}/draft/{draft}'
        threading.Thread(target=server.serve_forever, daemon=True).start()
        directory = Path(temp)
        executable = directory / 'native'
        if mode == 'apple-events':
            cmd = ['swiftc', '-module-cache-path', str(directory / 'modules')]
            cmd.extend(str(ROOT / 'Sources/RiftletAdapters' / name) for name in NATIVE_SOURCES)
            subprocess.run(cmd + [HERE / 'main.swift', '-o', executable], check=True)
        binary = APP / 'Contents/MacOS' / info['CFBundleExecutable']
        args = [str(binary), '--user-data-dir=' + str(directory / 'profile'), '--disable-extensions', '--no-first-run',
                '--no-default-browser-check', '--disable-background-networking', '--disable-sync', '--no-proxy-server',
                '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1']
        if not gui:
            args.append('--headless=new')
        process = subprocess.Popen(args + [url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            deadline = time.monotonic() + 15
            while not loaded.wait(0.1) and process.poll() is None and time.monotonic() < deadline:
                pass
            if not loaded.is_set():
                print('EDGE_FIXTURE_DID_NOT_LOAD', 'exit', process.poll())
                return 1
            if mode == 'apple-events':
                config = json.dumps({'address': url, 'pid': process.pid, 'images': page_config['images']})
                result = subprocess.run([executable, HERE / 'fixture-command.js'], input=config, text=True, timeout=30,
                                        stdout=subprocess.PIPE, check=False)
                print(result.stdout.strip())
                if result.returncode:
                    return result.returncode
            elif not done.wait(15) or summary != [True]:
                print('HEADLESS_DRAFT_INVARIANTS_UNVERIFIED')
                return 1
            if set(received) != set(expected) or invalid:
                print('RECEIVER_MISMATCH')
                return 1
            evidence = {'scope': 'local-fixture', 'mode': mode, 'verifiedBodies': len(received),
                        'digests': [hashlib.sha256(images[op]).hexdigest() for op in images],
                        'acknowledgements': 2, 'correlatedRejections': int(ids[4] in received),
                        'lostReplies': int(ids[5] in received), 'duplicateRequests': len(invalid)}
            print(json.dumps(evidence, sort_keys=True))
            return 0
        finally:
            server.shutdown()
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['headless', 'apple-events'], required=True)
    parser.add_argument('--hosted-runner-window', action='store_true',
                        help='Only for an isolated GitHub-hosted macOS runner investigating foreground Apple Events')
    args = parser.parse_args()
    if args.hosted_runner_window and (args.mode != 'apple-events' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'):
        parser.error('a visible fixture requires a disposable GitHub-hosted runner')
    raise SystemExit(run(args.mode, args.hosted_runner_window))
