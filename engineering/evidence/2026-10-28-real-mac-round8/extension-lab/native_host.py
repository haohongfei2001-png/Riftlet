#!/usr/bin/env python3
"""Synthetic metadata only. No browser, file, input, upload, or App authority API."""
import json
import os
import re
import sys
import time
import uuid

MAX_BYTES = 4096
MAX_MESSAGES = 128
UUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
DOCUMENT_ID = re.compile(r'^[0-9a-fA-F]{32}$')
IDENTITY = {'documentID', 'documentNonce', 'tabID', 'windowID', 'frameID'}

class Refused(ValueError):
    pass

def exact(value, keys):
    if type(value) is not dict or set(value) != set(keys):
        raise Refused('schema')

def uid(value):
    if type(value) is not str or not UUID.fullmatch(value):
        raise Refused('identity')

def integer(value, low=0):
    if type(value) is not int or not low <= value <= 2**31-1:
        raise Refused('integer')

def pairs(values):
    result = {}
    for key, value in values:
        if key in result:
            raise Refused('duplicate-key')
        result[key] = value
    return result

def read_exact(stream, count):
    result = bytearray()
    while len(result) < count:
        data = stream.read(count - len(result))
        if not data:
            raise Refused('truncated')
        result.extend(data)
    return bytes(result)

def read_frame(stream):
    first = stream.read(1)
    if not first:
        return None
    length = int.from_bytes(first + read_exact(stream, 3), sys.byteorder)
    if not 0 < length <= MAX_BYTES:
        raise Refused('length')
    try:
        return json.loads(read_exact(stream, length).decode('utf-8'), object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(Refused('constant')))
    except (UnicodeError, json.JSONDecodeError, RecursionError):
        raise Refused('json') from None

def frame(value):
    data = json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(',', ':')).encode()
    if not 0 < len(data) <= MAX_BYTES:
        raise Refused('length')
    return len(data).to_bytes(4, sys.byteorder) + data

class Gate:
    """A candidate cache, NEVER production authority. Clock belongs to host."""
    def __init__(self, clock=time.monotonic_ns):
        self.clock = clock
        self.host_epoch = str(uuid.uuid4())
        self.channel = None
        self.sequence = 0
        self.view = None
        self.seen_views = set()
        self.publication = None
        self.closed = False

    def close(self):
        self.closed = True
        self.publication = None

    def receive(self, message):
        try:
            return self._receive(message)
        except (Refused, TypeError, KeyError):
            self.close()
            raise Refused('protocol') from None

    def _receive(self, m):
        if self.closed or type(m) is not dict:
            raise Refused('closed')
        if self.channel is None:
            exact(m, {'v', 'kind', 'channel'})
            if m['v'] != 1 or type(m['v']) is not int or m['kind'] != 'hello':
                raise Refused('hello')
            uid(m['channel']); self.channel = m['channel']
            return {'v': 1, 'kind': 'helloAck', 'hostEpoch': self.host_epoch,
                    'channel': self.channel, 'inputAuthority': False}
        common = {'v', 'kind', 'channel', 'hostEpoch', 'sequence', 'viewEpoch'}
        kind = m.get('kind')
        exact(m, common | (IDENTITY | {'phase'} if kind == 'publish' else set()))
        if m['v'] != 1 or type(m['v']) is not int or kind not in ('invalidate', 'publish'):
            raise Refused('kind')
        uid(m['viewEpoch']); integer(m['sequence'], 1)
        if m['channel'] != self.channel or m['hostEpoch'] != self.host_epoch or m['sequence'] != self.sequence + 1:
            raise Refused('order')
        if m['sequence'] > MAX_MESSAGES:
            raise Refused('budget')
        self.sequence = m['sequence']
        if kind == 'invalidate':
            if m['viewEpoch'] in self.seen_views:
                raise Refused('reused-epoch')
            self.view = m['viewEpoch']; self.seen_views.add(self.view); self.publication = None
        else:
            if type(m['documentID']) is not str or not DOCUMENT_ID.fullmatch(m['documentID']) or m['documentID'] == '0' * 32:
                raise Refused('document-id')
            uid(m['documentNonce'])
            integer(m['tabID']); integer(m['windowID'])
            if type(m['frameID']) is not int or m['frameID'] != 0:
                raise Refused('frame')
            if m['phase'] not in ('document_start', 'dom_ready', 'visibility_change') or m['viewEpoch'] != self.view:
                raise Refused('stale-view')
            identity = {k: m[k] for k in IDENTITY}
            if self.publication and self.publication['identity'] != identity:
                raise Refused('identity-change-without-invalidation')
            self.publication = {'identity': identity, 'viewEpoch': self.view,
                                'publishedNS': self.clock(), 'hostEpoch': self.host_epoch}
        return {'v': 1, 'kind': kind + 'Ack', 'sequence': self.sequence,
                'candidatePresent': self.publication is not None, 'inputAuthority': False,
                'publishedNS': str(self.publication['publishedNS']) if self.publication else None}

    def freeze(self, original_event_ns, expected_view, expected_identity):
        # The event and expected current identity are HOST test inputs, never wire fields.
        p = self.publication
        eligible = (not self.closed and type(original_event_ns) is int and p is not None
                    and 0 <= p['publishedNS'] < original_event_ns <= self.clock()
                    and original_event_ns - p['publishedNS'] <= 500_000_000
                    and expected_view == p['viewEpoch'] and expected_identity == p['identity'])
        return {'eligibleOriginalPublication': bool(eligible), 'inputAuthority': False}

def main():
    allowed = os.environ.get('RIFTLET_LAB_ORIGIN', '')
    if len(sys.argv) != 2 or not re.fullmatch(r'chrome-extension://[a-p]{32}/', allowed) or sys.argv[1] != allowed:
        return 2
    gate = Gate()
    try:
        for _ in range(MAX_MESSAGES + 1):
            message = read_frame(sys.stdin.buffer)
            if message is None:
                gate.close(); return 0
            reply = gate.receive(message)
            sys.stdout.buffer.write(frame(reply)); sys.stdout.buffer.flush()
        gate.close(); return 2
    except (Refused, BrokenPipeError):
        gate.close(); return 2  # No untrusted body/identity reaches stderr.

if __name__ == '__main__':
    raise SystemExit(main())
