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
import sqlite3
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
EDGE = Path("/Applications/Microsoft Edge.app")
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


def events(path):
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_bytes().splitlines() if line]


class Draft:
    """Only neutral localhost content. No external resources and no message action."""
    def __init__(self, title):
        self.title = title
        self.phase = 0
        self.observed = set()
        self.file_changes = 0
        self.post_requests = 0
        self.document_requests = 0
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
                    <main><textarea>Neutral unsent draft</textarea><img width=16 height=16
                    src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==">
                    <input type=file></main><script>
                    const field=document.querySelector('textarea'), prior=document.querySelector('img'),
                    priorSource=prior.src, input=document.querySelector('input');
                    field.setSelectionRange(2,7); const ping=s=>fetch(location.pathname+'/'+s);
                    input.onchange=()=>ping('change');
                    let old=-1; async function report(){try{const n=+(await(await ping('phase')).text());
                    if(n!==old){old=n;document.body.style.background=['#93bfd1','#f6e3a2','#98c7ac','#d8e9b9'][n];
                    await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
                    const ok=field.value==='Neutral unsent draft'&&field.selectionStart===2&&field.selectionEnd===7&&
                       document.querySelector('textarea')===field&&document.querySelectorAll('img').length===1&&
                       document.querySelector('img')===prior&&prior.src===priorSource&&prior.complete&&prior.naturalWidth===1&&
                       document.querySelector('input')===input&&input.files.length===0;
                    if(!ok) old=-1; else await ping('seen/'+n);}}finally{setTimeout(report,120);}}report();
                    </script>""".replace("TITLE", draft.title)
                    self.reply(200, html.encode(), "text/html")
                elif self.path == prefix + "/phase":
                    self.reply(200, str(draft.phase).encode())
                elif self.path in [prefix + "/seen/" + str(i) for i in range(4)]:
                    draft.observed.add(int(self.path[-1]))
                    self.reply(200)
                elif self.path == prefix + "/change":
                    draft.file_changes += 1
                    self.reply(200)
                else:
                    self.reply(404)

            def do_POST(self):
                draft.post_requests += 1
                self.reply(405)
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
        command("swiftc", HERE / "EdgeHostUI.swift", "-o", helper, timeout=120)
        check = command(helper, "preflight", check=False)
        if check.returncode == 77:
            reason = check.stdout.decode().strip()
            if reason not in {"MISSING_EXISTING_AX_OR_SCREEN_PERMISSION", "AN_EXISTING_HOST_IS_RUNNING"}:
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
        command("/usr/bin/open", "-n", "-g", app, "--args", "--acceptance-trace")
        def product_pid():
            result = command(helper, "productPID", app, check=False)
            return int(result.stdout) if result.returncode == 0 else None
        product = wait_for(product_pid, "ordinary_bundle_launch_unconfirmed")
        def quit_product():
            if product_pid() == product:
                command(helper, "quitProduct", app)
                wait_for(lambda: product_pid() is None, "product_exit_unconfirmed")
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
            report["stage"] = "edge_launchservices"
            launched = command(helper, "launchEdge", root / "edge", url, check=False, timeout=22)
            report["edgeLaunchExit"] = launched.returncode
            if launched.returncode == 19:
                if re.fullmatch(rb"-?\d+\s*", launched.stdout):
                    report["launchServicesErrorCode"] = int(launched.stdout)
                report["result"] = "PARTIAL_EDGE_LAUNCHSERVICES_ERROR"
                return 0
            if launched.returncode == 21:
                report["result"] = "PARTIAL_EDGE_LAUNCHSERVICES_REPLY_TIMEOUT"
                return 0
            if launched.returncode != 0:
                raise RuntimeError({18: "edge_launch_isolation_unconfirmed", 20: "launched_edge_identity_mismatch",
                                    64: "invalid_helper_arguments"}.get(launched.returncode, "edge_native_launch_failed"))
            if not re.fullmatch(rb"[1-9]\d* [1-9]\d*\s*", launched.stdout):
                raise RuntimeError("invalid_native_edge_launch_identity")
            edge_pid, edge_birth = launched.stdout.decode().split()
            session.callback(command, helper, "quitEdge", edge_pid, edge_birth)
            def ui(action, row=0, expected_window=0):
                result = command(helper, action, edge_pid, product, app, title, row, expected_window, edge_birth, check=False)
                report["lastNativeAction"] = action
                report["lastNativeExit"] = result.returncode
                failures = {10: "original_edge_process_exited", 11: "original_edge_identity_changed",
                            12: "original_product_process_exited", 13: "original_product_identity_changed",
                            64: "invalid_helper_arguments"}
                if result.returncode in failures:
                    raise RuntimeError(failures[result.returncode])
                return result
            report["stage"] = "original_edge_document_get"
            wait_for(lambda: draft.document_requests >= 1, "neutral_document_get_unobserved")
            if draft.document_requests != 1:
                raise RuntimeError("original_neutral_edge_document_unavailable")
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
            asset_digests = {hashlib.sha256(v[0].lower().encode()).hexdigest() for v in rows.values()}
            def present(n):
                value = ui("ready", n, window)
                if value.returncode in (0, 5):
                    return "ready" if value.returncode == 0 else "action_unavailable"
                if value.returncode != 2:
                    raise RuntimeError("native_row_probe_failed")
                return None
            def facts():
                evidence = events(recent)
                clicked = [r for r in evidence if r.get("event") == "selection_boundary"
                           and r.get("source") == "accessibility" and r.get("targetRequested") is True]
                refused = [r for r in evidence if r.get("event") == "click_input_refused"
                           and r.get("error") == "browserNotFrontmost" and r.get("phase") == "resolveSelection"]
                return clicked, refused
            for n in (1, 2):
                report["stage"] = f"original_thumbnail_{n}"
                round_result = dict(ordinal=n, action="NOT_RUN", rejection="UNCONFIRMED", retained="UNCONFIRMED")
                report["rounds"].append(round_result)
                try:
                    capability = wait_for(lambda: present(n), "exact_thumbnail_not_accessible")
                except ObservationTimeout:
                    if selected_window() != window:
                        raise RuntimeError("original_edge_window_changed")
                    report["result"] = "PARTIAL_PRODUCT_ROW_NOT_EXPOSED_TO_AX"
                    return 0
                if capability == "action_unavailable":
                    report["result"] = "PARTIAL_PRODUCT_ROW_LACKS_PUBLISHED_AXPRESS"
                    return 0
                if selected_window() != window:
                    raise RuntimeError("original_edge_window_changed")
                report["pressAttempts"] += 1
                round_result["action"] = "REQUESTED_ONCE"
                result = ui("press", n, window)
                if result.returncode:
                    raise RuntimeError({2: "original_target_no_longer_available", 3: "axpress_reply_uncertain",
                                        4: "foreground_changed_after_axpress"}.get(result.returncode, "ui_action_failed"))
                def current_result():
                    clicked, refused = facts()
                    ids = [r["assetIDDigest"] for r in clicked]
                    return (len(clicked) == len(refused) == n and len(set(ids)) == n and set(ids) <= asset_digests
                            and all(c["assetIDDigest"] == r["assetIDDigest"] and
                                    c["diagnosticSessionDigest"] == r["diagnosticSessionDigest"] and
                                    c["diagnosticSequence"] < r["diagnosticSequence"] and r.get("critical") is True
                                    for c, r in zip(clicked, refused)))
                wait_for(current_result, "selection_or_original_refusal_unconfirmed")
                report["confirmedDistinctRefusals"] = n
                round_result["rejection"] = "MATCHING_PRODUCT_REFUSAL"
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
            return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    report = dict(scope="ordinary-packaged-app-accessibility-press-edge-loopback", commercialService="NOT_RUN",
                  physicalClicks=False, rounds=[], generatedScreenshotFiles=0, osScreenshotMarkersVerified=0,
                  windowCapturesWithoutMarker=0, systemRegionCaptureAttempts=0,
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
