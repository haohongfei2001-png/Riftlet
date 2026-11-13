"""Run Safari's public scripting interface only on a fresh, owned hosted macOS console."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
from pathlib import Path
import platform
import secrets
import subprocess
import tempfile
import threading

HERE = Path(__file__).resolve().parent


def exercise():
    if (platform.system() != 'Darwin' or os.getenv('GITHUB_ACTIONS') != 'true'
            or os.getenv('RUNNER_ENVIRONMENT') != 'github-hosted' or os.getuid() == 0
            or os.stat('/dev/console').st_uid != os.getuid()):
        print('NOT_RUN_HOSTED_CONSOLE_REQUIRED')
        return 77
    path = '/draft/' + secrets.token_hex(16)
    tokens = set()

    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.path != path:
                self.send_error(404)
                return
            token = secrets.token_hex(16)
            tokens.add(token)
            body = f'<!doctype html><html data-neutral-token="{token}"><textarea>neutral draft</textarea></html>'.encode()
            self.send_response(200)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    with tempfile.TemporaryDirectory(prefix='riftlet-safari-') as temp, HTTPServer(('127.0.0.1', 0), Fixture) as server:
        binary = Path(temp) / 'safari-probe'
        cache = os.environ.get('CLANG_MODULE_CACHE_PATH', str(Path(temp) / 'modules'))
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', cache, HERE / 'safari_fixture.swift', '-o', binary],
                       timeout=180, check=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            p = subprocess.run([binary, HERE / 'safari-fixture.applescript', f'http://127.0.0.1:{server.server_port}{path}'],
                               timeout=35)
        finally:
            server.shutdown()
        if p.returncode == 0 and len(tokens) < 3:
            raise RuntimeError('Fewer than three fresh neutral documents from independent receiver')
        print('neutralDocumentResponses', len(tokens), 'attachments', 0)
        return p.returncode


if __name__ == '__main__':
    raise SystemExit(exercise())
