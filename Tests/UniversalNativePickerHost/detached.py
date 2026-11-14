"""Verify the real AX radio action on a nonactivating receiver, independent of click routing."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from uuid import uuid4

from run import pixel

HERE = Path(__file__).resolve().parent


def run():
    with tempfile.TemporaryDirectory(prefix='riftlet-detached-ax-') as temp:
        root = Path(temp)
        binary = root / 'detached'
        file = root / 'token'
        file.write_text(str(uuid4()))
        data = pixel((90, 100, 110))
        (root / 'neutral.png').write_bytes(data)
        expected = file.read_bytes() + b' ' + hashlib.sha256(data).hexdigest().encode()
        cache = os.environ.get('CLANG_MODULE_CACHE_PATH', str(root / 'module-cache'))
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', cache,
                        str(HERE / 'AXPickerActionButton.swift'), str(HERE / 'AXPickerDetached.swift'),
                        '-o', str(binary)], check=True, timeout=180)
        with subprocess.Popen([str(binary), '--receive', str(file)]) as receiver:
            try:
                until = time.monotonic() + 4
                while time.monotonic() < until and not (root / 'ready').exists() and receiver.poll() is None:
                    time.sleep(0.04)
                if not (root / 'ready').exists():
                    raise RuntimeError('DETACHED_RECEIVER_STARTUP_FAILED')
                observed = subprocess.run([str(binary), '--observe', str(file), str(receiver.pid)], capture_output=True,
                                          text=True, timeout=5)
                state = observed.stdout.strip()
                receipt = root / 'receipt'
                until = time.monotonic() + 1
                while not receipt.is_file() and time.monotonic() < until and observed.returncode == 0:
                    time.sleep(0.04)
                exact = receipt.is_file() and receipt.read_bytes() == expected
                print(json.dumps(dict(scope='detached-AX-selection-and-confirmation', observer=state,
                                      exactReceiverHandlerReceipt=exact, expectedPNGBytes=len(data),
                                      expectedPNGSHA256=hashlib.sha256(data).hexdigest(), externalService='NOT_RUN'), sort_keys=True))
                if observed.returncode != 0 or state != 'DETACHED_SELECTION_AND_SUBMIT_AXPRESS_ONCE' or not exact:
                    raise SystemExit(observed.returncode or 1)
            finally:
                if receiver.poll() is None:
                    receiver.terminate()


if __name__ == '__main__':
    run()
