"""One controlled native Edge attempt in the already-owned ordinary test session."""
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess

# This publicly generated 1x1 pixel is the only file the CLI accepts.
PIXEL = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNI6ZgJAALZAYa2S+pDAAAAAElFTkSuQmCC")
SOURCES = ("NativeMacAXDriver", "ChromeProcessIdentity", "ApplicationHostAdapter", "ChromeActiveTabDescriptor",
           "EdgeApplicationHost", "ConversationSurfaceAdapter", "EdgeNativeDraftProbe", "AXPickerInspection",
           "AttachmentTransport", "AXPickerFileHandoff", "NativePickerVerifiedFile", "EdgeOwnedFilePanel",
           "EdgeConversationPicker")


def probe_neutral_picker(root, edge_pid, edge_birth, url):
    root = Path(root).resolve()
    if (os.getenv("GITHUB_ACTIONS") != "true" or os.getenv("RUNNER_ENVIRONMENT") != "github-hosted"
            or os.getenv("GITHUB_REPOSITORY") != "haohongfei2001-png/Riftlet" or not os.getenv("RUNNER_TEMP")
            or os.getuid() == 0 or os.stat("/dev/console").st_uid != os.getuid()
            or root.parent != Path(os.environ["RUNNER_TEMP"]).resolve() or not root.name.startswith("riftlet-edge-host-")
            or not re.fullmatch(r"http://127\.0\.0\.1:[0-9]+/RiftletNeutral[a-f0-9]{32}", url)):
        return {"status": "NOT_RUN_NO_DISPOSABLE_CONSOLE", "commercialService": "NOT_RUN"}
    here = Path(__file__).resolve().parent
    adapters = here.parents[1] / "Sources/RiftletAdapters"
    directory = root / "picker-images"
    directory.mkdir(mode=0o700)
    file = directory / "neutral.png"
    with file.open("xb") as stream:
        stream.write(PIXEL)
    binary = root / "owned-edge-picker"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-D", "RIFTLET_CONTROLLED_EDGE",
                    *[str(adapters / (s + ".swift")) for s in SOURCES],
                    str(here / "EdgeNeutralPickerCLI.swift"), "-o", binary], check=True, timeout=120)
    result = subprocess.run([str(binary), str(edge_pid), str(edge_birth), url, str(file)],
                            check=True, timeout=25, capture_output=True, text=True)
    state = result.stdout.strip()
    known = {"REFUSED_BEFORE_ENTRY", "ENTRY_ATTEMPTED_NO_FILE_CONFIRMATION", "EXACT_FILE_SUBMIT_ATTEMPTED",
             "ORIGINAL_ACTION_UNKNOWN", "ORIGINAL_INPUT_INTENT_EXISTS", "NATIVE_EDGE_TARGET_CHANGED", "NATIVE_EDGE_NOT_FRONTMOST",
             "NATIVE_EDGE_DESCRIPTOR_UNAVAILABLE", "NATIVE_DRAFT_CHANGED_OR_UNPROVEN"}
    if state not in known and not (re.fullmatch(r"(?:EDGE_AUTOMATION_OSSTATUS|NATIVE_PREFLIGHT_AXERROR)_-?\d+", state)
                                   or re.fullmatch(r"NATIVE_AX_UNAVAILABLE_(permission|process|window|document|editor|selection|budget|address)", state)):
        raise RuntimeError("unrecognized_controlled_edge_picker_result")
    return {"status": state, "commercialService": "NOT_RUN", "scope": "owned-loopback-edge-native-tab-and-ax-picker",
            "expectedPNG_SHA256": hashlib.sha256(PIXEL).hexdigest()}
