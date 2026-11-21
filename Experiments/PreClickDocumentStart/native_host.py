#!/usr/bin/env python3
"""Test-only Native Messaging host. UI events come from a private Unix socket."""
import fcntl
import json
import os
from pathlib import Path
import secrets
import selectors
import socket
import sqlite3
import stat
import struct
import sys
import time
import uuid

def send(message):
    data = json.dumps(message, separators=(',', ':')).encode()
    sys.stdout.buffer.write(struct.pack('=I', len(data)) + data)
    sys.stdout.buffer.flush()

def main():
    base = Path(__file__).resolve().parent
    config = json.loads((base / 'config.json').read_text())
    (base/'launched').write_text('matched' if sys.argv[1:2]==[config['extensionOrigin']] else 'wrong-origin')
    if sys.argv[1:2] != [config['extensionOrigin']]:
        return 2
    session = socket.socket(socket.AF_UNIX)
    os.umask(0o077)
    lock = (base/'host.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    endpoint = base/'input.sock'
    if endpoint.exists():
        if not stat.S_ISSOCK(endpoint.lstat().st_mode): return 2
        endpoint.unlink()
    session.bind(str(endpoint))
    session.listen(1)
    poll = selectors.DefaultSelector()
    poll.register(session, selectors.EVENT_READ)
    poll.register(sys.stdin.fileno(), selectors.EVENT_READ)
    db = sqlite3.connect(base / 'claims.sqlite')
    db.execute('CREATE TABLE IF NOT EXISTS op(id TEXT PRIMARY KEY,state TEXT,identity TEXT,drop_reply INTEGER,observed_drop INTEGER DEFAULT 0)')
    db.commit()
    ready = {}
    packet = bytearray()
    while True:
        for fd, _ in poll.select():
            if fd.fileobj == session:
                with session.accept()[0] as source:
                    source.settimeout(2)
                    with source.makefile('rb') as f:
                        event = json.loads(f.readline(4096))
                    action = event['action']
                    if action == 'current':
                        visible = [v for v in ready.values() if v.get('readyNS')]
                        answer = visible[0] if len(visible) == 1 else {}
                    elif action == 'state':
                        row = db.execute('SELECT state FROM op WHERE id=?',(event['op'],)).fetchone()
                        answer = {'state': row[0] if row else 'ABSENT'}
                    elif action == 'click':
                        original = ready.get(event['key']['ticket'])
                        stamp = event['eventNS']
                        prior = db.execute('SELECT state FROM op WHERE id=?',(event['op'],)).fetchone()
                        if prior:
                            answer = {'state':'ALREADY_CLAIMED','previous':prior[0]}
                        elif not original or original.get('key') != event['key'] or original.get('ack') != event['ack'] or not (
                            original.get('readyNS',0) > 0 and original['readyNS'] < stamp <= time.monotonic_ns()
                        ):
                            answer = {'state':'REFUSED'}
                        else:
                            uuid.UUID(event['op'])
                            # Commit the original claim before sending anything into the browser.
                            identity = json.dumps(original['key'],sort_keys=True)
                            db.execute('INSERT INTO op(id,state,identity,drop_reply) VALUES(?,?,?,?)',
                                       (event['op'],'UNKNOWN',identity,int(event.get('dropReply') is True)))
                            db.commit()
                            send({'kind':'commit','key':original['key'],'ack':original['ack'],
                                  'op':event['op'],'png':config['fixturePNG']})
                            answer = {'state':'CLAIMED','ackBeforeEvent':original['readyNS'] < stamp}
                    else:
                        answer = {'state':'REFUSED'}
                    source.sendall((json.dumps(answer)+'\n').encode())
                continue
            data = os.read(sys.stdin.fileno(),65536)
            if not data: return 0
            packet.extend(data)
            while len(packet) >= 4:
                n, = struct.unpack_from('=I', packet)
                if n > 8192: return 2
                if len(packet) < n+4: break
                msg=json.loads(packet[4:4+n]); del packet[:n+4]
                key=msg['key']; ticket=key['ticket']
                if msg['kind']=='offer':
                    uuid.UUID(ticket); uuid.UUID(key['documentId'])
                    if not all(isinstance(key[k],int) and key[k]>0 for k in ('windowId','tabId')): continue
                    ack=secrets.token_hex(24)
                    ready[ticket]={'key':key,'ack':ack}
                    send({'kind':'ack','key':key,'ack':ack})
                elif msg['kind']=='ready':
                    current=ready.get(ticket)
                    if current and current['key']==key and current['ack']==msg['ack']:
                        current['readyNS']=time.monotonic_ns()
                elif msg['kind']=='revoke':
                    if ready.get(ticket,{}).get('key')==key: ready.pop(ticket)
                elif msg['kind']=='result' and msg.get('state') in ('UNKNOWN','REFUSED','INPUT_RETURNED'):
                    db.execute("""UPDATE op SET state=CASE WHEN drop_reply=1 THEN state ELSE ? END,
                                           observed_drop=drop_reply WHERE id=? AND identity=? AND state='UNKNOWN'""",
                               (msg['state'],msg['op'],json.dumps(key,sort_keys=True)))
                    db.commit()
if __name__=='__main__':
    sys.exit(main())
