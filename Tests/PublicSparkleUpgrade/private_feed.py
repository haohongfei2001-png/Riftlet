"""Keep the candidate inside the draft or the disposable Mac; expose it only to that Mac's Sparkle."""
import base64
from contextlib import contextmanager
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import threading

release_source = '2598c0004d1f897880951e6c8a38c7503eb61948'
archive_name = 'Riftlet-1.0.11.dmg'
archive_sha = '1611fbbd1866d1e686489dece6b8fbc03d7f0dcde4669a0b58c8a9a95c0c8f41'
feed_sha = 'cee9bcbc0096cae5cf7e84b71309ff542b83add1e02063b78d56a10b74572609'
base_url = 'http://127.0.0.1:48167/'
private_dir = Path(os.environ['RUNNER_TEMP']) / 'riftlet-private-sparkle'
def file_sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fetch_private_inputs():
    assert os.environ['GITHUB_REPOSITORY'] == 'haohongfei2001-png/Riftlet'
    assert os.environ['GITHUB_REF'] == 'refs/heads/codex/riftlet-111-public-upgrade-qa'
    assert os.environ['RUNNER_ENVIRONMENT'] == 'github-hosted'
    os.umask(0o077)
    private_dir.mkdir(mode=0o700)
    release_id = int(os.environ['PRIVATE_RELEASE_ID'])
    assert release_id > 0
    prefix='repos/haohongfei2001-png/Riftlet/releases/'
    result = subprocess.check_output(['gh','api',prefix+str(release_id)],timeout=35)
    release = json.loads(result)
    assert release['id']==release_id and release['draft'] and release['published_at'] is None
    assert release['target_commitish']==release_source and release['tag_name']=='v1.0.11'
    assets={a['name']:a for a in release['assets']}
    assert set(assets)=={'SHA256SUMS.txt',archive_name}
    asset=assets[archive_name]
    assert asset['state']=='uploaded' and asset['digest']=='sha256:'+archive_sha and asset['size']==13945478
    path=private_dir/archive_name
    with path.open('xb') as out:
        subprocess.run(['gh','api','-H','Accept: application/octet-stream',prefix+'assets/'+str(asset['id'])],stdout=out,check=True,timeout=135)
    assert file_sha(path)==archive_sha and path.stat().st_size==asset['size']
    signed=base64.b64decode(os.environ['PRIVATE_FEED_B64'],validate=True)
    assert hashlib.sha256(signed).hexdigest()==feed_sha
    (private_dir/'private.xml').write_bytes(signed)

@contextmanager
def serve():
    assert file_sha(private_dir/archive_name)==archive_sha and file_sha(private_dir/'private.xml')==feed_sha
    gets = []
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):
            pass
        def do_GET(self):
            name=self.path.partition('?')[0].removeprefix('/')
            if name not in ('private.xml',archive_name) or self.client_address[0]!='127.0.0.1':
                self.send_error(404);return
            file=private_dir/name
            self.send_response(200);self.send_header('Content-Type','application/rss+xml' if name=='private.xml' else 'application/octet-stream')
            self.send_header('Content-Length',str(file.stat().st_size));self.end_headers()
            with file.open('rb') as stream:
                while chunk:=stream.read(131072):
                    self.wfile.write(chunk)
            gets.append(name)
    with ThreadingHTTPServer(('127.0.0.1',48167),Handler) as http:
        thread=threading.Thread(target=http.serve_forever,daemon=True);thread.start()
        try:yield gets
        finally:http.shutdown();thread.join()

if __name__=='__main__':
    fetch_private_inputs()
