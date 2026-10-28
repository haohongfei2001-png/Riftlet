#!/usr/bin/env python3
"""Exact reviewed delta on the fixed Quiet Edge source; no admission overrides.

Reuse the existing audited composition implementation from its immutable Git
blob. Its historical invocation still runs the complete original Quiet Edge
gate on 443d21d, which in turn runs the original Beta, entry and arrival gates.
Only the three exact metadata paths below may change after source review.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import types

BASELINE = "443d21da1a55c0061eafced823b5406879b96024"
ENGINE_BLOB = "eff1187ef5a46797266cd6aa69e383dfdf4e3a60"
ENGINE_PATH = "scripts/verify-thin-edge-composition.py"
GATE_PATH = "scripts/verify-builtin-capture-composition.py"
METADATA_PATHS = frozenset((
    GATE_PATH,
    "docs/BUILTIN_CAPTURE_HANDOFF_2026-10-29.md",
    "engineering/evidence/2026-10-29-builtin-capture/results.json",
))
REVIEWED_SOURCE = None  # Set only after the independent review + source commit.


def load_engine():
    repository = Path(__file__).resolve().parents[1]
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = os.devnull
    source = subprocess.check_output(
        ["git", "--no-replace-objects", "-C", str(repository), "cat-file", "blob", ENGINE_BLOB],
        env=environment, stderr=subprocess.PIPE)
    module = types.ModuleType("riftlet_builtin_pinned_composition")
    module.__file__ = str(repository / ENGINE_PATH)
    sys.modules[module.__name__] = module
    exec(compile(source, module.__file__, "exec"), module.__dict__)
    module.GATE_PATH = GATE_PATH
    module.METADATA_PATHS = METADATA_PATHS
    return module


ENGINE = load_engine()
POLICY = ENGINE.Policy(BASELINE,
    (ENGINE.HistoricalAudit("quiet-edge", BASELINE, ENGINE_PATH, ENGINE_BLOB),), REVIEWED_SOURCE)


def audit(repository, revision="HEAD", policy=POLICY):
    return ENGINE.audit(repository, revision, policy)


def main():
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD")
    parser.add_argument("--repository", type=Path, default=Path("."))
    arguments = parser.parse_args()
    report = audit(arguments.repository, arguments.revision)
    print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
    print("BUILTIN_CAPTURE_COMPOSITION_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
