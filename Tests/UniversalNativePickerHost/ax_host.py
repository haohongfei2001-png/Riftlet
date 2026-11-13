"""Two distinct external AX paths. Visible receivers run only on a disposable hosted Mac."""
import ctypes
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
from pathlib import Path
import plistlib
import signal
import shutil
import subprocess
import tempfile
import threading
import time
from uuid import uuid4


class ProbeFailure(RuntimeError):
    """An observed failure, independent of whether the platform is supported."""


def classify(mode, state, events, acknowledged):
    valid_events = ['firstBodyByte', 'expectedCompleteBody']
    if any(event not in valid_events for event in events):
        raise ProbeFailure(f'{mode}: incorrect or duplicate file delivery ({events})')
    if state == 'EXACT_FILE_SUBMIT_ATTEMPTED':
        if events != valid_events or not acknowledged:
            raise ProbeFailure(f'{mode}: submit lacked original draft acknowledgement or exact body ({events})')
        return 'VERIFIED_EXTERNAL_FIXTURE_HANDOFF'
    if events or acknowledged:
        raise ProbeFailure(f'{mode}: delivery occurred without a confirmed submit ({state}, {events})')
    if state == 'NOT_RUN_NO_EXISTING_AX_TRUST':
        return state
    # Remote system sheets do not promise in-process AX ownership/URL rows.
    # These specific refusals happen before a file is supplied to the client.
    if mode == 'system-open-panel' and state in {
            'ENTRY_PRESSED_OWNED_SHEET_UNPROVEN', 'SHEET_OWNED_FILE_ROW_UNPROVEN', 'EXACT_SELECTION_UNPROVEN'}:
        return state
    raise ProbeFailure(f'{mode}: controlled binding, selection or action failed ({state})')


def owned_receiver(pid, executable):
    if pid <= 1:
        return False
    path = ctypes.create_string_buffer(4096)
    proc = ctypes.CDLL('/usr/lib/libproc.dylib').proc_pidpath
    proc.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    return proc(pid, path, len(path)) > 0 and os.path.realpath(path.value) == os.fsencode(executable.resolve())


def exercise(executable, observer, nonce, directory, sample):
    events = []
    receipt = ('accepted-' + nonce).encode()

    class Receiver(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_POST(self):
            self.connection.settimeout(3)
            if (self.path != '/receive/' + nonce or self.headers.get_content_type() != 'image/png'
                    or self.headers.get('Content-Length') != str(len(sample)) or events):
                events.append('unexpectedOrDuplicate')
                self.send_error(400)
                return
            first = self.rfile.read(1)
            if first != sample[:1]:
                events.append('wrongFirstByte')
                self.send_error(400)
                return
            events.append('firstBodyByte')
            if first + self.rfile.read(len(sample) - 1) != sample:
                events.append('wrongCompleteBody')
                self.send_error(400)
                return
            events.append('expectedCompleteBody')
            self.send_response(201)
            self.send_header('Content-Length', str(len(receipt)))
            self.end_headers()
            self.wfile.write(receipt)

    with HTTPServer(('127.0.0.1', 0), Receiver) as server:
        (directory / 'port').write_text(str(server.server_port))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            # LaunchServices registers the regular app and presents its window.
            # The separate plain executable has no competing foreground app identity.
            receiver_pid = 0
            command = ['/usr/bin/open', '-n', '-W', '--env', 'GITHUB_ACTIONS=true', '--env',
                       'RUNNER_ENVIRONMENT=github-hosted', str(executable.parents[2]),
                       '--args', '--receive', nonce, str(directory)]
            with subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as receiver:
                try:
                    until = time.monotonic() + 9
                    while receiver.poll() is None and not (directory / 'ready').exists() and time.monotonic() < until:
                        time.sleep(0.1)
                    if not (directory / 'ready').exists():
                        details = directory / 'startup-status'
                        status = details.read_text() if details.is_file() else 'NO_REGISTERED_READY_RECEIPT'
                        raise ProbeFailure(f'{directory.name}: fixture startup failed ({status})')
                    receiver_pid = int((directory / 'ready').read_text())
                    if not owned_receiver(receiver_pid, executable):
                        raise ProbeFailure(f'{directory.name}: unexpected executable for the private receiver PID')
                    try:
                        result = subprocess.run([str(observer), '--observe', nonce, str(receiver_pid), str(directory)],
                                                check=False, capture_output=True, text=True, timeout=8)
                    except subprocess.TimeoutExpired as error:
                        raise ProbeFailure(f'{directory.name}: observer timed out') from error
                    if result.returncode:
                        raise ProbeFailure(f'{directory.name}: AX observer exited with {result.returncode}')
                    state = result.stdout.strip()
                    if state == 'EXACT_FILE_SUBMIT_ATTEMPTED':
                        receiver.wait(timeout=20)
                        if receiver.returncode != 0:
                            raise ProbeFailure(f'{directory.name}: receiving draft exited with {receiver.returncode}')
                    received = directory / 'received'
                    acknowledged = received.is_file() and received.read_bytes() == sample
                    status = classify(directory.name, state, list(events), acknowledged)
                    return {'status': status, 'receiverEvents': list(events), 'originalDraftAcknowledged': acknowledged,
                            'draftTextSelectionPriorPNGPreserved': acknowledged,
                            'sha256': hashlib.sha256(sample).hexdigest() if acknowledged else None,
                            'commercialService': 'NOT_RUN'}
                finally:
                    if owned_receiver(receiver_pid, executable):
                        try:
                            os.kill(receiver_pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                    if receiver.poll() is None:
                        try:
                            receiver.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            receiver.terminate()  # our /usr/bin/open launcher

        finally:
            server.shutdown()
            thread.join()


def probe(here, sample, prior, cache):
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
        return {'status': 'NOT_RUN_HOSTED_CONSOLE_REQUIRED'}
    if os.stat('/dev/console').st_uid != os.getuid() or os.getuid() == 0:
        return {'status': 'NOT_RUN_NO_OWNED_CONSOLE'}
    adapters = here.parents[1] / 'Sources/RiftletAdapters'
    with tempfile.TemporaryDirectory(prefix='riftlet-ax-picker-') as temp:
        root = Path(temp).resolve()
        nonce = str(uuid4()).upper()
        contents = root / 'AXPickerFixture.app/Contents'
        executable = contents / 'MacOS/AXPickerFixture'
        executable.parent.mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps(dict(
            CFBundleIdentifier='org.riftlet.axpicker.' + nonce, CFBundleExecutable=executable.name,
            CFBundlePackageType='APPL', CFBundleShortVersionString='1', CFBundleVersion='1')))
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', cache,
                        *[str(adapters / source) for source in ('NativeMacAXDriver.swift', 'AXPickerInspection.swift',
                          'AttachmentTransport.swift', 'AXPickerFileHandoff.swift')],
                        str(here / 'AXPickerHost.swift'), '-o', str(executable)], check=True, timeout=180)
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(contents.parent)], check=True)
        # Do not invoke the observer through the receiver bundle. Two copies of
        # that bundle identity cannot act as an unambiguous foreground binding.
        observer = root / 'ax-observer'
        shutil.copy2(executable, observer)
        subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', 'org.riftlet.fixtureobserver.' + nonce,
                        '--timestamp=none', str(observer)], check=True)
        result = {}
        for mode in ['appkit-file-list', 'system-open-panel']:
            directory = root / mode
            (directory / 'images').mkdir(parents=True, mode=0o700)
            (directory / 'images/neutral.png').write_bytes(sample)
            (directory / 'prior.png').write_bytes(prior)
            if mode == 'appkit-file-list':
                (directory / 'images/decoy.png').write_bytes(prior)
            try:
                result[mode] = exercise(executable, observer, nonce, directory, sample)
            except (ProbeFailure, subprocess.TimeoutExpired) as error:
                result[mode] = {'status': 'FAILED_CONTROLLED_VALIDATION', 'reason': str(error)}
            line = f"External AX {mode}: {result[mode]['status']}"
            print(line, flush=True)
            if summary := os.environ.get('GITHUB_STEP_SUMMARY'):
                with open(summary, 'a', encoding='utf-8') as stream:
                    stream.write(line + '\n')
        failures = [f'{mode}: {status["reason"]}' for mode, status in result.items()
                    if status['status'] == 'FAILED_CONTROLLED_VALIDATION']
        if failures:
            raise ProbeFailure(' / '.join(failures))
        return result
