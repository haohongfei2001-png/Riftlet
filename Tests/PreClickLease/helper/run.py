#!/usr/bin/env python3
"""Windowless loopback experiment. A browser executable is always explicitly supplied."""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import sqlite3
import subprocess
import tempfile
import threading
import time
import uuid

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[2] / 'Experiments/PreClickDocumentStart'
PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZsAAAAASUVORK5CYII='
def until(fn, timeout=4):
    deadline = time.monotonic()+timeout
    while time.monotonic()<deadline:
        result=fn()
        if result: return result
        time.sleep(.04)
    raise TimeoutError('condition not observed')
def lab(browser, label, event_binary):
    with tempfile.TemporaryDirectory(prefix='r108-',dir='/private/tmp') as tmp:
        root=Path(tmp)
        nonce=secrets.token_hex(12)
        route='/riftlet-preclick-lab/'+nonce
        observations=[]
        commands=[]
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                if self.path==route:
                    body=(HERE/'fixture.html').read_bytes()
                    self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8')
                elif self.path==route+'/next':
                    body=json.dumps(commands.pop(0) if commands else '').encode()
                    self.send_response(200);self.send_header('Content-Type','application/json')
                else:
                    self.send_error(404);return
                self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(body)
            def do_POST(self):
                if self.path!=route+'/report': self.send_error(404);return
                n=int(self.headers.get('Content-Length',0))
                if n<1 or n>2000: self.send_error(400);return
                observations.append(json.loads(self.rfile.read(n)))
                self.send_response(204);self.end_headers()
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}{route}'
        ext=root/'extension';shutil.copytree(SOURCE/'extension',ext)
        (ext/'scope.js').write_text('globalThis.riftletLabURL='+json.dumps(url)+';\n')
        key=base64.b64decode(json.loads((ext/'manifest.json').read_text())['key'])
        eid=hashlib.sha256(key).hexdigest()[:32].translate(str.maketrans('0123456789abcdef','abcdefghijklmnop'))
        host=root/'host';host.mkdir(mode=0o700)
        shutil.copy2(SOURCE/'native_host.py',host/'native_host.py')
        origin='chrome-extension://'+eid+'/'
        (host/'config.json').write_text(json.dumps({'extensionOrigin':origin,'fixturePNG':PNG}))
        profile=root/'profile';manifests=profile/'NativeMessagingHosts';manifests.mkdir(parents=True)
        name='com.riftlet.preclick_lab'
        (manifests/(name+'.json')).write_text(json.dumps({'name':name,'description':'Disposable loopback fixture',
            'path':str(host/'native_host.py'),'type':'stdio','allowed_origins':[origin]}))
        def ipc(**kw):
            with socket.socket(socket.AF_UNIX) as s:
                s.settimeout(1);s.connect(str(host/'input.sock'))
                s.sendall((json.dumps(kw)+'\n').encode());s.shutdown(socket.SHUT_WR)
                return json.loads(s.makefile('rb').readline(8192))
        def event(): return int(subprocess.check_output([event_binary],text=True).strip())
        def click(pin, op, when, lost=False):
            return ipc(action='click',key=pin['key'],ack=pin['ack'],eventNS=when,op=op,dropReply=lost)
        def page_count(): return sum(m.get('action')=='input' for m in observations)
        def settled(op): return ipc(action='state',op=op)['state']
        def next_pin(old=None):
            def probe():
                now=ipc(action='current')
                return now if now and (old is None or now['key']!=old['key']) else None
            return until(probe)
        before=event()
        flags=['--headless=new','--no-first-run','--no-default-browser-check','--disable-sync',
               '--enable-logging=stderr','--disable-background-networking','--disable-component-update','--disable-client-side-phishing-detection',
               '--user-data-dir='+str(profile),'--disable-extensions-except='+str(ext),'--load-extension='+str(ext),url]
        result={'browser':label,'version':subprocess.check_output([str(browser),'--version'],text=True).strip(),
                'os':'macOS','profile':'disposable','nativePipe':False,'pageReached':False}
        proc=subprocess.Popen([str(browser),*flags],stdout=subprocess.DEVNULL,stderr=(root/'browser.log').open('w'),start_new_session=True)
        try:
            until(lambda: any(m.get('action')=='open' for m in observations),12);result['pageReached']=True
            try:
                until(lambda: (host/'input.sock').exists(),2)
            except TimeoutError:
                commands.append('reload')
            try: until(lambda: (host/'input.sock').exists(),5)
            except TimeoutError:
                errors=(root/'browser.log').read_text(errors='replace')
                reasons=[line.split('] ',1)[-1].split(', source:')[0][:180] for line in errors.splitlines() if
                         ('RIFTLET_HELPER_' in line or 'native messaging host' in line.lower() or 'failed to load extension' in line.lower() or (('load-extension' in line.lower() or 'disable-extensions-except' in line.lower()) and ('disabled' in line.lower() or 'not allowed' in line.lower() or 'unsupported' in line.lower())))]
                if proc.poll() is None:
                    os.killpg(proc.pid,signal.SIGTERM);proc.wait(timeout=4)
                prefs=profile/'Default/Secure Preferences'
                if not prefs.exists():prefs=profile/'Default/Preferences'
                result.update(status='BLOCKED_NO_NATIVE_CHANNEL',diagnostic=reasons[:4],documentStages=[m['stage'] for m in observations if m.get('action')=='diagnostic'],
                              nativeInvocation=(host/'launched').read_text() if (host/'launched').exists() else 'NOT_STARTED',
                              isolatedExtensionRegistered=eid in prefs.read_text(errors='replace') if prefs.exists() else None,
                              pagesReached=sum(m.get('action')=='open' for m in observations))
                return result
            result['nativePipe']=True
            pin=next_pin()
            op=str(uuid.uuid4())
            assert click(pin,op,before)['state']=='REFUSED' and settled(op)=='ABSENT'
            for field in ('windowId','tabId','documentId'):
                wrong={**pin,'key':dict(pin['key'])}
                wrong['key'][field]=(str(uuid.uuid4()) if field=='documentId' else wrong['key'][field]+1)
                assert click(wrong,op,event())['state']=='REFUSED' and settled(op)=='ABSENT'
            natural=click(pin,op,event())
            assert natural=={'state':'CLAIMED','ackBeforeEvent':True}
            until(lambda: settled(op)=='INPUT_RETURNED' and page_count()==1)
            assert click(pin,op,event())['state']=='ALREADY_CLAIMED'
            warm=str(uuid.uuid4())
            assert click(pin,warm,event())['state']=='CLAIMED'
            until(lambda: settled(warm)=='INPUT_RETURNED' and page_count()==2)
            commands.append('editor-aba');fresh=next_pin(pin)
            assert fresh['key']['documentId']==pin['key']['documentId']
            assert click(pin,str(uuid.uuid4()),event())['state']=='REFUSED'
            commands.append('draft');revision=next_pin(fresh)
            assert revision['key']['documentId']==fresh['key']['documentId']
            assert click(fresh,str(uuid.uuid4()),event())['state']=='REFUSED'
            commands.append('reload');reloaded=next_pin(revision)
            assert reloaded['key']['documentId']!=fresh['key']['documentId']
            assert click(revision,str(uuid.uuid4()),event())['state']=='REFUSED'
            op2=str(uuid.uuid4())
            assert click(reloaded,op2,event(),True)['state']=='CLAIMED'
            until(lambda:page_count()==3)
            def dropped():
                with sqlite3.connect(host/'claims.sqlite') as reopened:
                    return reopened.execute('SELECT observed_drop FROM op WHERE id=?',(op2,)).fetchone()==(1,)
            until(dropped)
            assert settled(op2)=='UNKNOWN' and click(reloaded,op2,event())['state']=='ALREADY_CLAIMED'
            reports=[m for m in observations if m.get('action')=='input']
            assert [m['input'] for m in reports]==[1,2,1]
            assert len(reports)==3 and all(m['input']==m['change'] and m['send']==0 and m['old'] and m['text'] and m['selection'] and m['fileCount']==1 and m['sha256']==hashlib.sha256(base64.b64decode(PNG)).hexdigest() for m in reports)
            result.update(status='PASS_CONTROLLED',coldEventBeforeReady='REFUSED',firstEventAfterNativeReady='INPUT_RETURNED',
                          nextWarmEventSameLease='INPUT_RETURNED',wrongWindowTabDocument='REFUSED',sameEditorNewDraftGeneration='REFUSED',
                          sameDocumentEditorABA='REFUSED',sameURLNewDocument='REFUSED',browserDocumentIdChanged=True,
                          lostResult='UNKNOWN_NO_REPLAY',nativeOpClaims=3,syntheticPageInputs=3,sends=0,
                          priorTextSelectionAttachmentPreserved=True,sha256Matches=True)
            return result
        finally:
            os.killpg(proc.pid,signal.SIGTERM) if proc.poll() is None else None
            try: proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid,signal.SIGKILL);proc.wait()
            server.shutdown();server.server_close()
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--browser',type=Path,required=True)
    parser.add_argument('--label',required=True)
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='r108-event-',dir='/private/tmp') as t:
        binary=str(Path(t)/'capture-event')
        subprocess.run(['swiftc',str(HERE/'event.swift'),'-o',binary],check=True)
        print(json.dumps(lab(args.browser,args.label,binary),indent=2),flush=True)
