"""Real, hidden WKWebView in a cooperating test host. Synthetic image bytes stay on loopback."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import platform
import struct
import sys
import subprocess
import tempfile
import threading
import zlib

from ax_host import probe as external_ax_probe

HERE = Path(__file__).resolve().parent


def pixel(rgb):
    def chunk(kind, body):
        return struct.pack('!I', len(body)) + kind + body + struct.pack('!I', zlib.crc32(kind + body))
    header = struct.pack('!2I5B', 1, 1, 8, 2, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(bytes((0, *rgb)))) + chunk(b'IEND', b''))


def webkit():
    if platform.system() != 'Darwin':
        raise SystemExit('NOT_RUN_MACOS_REQUIRED')
    page = (HERE / 'draft.html').read_bytes()
    inputs = [pixel((90, 100, 110)), pixel((120, 130, 140))]
    prior = pixel((42, 72, 102))
    served_prior = []
    received = []
    events = []

    class Receiver(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def reply(self, code, type_, data):
            self.send_response(code)
            self.send_header('Content-Type', type_)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == '/draft':
                self.reply(200, 'text/html', page)
            elif self.path == '/prior.png':
                served_prior.append(hashlib.sha256(prior).hexdigest())
                self.reply(200, 'image/png', prior)
            else:
                self.reply(404, 'text/plain', b'')

        def do_POST(self):
            index = len(received)
            if (index >= len(inputs) or self.path != f'/receive/{index}'
                    or self.headers.get('Content-Length') != str(len(inputs[index]))
                    or self.headers.get_content_type() != 'image/png'):
                events.append('unexpected-request')
                self.reply(400, 'text/plain', b'')
                return
            self.connection.settimeout(4)
            first = self.rfile.read(1)
            if first != inputs[index][:1]:
                events.append('incorrect-first-byte')
                self.reply(400, 'text/plain', b'')
                return
            events.append(f'body-start-{index}')
            data = first + self.rfile.read(len(inputs[index]) - 1)
            if data != inputs[index]:
                events.append('wrong-bytes')
                self.reply(400, 'text/plain', b'')
                return
            received.append(hashlib.sha256(data).hexdigest())
            events.append(f'body-complete-{index}')
            self.reply(201, 'text/plain', f'received-{index}'.encode())

    with tempfile.TemporaryDirectory(prefix='riftlet-native-picker-') as directory:
        root = Path(directory).resolve()
        for index, data in enumerate(inputs):
            (root / f'neutral-{index}.png').write_bytes(data)
        binary = root / 'picker-fixture'
        # SwiftPM is unnecessary for this standalone Apple-framework fixture.
        cache = os.environ.get('CLANG_MODULE_CACHE_PATH', str(root / 'module-cache'))
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', cache,
                        *[str(HERE.parents[1] / 'Sources/RiftletAdapters' / source) for source in
                          ('AttachmentTransport.swift', 'NativeMacAXDriver.swift', 'NativePickerVerifiedFile.swift',
                           'NativePickerFileDelivery.swift')],
                        str(HERE / 'Probe.swift'), '-o', str(binary)], check=True, timeout=240)
        with HTTPServer(('127.0.0.1', 0), Receiver) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                result = subprocess.run([str(binary), str(server.server_port), str(root)],
                                        check=True, capture_output=True, text=True, timeout=30)
            except subprocess.CalledProcessError as error:
                # Only our bounded diagnostic code, never framework/process output.
                for line in error.stderr.splitlines():
                    if line.startswith('native-picker fixture: '):
                        print(line, flush=True)
                raise
            finally:
                server.shutdown()
                thread.join()
        if (served_prior != [hashlib.sha256(prior).hexdigest()]
                or received != [hashlib.sha256(item).hexdigest() for item in inputs]
                or events != ['body-start-0', 'body-complete-0', 'body-start-1', 'body-complete-1']):
            raise RuntimeError('Receiver did not confirm two independent ordered uploads')
        print(json.dumps(dict(scope='controlled-cooperating-WKWebView', macOS=platform.mac_ver()[0],
                              arch=platform.machine(), receiverEvents=events, sha256=received, priorPNGSHA256=served_prior[0],
                              **json.loads(result.stdout)), sort_keys=True), flush=True)


def external_ax():
    if platform.system() != 'Darwin':
        raise SystemExit('NOT_RUN_MACOS_REQUIRED')
    subprocess.run([sys.executable, '-B', '-m', 'unittest', 'discover', '-s', str(HERE),
                    '-p', 'test_ax_result.py'], check=True)
    with tempfile.TemporaryDirectory(prefix='riftlet-ax-cache-') as directory:
        cache = os.environ.get('CLANG_MODULE_CACHE_PATH', directory)
        result = external_ax_probe(HERE, pixel((90, 100, 110)), pixel((42, 72, 102)), cache)
    print(json.dumps({'scope': 'controlled-external-appkit', 'externalAX': result}, sort_keys=True), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=['webkit', 'external-ax'])
    choice = parser.parse_args().only
    if choice in (None, 'webkit'):
        webkit()
    if choice in (None, 'external-ax'):
        external_ax()
