"""An ordinary Riftlet App rejecting a fresh Edge loopback window on a hosted Mac."""
import argparse
import ctypes
import errno
from contextlib import ExitStack
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import re
import sys
import secrets
import signal
import sqlite3
import stat
import subprocess
import tempfile
import threading
import time
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
EDGE = Path("/Applications/Microsoft Edge.app")
AX_HOST_SOURCES = ("ChromeProcessIdentity", "NativeMacAXDriver", "EdgeNativeDraftProbe", "EdgeApplicationHost",
                   "ChromeActiveTabDescriptor", "ApplicationHostAdapter", "ConversationSurfaceAdapter")
sys.path.insert(0, str(REPO / "Tests/UniversalNativePickerHost"))
from edge_neutral_picker import PIXEL, probe_neutral_picker

ROOT = Path.home() / "Library/Application Support/Riftlet"


def command(*args, check=True, timeout=15):
    return subprocess.run(list(map(str, args)), capture_output=True, check=check, timeout=timeout)


class ObservationTimeout(RuntimeError):
    pass


def wait_for(probe, label, seconds=14):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        result = probe()
        if result:
            return result
        time.sleep(0.2)
    raise ObservationTimeout(label)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def system_capture_digest(path, marker_wait=10):
    """Read the OS marker and PNG from one fd, watching only that original inode."""
    marker = b"com.apple.metadata:kMDItemIsScreenCapture"
    # Darwin's <sys/xattr.h> ABI differs from Linux. CPython on macOS does
    # not expose os.getxattr; keep the symbol binding off the non-Mac path.
    get_attribute = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True).fgetxattr
    get_attribute.restype = ctypes.c_ssize_t
    get_attribute.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p,
                              ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
        with os.fdopen(fd, "rb") as original:
            initial = os.fstat(fd)
            if not stat.S_ISREG(initial.st_mode) or initial.st_uid != os.getuid():
                raise RuntimeError("capture_not_owned_regular_file")
            header = original.read(24)
            if (len(header) != 24 or header[:16] != b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR"
                    or not int.from_bytes(header[16:20], "big") or not int.from_bytes(header[20:24], "big")):
                raise RuntimeError("capture_invalid_png_header")

            def marker_ready():
                if not os.path.samestat(initial, path.lstat()):
                    raise RuntimeError("capture_original_inode_changed")
                data = ctypes.create_string_buffer(4096)
                count = get_attribute(fd, marker, data, len(data), 0, 0)
                if count < 0:
                    code = ctypes.get_errno()
                    if code == errno.ENOATTR:
                        return False
                    if code == errno.ERANGE:
                        raise RuntimeError("capture_marker_oversized")
                    raise OSError(code, "fgetxattr")
                try:
                    value = plistlib.loads(data.raw[:count])
                except (plistlib.InvalidFileException, ValueError):
                    raise RuntimeError("capture_marker_invalid_plist") from None
                if type(value) is not bool:
                    raise RuntimeError("capture_marker_not_boolean")
                if not value:
                    raise RuntimeError("capture_marker_explicit_false")
                return True

            try:
                marked = wait_for(marker_ready, "capture_marker_absent_after_wait", marker_wait)
            except ObservationTimeout:
                marked = False
            original.seek(0)
            image_hash = hashlib.sha256(original.read()).hexdigest()
            final = os.fstat(fd)
            if (not os.path.samestat(initial, path.lstat()) or initial.st_size != final.st_size
                    or initial.st_mtime_ns != final.st_mtime_ns):
                raise RuntimeError("capture_original_changed")
            return image_hash, marked
    except FileNotFoundError:
        raise RuntimeError("capture_original_missing") from None
    except PermissionError:
        raise RuntimeError("capture_read_permission_denied") from None
    except OSError as error:
        if error.errno == errno.ELOOP:
            raise RuntimeError("capture_original_is_symlink") from None
        raise RuntimeError("capture_file_read_error") from None


def default_file_capture_target(source):
    settings = plistlib.loads(command("defaults", "export", "com.apple.screencapture", "-").stdout)
    return (settings.get("location") == str(source) and settings.get("target", "file") == "file"
            and settings.get("type", "png").lower() == "png")


def sole_new_png(source, previous):
    new = set(source.iterdir()) - previous
    if len(new) > 1:
        raise RuntimeError("ambiguous_system_capture_output")
    if new:
        output = next(iter(new))
        if output.suffix.lower() == ".png":
            return output
    return None


def stop_edge_group(process):
    # start_new_session makes this living child both the only session leader and group leader.
    if process.poll() is not None:
        return
    try:
        if os.getpgid(process.pid) != process.pid or os.getsid(process.pid) != process.pid:
            raise RuntimeError("edge_group_ownership_changed")
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            if process.poll() is None and os.getpgid(process.pid) == os.getsid(process.pid) == process.pid:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
    except ProcessLookupError:
        process.wait(timeout=5)


def events(path):
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_bytes().splitlines() if line]


def inspect_neutral_ax(helper, edge_pid, product_pid, app, title, window, edge_birth, product_birth, url):
    # Independent read-only measurement. AX cannot supply the browser's actual tab identifier.
    try:
        result = command(helper, "neutralAX", edge_pid, product_pid, app, title, 0, window, edge_birth,
                         product_birth, url, check=False, timeout=8)
    except subprocess.TimeoutExpired:
        return "NATIVE_READ_TIMED_OUT"
    if result.returncode in (10, 11, 12, 13):
        return "ORIGINAL_PROCESS_UNAVAILABLE"
    result.check_returncode()
    outcome = result.stdout.decode().strip()
    if outcome not in {"ORIGINAL_AX_DOCUMENT_EDITOR_TEXT_RANGE", "permission", "process", "window",
                       "document", "editor", "selection", "budget", "address", "AX_ATTRIBUTES_UNAVAILABLE"}:
        raise RuntimeError("invalid_neutral_ax_observation")
    return outcome


def original_mouse_refusals(evidence, sent):
    selections = [r for r in evidence if r.get("event") == "selection_boundary"]
    refusals = [r for r in evidence if r.get("event") == "click_input_refused"]
    if not sent or len(selections) != len(sent) or len(refusals) != len(sent):
        return False
    session = selections[0].get("diagnosticSessionDigest")
    if not session or len({r.get("eventNumber") for r in selections}) != len(sent):
        return False
    last_sequence = -1
    for (asset, window, tag), click, refusal in zip(sent, selections, refusals):
        if not (click.get("source") == "mouse" and click.get("targetRequested") is True
                and click.get("assetIDDigest") == refusal.get("assetIDDigest") == asset
                and click.get("windowNumber") == window and click.get("clickCount") == 1
                and type(click.get("eventNumber")) is int and click.get("mouseProbeTag") == tag
                and click.get("diagnosticSessionDigest") == refusal.get("diagnosticSessionDigest") == session
                and last_sequence < click["diagnosticSequence"] < refusal["diagnosticSequence"]
                and refusal.get("phase") == "resolveSelection" and refusal.get("error") == "browserNotFrontmost"
                and refusal.get("critical") is True):
            return False
        last_sequence = refusal["diagnosticSequence"]
    return True


def picker_after_mouse_safe(report, sent, evidence):
    completed = len(sent)
    if completed != report["pressAttempts"] or completed != report["confirmedDistinctRefusals"]:
        return False
    if any(row.get("event") == "click_target_resolved" for row in evidence):
        return False
    if completed:
        if not original_mouse_refusals(evidence, sent):
            return False
    elif any(row.get("event") in ("selection_boundary", "click_input_refused") for row in evidence):
        return False
    if any(r.get("action") != "ONE_GLOBAL_MOUSE_DOWN_UP_POSTED"
           or r.get("retained") != "BOTH_ORIGINAL_ASSETS_VISIBLE_PENDING" for r in report["rounds"][:completed]):
        return False
    remaining = report["rounds"][completed:]
    if report["result"] == "VERIFIED_TWO_APP_REJECTIONS_CONTROLLED_EDGE":
        return completed == 2 and not remaining and report["mouseDispatchCalls"] == completed
    if completed > 1 or len(remaining) != 1:
        return False
    last = remaining[0].get("action")
    return ((report["result"] == "PARTIAL_NATIVE_THUMBNAIL_MOUSE_TARGET_UNVERIFIED"
             and last == "NOT_RUN" and report["mouseDispatchCalls"] == completed) or
            (report["result"] == "PARTIAL_NATIVE_MOUSE_TARGET_CHANGED_BEFORE_DOWN"
             and last == "VETO_BEFORE_MOUSE_DOWN" and report["mouseDispatchCalls"] == completed + 1))


class Draft:
    """Only neutral localhost content. No external resources and no message action."""
    def __init__(self, title):
        self.title = title
        self.phase = 0
        self.observed = set()
        self.file_changes = 0
        self.post_requests = 0
        self.document_requests = 0
        self.picker_enabled = False
        self.picker_events = []
        self.picker_reply = secrets.token_hex(16)
        self.lock = threading.Lock()

    def handler(self):
        draft = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *unused):
                pass

            def reply(self, status, body=b"", mime="text/plain"):
                self.send_response(status)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                prefix = "/" + draft.title
                if self.path == prefix:
                    with draft.lock:
                        draft.document_requests += 1
                        first_document = draft.document_requests == 1
                    if not first_document:
                        self.reply(410)
                        return
                    html = """<!doctype html><meta charset=utf-8><title>TITLE</title>
                    <main><textarea id="riftlet-neutral-editor">Neutral unsent draft</textarea><img id="riftlet-neutral-prior" alt="Neutral prior attachment" width=16 height=16
                    src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==">
                    <button type=button id="riftlet-neutral-attachment" onclick="this.nextElementSibling.click()">Attach PNG</button>
                    <input type=file hidden></main><script>
                    const field=document.querySelector('textarea'), prior=document.querySelector('img'),
                    priorSource=prior.src, input=document.querySelector('input');
                    field.setSelectionRange(2,7); const ping=s=>fetch(location.pathname+'/'+s);
                    input.onchange=async()=>{
                      await ping('change');
                      const original=input.files.length===1 && input.files[0].name==='neutral.png';
                      if(!original || (await(await ping('picker-enabled')).text())!=='yes') return;
                      const resp=await fetch(location.pathname+'/picker-file',{method:'POST',body:input.files[0]});
                      if(resp.status!==201) return;
                      const ticket=await resp.text();
                      if(field.value==='Neutral unsent draft' && field.selectionStart===2 && field.selectionEnd===7 &&
                         document.querySelector('textarea')===field && document.querySelector('img')===prior &&
                         prior.src===priorSource && prior.complete && document.querySelectorAll('img').length===1 &&
                         document.querySelector('input')===input && input.files.length===1) {
                         const image=new Image(); image.src=URL.createObjectURL(input.files[0]); await image.decode();
                         document.querySelector('main').append(image);
                         if(image.isConnected && image.naturalWidth===1 && image.naturalHeight===1) await ping('picker-ack/'+ticket);
                      }
                    };
                    let old=-1; async function report(){try{const n=+(await(await ping('phase')).text());
                    if(n!==old){old=n;document.body.style.background=['#93bfd1','#f6e3a2','#98c7ac','#d8e9b9','#a4c6db'][n];
                    await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
                    const ok=field.value==='Neutral unsent draft'&&field.selectionStart===2&&field.selectionEnd===7&&
                       document.querySelector('textarea')===field&&document.querySelectorAll('img').length===1&&
                       document.querySelector('img')===prior&&prior.src===priorSource&&prior.complete&&prior.naturalWidth===1&&
                       document.querySelector('input')===input&&input.files.length===0;
                    if(!ok) old=-1; else await ping('seen/'+n);}}finally{setTimeout(report,120);}}report();
                    </script>""".replace("TITLE", draft.title)
                    self.reply(200, html.encode(), "text/html")
                elif self.path == prefix + "/picker-enabled":
                    self.reply(200, b"yes" if draft.picker_enabled else b"no")
                elif self.path == prefix + "/picker-ack/" + draft.picker_reply and draft.picker_enabled:
                    with draft.lock:
                        draft.picker_events.append("originalDraftAcknowledged")
                    self.reply(200)
                elif self.path == prefix + "/phase":
                    self.reply(200, str(draft.phase).encode())
                elif self.path in [prefix + "/seen/" + str(i) for i in range(5)]:
                    draft.observed.add(int(self.path[-1]))
                    self.reply(200)
                elif self.path == prefix + "/change":
                    draft.file_changes += 1
                    self.reply(200)
                else:
                    self.reply(404)

            def do_POST(self):
                draft.post_requests += 1
                if (not draft.picker_enabled or self.path != "/" + draft.title + "/picker-file"
                        or self.headers.get("Content-Type") != "image/png"
                        or self.headers.get("Content-Length") != str(len(PIXEL))):
                    self.reply(405)
                    return
                self.connection.settimeout(3)
                with draft.lock:
                    if draft.picker_events or self.rfile.read(1) != PIXEL[:1]:
                        draft.picker_events.append("unexpectedOrDuplicate")
                        self.reply(400)
                        return
                    draft.picker_events.append("firstBodyByte")
                    if self.rfile.read(len(PIXEL) - 1) != PIXEL[1:]:
                        draft.picker_events.append("wrongCompleteBody")
                        self.reply(400)
                        return
                    draft.picker_events.append("exactCompleteBody")
                self.reply(201, draft.picker_reply.encode())
        return Handler


def read_assets(dbfile):
    if not dbfile.exists():
        return {}
    with sqlite3.connect(dbfile.as_uri() + "?mode=ro", uri=True) as db:
        result = {}
        for ident, name, status, visibility, image in db.execute("SELECT id,file_name,status,visibility,image_json FROM assets"):
            image = json.loads(image)
            if Path(name).name != name or image["origin"] != "systemScreenshot" or image["sha256"] in result:
                raise RuntimeError("unexpected_asset")
            result[image["sha256"]] = (ident, name, status, visibility)
        return result


def exercise(app, report):
    temp_root = os.environ.get("RUNNER_TEMP")
    if (sys.platform != "darwin" or os.getenv("GITHUB_ACTIONS") != "true"
            or os.getenv("RUNNER_ENVIRONMENT") != "github-hosted"
            or os.getenv("GITHUB_REPOSITORY") != "haohongfei2001-png/Riftlet" or not temp_root
            or os.getuid() == 0 or os.stat("/dev/console").st_uid != os.getuid()):
        report["result"] = "NOT_RUN_HOSTED_CONSOLE_REQUIRED"
        return 77
    if os.path.lexists(ROOT) or command("defaults", "read", "com.riftlet.app", check=False).returncode == 0:
        report["result"] = "NOT_RUN_ACCOUNT_ALREADY_HAS_PRODUCT_STATE"
        return 77
    if not EDGE.is_dir():
        report["result"] = "NOT_RUN_EDGE_NOT_INSTALLED"
        return 77
    if (REPO / "build/Riftlet.app").is_symlink() or app != (REPO / "build/Riftlet.app").resolve() or not app.is_dir():
        raise RuntimeError("ordinary_package_missing")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.riftlet.app" or info.get("RiftletBuildChannel") != "development":
        raise RuntimeError("wrong_ordinary_product")
    binary = app / "Contents/MacOS/Riftlet"
    report["productExecutableSHA256"] = digest(binary)
    report["version"] = info["CFBundleShortVersionString"]
    report["build"] = info["CFBundleVersion"]
    report["testedMerge"] = os.environ.get("GITHUB_SHA")
    report["stage"] = "passive_preflight"
    with tempfile.TemporaryDirectory(prefix="riftlet-edge-host-", dir=temp_root) as directory, ExitStack() as cleanup:
        root = Path(directory).resolve()
        helper = root / "ui"
        main_source = root / "main.swift"
        main_source.write_bytes((HERE / "EdgeHostUI.swift").read_bytes())
        adapters = REPO / "Sources/RiftletAdapters"
        command("swiftc", main_source, *(adapters / (name + ".swift") for name in AX_HOST_SOURCES),
                "-o", helper, timeout=120)
        check = command(helper, "preflight", check=False)
        if check.returncode == 77:
            reason = check.stdout.decode().strip()
            if reason not in {"SCREEN_CAPTURE_PERMISSION_UNAVAILABLE", "AN_EXISTING_HOST_IS_RUNNING"}:
                raise RuntimeError("unclassified_platform_refusal")
            report["result"] = "NOT_RUN_" + reason
            return 77
        check.check_returncode()
        source = root / "system-source"
        source.mkdir()
        report["stage"] = "ordinary_app_startup"
        previous = command("defaults", "read", "com.apple.screencapture", "location", check=False)
        if previous.returncode == 0:
            cleanup.callback(command, "defaults", "write", "com.apple.screencapture", "location",
                             "-string", previous.stdout.decode().rstrip("\n"))
        else:
            cleanup.callback(command, "defaults", "delete", "com.apple.screencapture", "location")
        command("defaults", "write", "com.apple.screencapture", "location", "-string", source)
        # Ordinary LaunchServices entry. This flag only enables the existing bounded diagnostics.
        command("/usr/bin/open", "-n", "-g", app, "--args", "--acceptance-trace", "--acceptance-hit-map")
        def product_identity():
            result = command(helper, "productPID", app, check=False)
            if result.returncode == 2:
                return None
            result.check_returncode()
            if not re.fullmatch(rb"[1-9]\d* [1-9]\d*:[0-9]{1,6}\s*", result.stdout):
                raise RuntimeError("invalid_product_kernel_identity")
            return tuple(result.stdout.decode().split())
        product, product_birth = wait_for(product_identity, "ordinary_bundle_launch_unconfirmed")
        def quit_product():
            if product_identity() == (product, product_birth):
                command(helper, "quitProduct", app, product_birth)
                wait_for(lambda: product_identity() is None, "product_exit_unconfirmed")
        cleanup.callback(quit_product)
        recent = ROOT / "diagnostics/acceptance-recent.jsonl"
        wait_for(lambda: command("lsof", "-nP", "-a", "-p", product, "-Ffn", source, check=False).returncode == 0,
                 "ordinary_capture_watcher_unavailable", 25)
        report["appWatcherReady"] = True
        title = "RiftletNeutral" + uuid.uuid4().hex
        draft = Draft(title)
        server = cleanup.enter_context(ThreadingHTTPServer(("127.0.0.1", 0), draft.handler()))
        with ExitStack() as session:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            session.callback(server.shutdown)
            url = f"http://127.0.0.1:{server.server_port}/{title}"
            report["stage"] = "edge_normal_tab_launch"
            profile = root / "edge"
            edge_info = plistlib.loads((EDGE / "Contents/Info.plist").read_bytes())
            executable = EDGE / "Contents/MacOS/Microsoft Edge"
            if (root.parent != Path(temp_root).resolve() or not root.name.startswith("riftlet-edge-host-")
                    or os.path.lexists(profile) or edge_info.get("CFBundleIdentifier") != "com.microsoft.edgemac"
                    or edge_info.get("CFBundleExecutable") != executable.name or not executable.is_file()
                    or not re.fullmatch(r"http://127\.0\.0\.1:[0-9]+/RiftletNeutral[a-f0-9]{32}", url)):
                raise RuntimeError("invalid_isolated_edge_launch")
            vacant = command(helper, "edgeVacant", check=False)
            if vacant.returncode == 18:
                report["result"] = "PARTIAL_EDGE_ALREADY_RUNNING_BEFORE_LAUNCH"
                return 0
            vacant.check_returncode()
            edge = subprocess.Popen([executable, "--user-data-dir=" + str(profile), "--disable-extensions", "--no-first-run",
                "--no-default-browser-check", "--disable-background-networking", "--disable-sync", "--no-proxy-server",
                "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1", url],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            session.callback(stop_edge_group, edge)
            edge_pid = edge.pid
            report["edgeLaunch"] = "OWN_NORMAL_TAB_CHILD_CREATED"
            def await_child(fact, timeout_reason):
                deadline = time.monotonic() + 16
                while time.monotonic() < deadline:
                    code = edge.poll()
                    if code is not None:
                        report.update(result="PARTIAL_OWN_EDGE_CHILD_EXITED", edgeChildExit=code)
                        return None
                    result = fact()
                    if result:
                        return result
                    time.sleep(0.15)
                report["result"] = timeout_reason
                return None
            report["stage"] = "original_edge_document_get"
            if not await_child(lambda: draft.document_requests >= 1, "PARTIAL_OWN_LOOPBACK_DOCUMENT_NOT_REQUESTED"):
                return 0
            if draft.document_requests != 1:
                raise RuntimeError("original_neutral_edge_document_unavailable")
            report["stage"] = "original_edge_process_identity"
            def child_identity():
                probe = command(helper, "edgeIdentity", edge_pid, check=False)
                report["edgeIdentityExit"] = probe.returncode
                state = probe.stdout.decode().strip()
                if probe.returncode == 17 and state in {"KERNEL_BIRTH_UNAVAILABLE", "OWN_CHILD_NOT_REGISTERED",
                        "BUNDLE_ID_NOT_CONFIRMED", "BUNDLE_PATH_NOT_CONFIRMED", "EXECUTABLE_PATH_NOT_CONFIRMED",
                        "CHILD_BIRTH_CHANGED"}:
                    report["edgeIdentityObservation"] = state
                    return None
                probe.check_returncode()
                if not re.fullmatch(r"[1-9]\d*:[0-9]{1,6}", state):
                    raise RuntimeError("invalid_kernel_edge_identity")
                report["edgeIdentityObservation"] = "OWN_PID_BUNDLE_EXECUTABLE_AND_KERNEL_BIRTH_CONFIRMED"
                return state
            edge_birth = await_child(child_identity, "PARTIAL_NATIVE_IDENTITY_OF_OWN_CHILD_UNVERIFIED")
            if not edge_birth:
                return 0
            def ui(action, row=0, expected_window=0, *extra):
                result = command(helper, action, edge_pid, product, app, title, row, expected_window, edge_birth, product_birth, *extra, check=False)
                report["lastNativeAction"] = action
                report["lastNativeExit"] = result.returncode
                failures = {10: "original_edge_process_exited", 11: "original_edge_identity_changed",
                            12: "original_product_process_exited", 13: "original_product_identity_changed",
                            64: "invalid_helper_arguments"}
                if result.returncode in failures:
                    raise RuntimeError(failures[result.returncode])
                return result
            def selected_window(action="window"):
                value = ui(action)
                if value.returncode in (2, 14):
                    state = value.stdout.decode().strip()
                    if state not in {"EDGE_NOT_FRONTMOST", "WINDOWSERVER_LIST_UNAVAILABLE", "NO_EDGE_NORMAL_WINDOW",
                                     "MULTIPLE_EDGE_NORMAL_WINDOWS", "ORIGINAL_WINDOW_TITLE_UNAVAILABLE",
                                     "NEUTRAL_DOCUMENT_TITLE_NOT_VISIBLE", "WINDOW_NUMBER_UNAVAILABLE"}:
                        raise RuntimeError("unrecognized_window_probe_status")
                    report["lastWindowObservation"] = state
                    return None
                value.check_returncode()
                if not re.fullmatch(rb"[1-9]\d*\s*", value.stdout):
                    raise RuntimeError("invalid_native_window_id")
                return value.stdout.decode().strip()
            report["stage"] = "original_edge_window_identification"
            try:
                window = wait_for(lambda: selected_window("unfocusedWindow"), "original_edge_window_unverified")
            except ObservationTimeout:
                report["result"] = "PARTIAL_UNIQUE_NEUTRAL_EDGE_WINDOW_UNVERIFIED"
                return 0
            report["stage"] = "original_edge_activation"
            activation = ui("activate", expected_window=window)
            report["edgeActivationExit"] = activation.returncode
            if activation.returncode in (15, 16):
                report["result"] = ("PARTIAL_ORIGINAL_EDGE_WINDOW_CHANGED_BEFORE_ACTIVATION" if activation.returncode == 15
                                    else "PARTIAL_NATIVE_EDGE_ACTIVATION_DECLINED")
                return 0
            activation.check_returncode()
            report["edgeActivation"] = activation.stdout.decode().strip()
            if report["edgeActivation"] not in ("ALREADY_FRONTMOST", "REQUEST_ACCEPTED"):
                raise RuntimeError("unrecognized_native_activation_status")
            try:
                wait_for(lambda: selected_window() == window, "original_edge_not_frontmost")
            except ObservationTimeout:
                report["result"] = "PARTIAL_ORIGINAL_EDGE_WINDOW_DID_NOT_BECOME_FRONTMOST"
                return 0
            report["stage"] = "original_visible_document_paint"
            wait_for(lambda: 0 in draft.observed, "original_neutral_frame_unconfirmed")
            report["neutralAX"] = inspect_neutral_ax(helper, edge_pid, product, app, title, window,
                                                     edge_birth, product_birth, url)
            captures = []
            dbfile = ROOT / "queue.sqlite"
            region_mode = False
            for i in (0, 1):
                report["stage"] = f"system_screenshot_{i + 1}"
                if i:
                    draft.phase = i
                    wait_for(lambda: i in draft.observed, "neutral_second_frame_unconfirmed")
                if selected_window() != window:
                    raise RuntimeError("original_edge_window_changed")
                if not region_mode:
                    path = source / f"Neutral-{i}.png"
                    command("/usr/sbin/screencapture", "-x", "-o", "-t", "png", "-l" + window, path)
                    image_hash, marked = system_capture_digest(path)
                    report["generatedScreenshotFiles"] += 1
                    if not marked:
                        # No UI actions have occurred. Continue only while the real collector
                        # still contains precisely the previously verified owned captures.
                        if set(read_assets(dbfile)) != {d for d, _ in captures}:
                            raise RuntimeError("unmarked_input_import_or_unknown_queue_state")
                        report["windowCapturesWithoutMarker"] += 1
                        region_mode = True
                if region_mode:
                    # Apple -p uses the account's capture preferences and ignores filenames.
                    # -R bounds this operation to the unobscured center of the neutral window.
                    report["stage"] = f"default_system_region_{i + 1}"
                    report["result"] = "PARTIAL_SYSTEM_CAPTURE_WITHOUT_OS_SCREENSHOT_MARKER"
                    if not default_file_capture_target(source):
                        report["regionOutcome"] = "FILE_DESTINATION_UNVERIFIED"
                        return 0
                    previous_files = set(source.iterdir())
                    region = ui("region", expected_window=window)
                    if region.returncode == 2:
                        report["regionOutcome"] = "UNOBSCURED_ORIGINAL_EDGE_REGION_UNVERIFIED"
                        return 0
                    region.check_returncode()
                    bounds = region.stdout.decode().strip()
                    if not re.fullmatch(r"-?\d+,-?\d+,128,72", bounds):
                        raise RuntimeError("invalid_region_geometry")
                    report["systemRegionCaptureAttempts"] += 1
                    command("/usr/sbin/screencapture", "-p", "-x", "-t", "png", "-R" + bounds)
                    after = ui("region", expected_window=window)
                    if after.returncode or after.stdout != region.stdout:
                        raise RuntimeError("region_owner_or_visibility_changed")
                    try:
                        path = wait_for(lambda: sole_new_png(source, previous_files), "default_output_not_observed")
                    except ObservationTimeout:
                        report["regionOutcome"] = "NO_UNIQUE_PNG_IN_CONFIGURED_SOURCE"
                        return 0
                    image_hash, marked = system_capture_digest(path)
                    if sole_new_png(source, previous_files) != path:
                        raise RuntimeError("default_capture_output_changed")
                    report["generatedScreenshotFiles"] += 1
                    if not marked:
                        report["regionOutcome"] = "DEFAULT_CAPTURE_ALSO_MISSING_OS_MARKER"
                        return 0
                    report["regionOutcome"] = "DEFAULT_CAPTURE_PNG_WITH_OS_MARKER"
                report["osScreenshotMarkersVerified"] += 1
                captures.append((image_hash, path))
            if captures[0][0] == captures[1][0]:
                raise RuntimeError("two_distinct_captures_unproven")
            def imported():
                items = read_assets(dbfile)
                return items if len(items) == 2 and all(d in items for d, _ in captures) else None
            report["stage"] = "ordinary_import"
            rows = wait_for(imported, "two_capture_imports_unproven", 25)
            asset_digests = [hashlib.sha256(rows[d][0].lower().encode()).hexdigest() for d, _ in captures]
            sent = []
            def finish_with_picker():
                # Only intentional ordinary exits can reach this side probe.
                # A timeout/lost reply after dispatch instead unwinds directly.
                candidate = {"status": "NOT_RUN_ORDINARY_INPUT_UNCERTAIN", "commercialService": "NOT_RUN"}
                report["controlledEdgePicker"] = candidate
                if not picker_after_mouse_safe(report, sent, events(recent)):
                    return 0
                if (edge.poll() is not None or selected_window() != window or draft.document_requests != 1
                        or draft.file_changes or draft.post_requests or draft.picker_enabled or draft.picker_events
                        or read_assets(dbfile) != rows or any(row[2:] != ("pending", "visible") for row in rows.values())):
                    candidate["status"] = "NOT_RUN_ORIGINAL_BASELINE_UNPROVEN"
                    return 0
                with sqlite3.connect(dbfile.as_uri() + "?mode=ro", uri=True) as db:
                    if any(db.execute("SELECT count(*) FROM " + table).fetchone()[0]
                           for table in ("operations", "upload_starts")):
                        candidate["status"] = "NOT_RUN_EXISTING_ORDINARY_OPERATION"
                        return 0
                # Phase 4 has never been requested by either ordinary mouse round.
                # It demands a new original-node/text/selection/prior/empty-input witness.
                if 4 in draft.observed:
                    raise RuntimeError("picker_baseline_generation_reused")
                draft.phase = 4
                try:
                    wait_for(lambda: 4 in draft.observed, "picker_baseline_missing", 3)
                except ObservationTimeout:
                    candidate["status"] = "NOT_RUN_ORIGINAL_BASELINE_UNPROVEN"
                    return 0
                if (selected_window() != window or draft.document_requests != 1 or draft.file_changes
                        or draft.post_requests or edge.poll() is not None):
                    candidate["status"] = "NOT_RUN_ORIGINAL_BASELINE_UNPROVEN"
                    return 0
                draft.picker_enabled = True
                try:
                    candidate = probe_neutral_picker(root, edge_pid, edge_birth, url)
                    report["controlledEdgePicker"] = candidate
                    expected = ["firstBodyByte", "exactCompleteBody", "originalDraftAcknowledged"]
                    if candidate["status"] == "EXACT_FILE_SUBMIT_ATTEMPTED":
                        wait_for(lambda: draft.picker_events == expected, "picker_receipt_unconfirmed", 4)
                        if draft.file_changes != 1 or draft.post_requests != 1 or draft.document_requests != 1:
                            raise RuntimeError("controlled_picker_delivery_count")
                    elif draft.picker_events or draft.file_changes or draft.post_requests:
                        raise RuntimeError("unconfirmed_picker_changed_original_draft")
                    return 0
                except Exception as error:
                    candidate["testError"] = type(error).__name__
                    return 1
                finally:
                    candidate["receiverEvents"] = list(draft.picker_events)
                    draft.picker_enabled = False

            for n, expected_asset in enumerate(asset_digests, 1):
                report["stage"] = f"original_mouse_thumbnail_{n}"
                round_result = dict(captureSequence=n, action="NOT_RUN", rejection="UNCONFIRMED", retained="UNCONFIRMED")
                report["rounds"].append(round_result)
                tag = secrets.randbelow((1 << 48) - 1) + 1
                while any(previous_tag == tag for _, _, previous_tag in sent):
                    tag = secrets.randbelow((1 << 48) - 1) + 1
                def mouse_target(action):
                    result = ui(action, 0, window, expected_asset, tag)
                    state = result.stdout.decode().strip()
                    if result.returncode == 24:
                        if state in {"firstReceiver originalFrontEdge", "firstReceiver otherRiftletWindow",
                                     "firstReceiver none", "firstReceiver other"}:
                            round_result["actualReceiver"] = state.split()[1]
                            state = "firstMouseReceiverMismatch"
                        if state not in {"mapAbsent", "mapUnreadable", "mapNotOwnedRegularFile", "mapInvalidPayload",
                                "mapProcessMismatch", "mapStale", "mapRowsZero", "mapRowsOne", "mapRowsMoreThanTwo",
                                "foregroundChanged", "ambiguousAsset", "overlappingAssets",
                                "invalidGeometry", "ownerUnconfirmed", "eventDeliveryUnconfirmed",
                                "postPermissionUnavailable", "otherInputActive", "targetChangedBeforeDown",
                                "eventAllocationFailed", "firstMouseReceiverMismatch", "observerInitializationUnavailable"}:
                            raise RuntimeError("unknown_mouse_probe_status")
                        round_result["preflight"] = state
                        return None
                    result.check_returncode()
                    if not re.fullmatch(r"[12] [1-9]\d*", state):
                        raise RuntimeError("invalid_mouse_window_receipt")
                    round_result.update(preflight="verified", actualReceiver="originalRiftletInput")
                    return tuple(map(int, state.split()))
                try:
                    wait_for(lambda: mouse_target("mouseReady"), "mapped_target_not_demonstrated")
                except ObservationTimeout:
                    report["result"] = "PARTIAL_NATIVE_THUMBNAIL_MOUSE_TARGET_UNVERIFIED"
                    return finish_with_picker()
                # Exactly one call may post down/up per asset. Missing replies never permit another call.
                round_result["action"] = "DISPATCH_ENTERED"
                report["mouseDispatchCalls"] += 1
                response = mouse_target("mouseClick")
                if response is None:
                    round_result["action"] = "VETO_BEFORE_MOUSE_DOWN"
                    report["result"] = "PARTIAL_NATIVE_MOUSE_TARGET_CHANGED_BEFORE_DOWN"
                    return finish_with_picker()
                ordinal, expected_input_window = response
                sent.append((expected_asset, expected_input_window, tag))
                report["pressAttempts"] += 1
                round_result.update(ordinal=ordinal, action="ONE_GLOBAL_MOUSE_DOWN_UP_POSTED")
                wait_for(lambda: original_mouse_refusals(events(recent), sent), "original_mouse_selection_or_refusal_unconfirmed")
                if selected_window() != window:
                    raise RuntimeError("original_edge_changed_after_mouse_receipt")
                round_result["mouseProbeTagMatched"] = True
                round_result["originalEdgeWindowAfterReceipt"] = True
                report["confirmedDistinctRefusals"] = n
                round_result["rejection"] = "ORIGINAL_MOUSE_WINDOW_AND_ASSET_PRODUCT_REFUSAL"
                draft.phase = n + 1
                wait_for(lambda: draft.phase in draft.observed, "original_neutral_document_state_unconfirmed")
                if draft.document_requests != 1 or draft.file_changes or draft.post_requests:
                    raise RuntimeError("neutral_document_replaced_or_changed")
                after_round = read_assets(dbfile)
                if after_round != rows or any(v[2:] != ("pending", "visible") for v in after_round.values()):
                    raise RuntimeError("two_original_rows_not_retained")
                round_result.update(retained="BOTH_ORIGINAL_ASSETS_VISIBLE_PENDING",
                                    originalNeutralTextSelectionAndPriorImage=True)
            after = read_assets(dbfile)
            if len(rows) != 2 or rows != after or {v[2:] for v in after.values()} != {("pending", "visible")}:
                raise RuntimeError("two_original_rows_not_retained")
            for d, path in captures:
                if digest(path) != d or digest(ROOT / "media" / after[d][1]) != d:
                    raise RuntimeError("original_image_bytes_changed")
            with sqlite3.connect(dbfile.as_uri() + "?mode=ro", uri=True) as db:
                counts = {table: db.execute("SELECT count(*) FROM " + table).fetchone()[0]
                          for table in ("operations", "upload_starts")}
            if draft.document_requests != 1 or any(counts.values()) or draft.file_changes or draft.post_requests or selected_window() != window:
                raise RuntimeError("unexpected_file_action_or_target_change")
            report.update(result="VERIFIED_TWO_APP_REJECTIONS_CONTROLLED_EDGE", retainedVisibleAssets=2,
                          originalPrivateSHA256Matches=2, operations=counts["operations"], starts=counts["upload_starts"],
                          fixtureFileChanges=draft.file_changes, fixturePostRequests=draft.post_requests,
                          neutralTextSelectionAndPriorImageRetained=True, fixtureDocumentGETs=draft.document_requests,
                          stage="complete")
            return finish_with_picker()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    report = dict(scope="ordinary-packaged-app-native-mouse-edge-loopback", commercialService="NOT_RUN",
                  physicalClicks=False, rounds=[], generatedScreenshotFiles=0, osScreenshotMarkersVerified=0,
                  controlledEdgePicker={"status": "NOT_RUN_NO_SAFE_ORDINARY_EXIT", "commercialService": "NOT_RUN"},
                  neutralAX="NOT_RUN", appleEventsTabIdentity="NOT_MEASURED_IN_MOUSE_PROBE",
                  windowCapturesWithoutMarker=0, systemRegionCaptureAttempts=0, mouseDispatchCalls=0,
                  pressAttempts=0, confirmedDistinctRefusals=0)
    try:
        code = exercise(args.app.resolve(), report)
    except Exception as error:
        # Never include browser URLs, traces with local paths, or image data in the output artifact.
        reason = str(error) if isinstance(error, RuntimeError) and re.fullmatch(r"[a-z_]+", str(error)) else type(error).__name__
        if isinstance(error, subprocess.CalledProcessError):
            report["upstreamExit"] = error.returncode
        report.update(result="FAILED_CONTROLLED_CHECK", reason=reason)
        code = 1
    print(json.dumps(report, sort_keys=True))
    sys.exit(code)
