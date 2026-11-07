#!/usr/bin/env python3
"""Read-only document/source checks; no App, browser, network or user-data access."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[3]
PACKET = Path(__file__).resolve().parent
GUIDES = ROOT / "docs/consumer"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write a new JSON result; refuse overwrite")
    args = parser.parse_args()
    binding_path = PACKET / "source-bindings.json"
    binding = json.loads(binding_path.read_text(encoding="utf-8"))
    checks = []

    def check(name: str, ok: bool, detail: str) -> None:
        checks.append({"check": name, "result": "PASS" if ok else "FAIL", "detail": detail})

    for item in binding["files"]:
        path = ROOT / item["path"]
        check("source:" + item["path"], path.is_file() and not path.is_symlink()
              and sha(path) == item["sha256"], "Exact bytes of audited source")

    required = {
        "README.md", "QUICK-START.zh-CN.md", "QUICK-START.en.md",
        "INSTALL-AND-PERMISSIONS.md", "SUPPORT-MATRIX.md", "PRIVACY.md",
        "RECOVERY-AND-FAQ.md", "FEEDBACK-TEMPLATE.md",
    }
    check("guide-set", {p.name for p in GUIDES.glob("*.md")} == required,
          "Eight explicit consumer guides present")
    documents = sorted([*GUIDES.glob("*.md"), *PACKET.glob("*.md")])
    texts = {}
    for path in documents:
        text = path.read_text(encoding="utf-8", errors="strict")
        texts[path.name] = text
        relative = path.relative_to(ROOT).as_posix()
        check("privacy:" + relative, not re.search(
            r"/Users/|riftlet-private|Library/Application Support/Riftlet-Settings-Review-|"
            r"Bearer [A-Za-z0-9_-]{12,}|[A-Z0-9._%+-]+@(?:example\.com|example\.org)",
            text, re.IGNORECASE), "No real-home/private-evidence paths, bearer strings or placeholder contacts")
        links = re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", text)
        for target in links:
            target = target.strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith("#"):
                continue
            destination = (path.parent / unquote(parsed.path)).resolve()
            ok = destination.is_relative_to(ROOT) and destination.is_file()
            check("link:" + relative + " -> " + target, ok, "Local linked file exists within repository")

    required_copy = {
        "QUICK-START.zh-CN.md": ["START", "不是", "结果待核实"],
        "QUICK-START.en.md": ["START", "does not certify", "unconfirmed"],
        "INSTALL-AND-PERMISSIONS.md": ["ad-hoc", "Gatekeeper", "Apple Events", "待批准"],
        "PRIVACY.md": ["后台", "不会自动识别并删除其中的隐私"],
        "RECOVERY-AND-FAQ.md": ["UNKNOWN", "完整", "不删除", "卸载"],
        "CLOSED-BETA-PLAN.md": ["10–20", "0 邀请", "分母", "unknown", "PUBLIC_BETA_BLOCKED_OWNER_CREDENTIALS"],
        "START-SEMANTICS-AUDIT.md": ["BLOCKED_TOOL_POLICY", "attachmentAccepted", "currentFileInputs"],
    }
    # These guard against accidental omission; source review, not word presence,
    # establishes meaning. A PASS is not usability, runtime or legal approval.
    for name, phrases in required_copy.items():
        check("scope-copy:" + name, all(s in texts.get(name, "") for s in phrases),
              "Required scope/remediation language retained")

    failed = [x for x in checks if x["result"] != "PASS"]
    report = {
        "schemaVersion": 1,
        "result": "PASS_DOCUMENT_CHECKS" if not failed else "FAIL_DOCUMENT_CHECKS",
        "sourceBaseline": binding["sourceBaseline"],
        "scope": "Author checks of local links, source bytes and explicit scope wording only",
        "runtimeTests": "NOT_RUN",
        "liveChatGPT": "BLOCKED_TOOL_POLICY",
        "invitationsSent": 0,
        "networkOrProductionActions": False,
        "independentReview": "PENDING",
        "checks": checks,
        "summary": {"checks": len(checks), "passed": len(checks) - len(failed), "failed": len(failed)},
        "sourceBindingSHA256": sha(binding_path),
        "checkerSHA256": sha(Path(__file__).resolve()),
        "documents": [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p)} for p in documents],
    }
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        with args.output.open("x", encoding="utf-8") as destination:
            destination.write(encoded)
    print(encoded, end="")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
