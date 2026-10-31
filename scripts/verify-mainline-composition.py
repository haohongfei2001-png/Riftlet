#!/usr/bin/env python3
"""Verify explicitly reviewed source on main and actual GitHub PR merges.

The sole post-review exception is one regular JSON admission record. It records
real non-author review; it is not a cryptographic proof of reviewer identity.
Review of this policy/workflows and GitHub branch protection remain necessary.
No CLI or environment option can substitute a source approval pin.
"""

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


ADMISSION_PATH = "engineering/mainline/source-admission.json"
MAX_RECORD_BYTES = 2 * 1024 * 1024
LEGACY_GATE_PATH = "scripts/verify-final-product-composition.py"
HISTORICAL_GATE_PATHS = (
    LEGACY_GATE_PATH,
    "scripts/verify-internal-beta-integration.py",
    "scripts/verify-thin-edge-composition.py",
    "scripts/verify-unified-candidate-composition.py",
    "scripts/verify-builtin-capture-composition.py",
    "scripts/verify-capture-entry-integration.py",
    "scripts/verify-arrival-integration.py",
    "scripts/verify-feedback-isolation.sh",
)
HISTORICAL_PREFIXES = ("engineering/evidence/", "research/")
WEBSITE_PATHS = (
    "CNAME", ".nojekyll", "site.css", "site.js", "robots.txt", "sitemap.xml",
    "favicon.svg", "index.html", "site.webmanifest", "website-assets/error.svg",
    "website-assets/fonts/FONT-SOURCES.json", "website-assets/fonts/Instrument-Serif-OFL.txt",
    "website-assets/fonts/Noto-Serif-SC-OFL.txt", "website-assets/fonts/instrument-serif-italic.woff2",
    "website-assets/fonts/instrument-serif.woff2", "website-assets/fonts/noto-serif-sc.woff2",
    "website-assets/glass-study.png", "website-assets/reading.svg", "website-assets/riftlet.svg",
    "website-hero.css", "website-hero.js", "website-locale.js", "website-product.css",
    "website-product.js", "website-v2.css", "website-v2.js", "website/HERO_REVISION_2026-10-27.md",
    "website/README.md", "website/RELEASE_2026-10-30.md", "website/RESTORE_ART_DIRECTION_2026-10-27.md",
    "website/test-hero-layout.py", "website/test-hero-motion.py", "website/test-hero.py", "website/test-product.cjs",
)
PRODUCTION_BOUNDARY = {
    "ordinaryInput": False, "ordinaryStart": False, "ordinaryCompletion": False,
    "builtInUpload": False, "safeRetry": False, "webContinuation": False,
    "existingRestrictedCandidate": "UNCHANGED_NO_EXPANSION",
}


@dataclass(frozen=True)
class Policy:
    foundation: str
    foundation_tree: str
    foundation_parents: tuple
    legacy_source: str
    legacy_gate_blob: str
    website_source: str
    website_paths: tuple = WEBSITE_PATHS
    historical_gates: tuple = HISTORICAL_GATE_PATHS
    historical_prefixes: tuple = HISTORICAL_PREFIXES


POLICY = Policy(
    foundation="58f894af0f5d9bb0250c1e41750528232696b60c",
    foundation_tree="d7a16bf0d5550c3d54972d6fd4ac7c74133167eb",
    foundation_parents=("fccd809e9d55e0b221e75e6dcd7c21f6d357ee74",
                        "253ac8db92bfba9083d485b71b84c594223da217"),
    legacy_source="253ac8db92bfba9083d485b71b84c594223da217",
    legacy_gate_blob="e0dfa374e45badca36f01d9d6315ce667ee8d43f",
    website_source="fccd809e9d55e0b221e75e6dcd7c21f6d357ee74",
)


class AuditError(Exception):
    pass


def git_environment():
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    return env


def git(repository, *args, ancestor=False):
    process = subprocess.run(["git", "--no-replace-objects", "-C", str(repository), *args],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=git_environment())
    if ancestor and process.returncode in (0, 1):
        return process.returncode == 0
    if process.returncode:
        raise AuditError("git " + args[0] + " failed: " + process.stderr.decode(errors="replace").strip())
    return process.stdout


def resolve(repository, revision):
    return git(repository, "rev-parse", "--verify", "--end-of-options", revision + "^{commit}").decode().strip()


def fixed_commit(repository, revision):
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise AuditError("Missing or invalid fixed source/base/foundation commit")
    if resolve(repository, revision) != revision:
        raise AuditError("Commit does not resolve to its exact pin")
    return revision


def tree_id(repository, revision):
    return git(repository, "rev-parse", revision + "^{tree}").decode().strip()


def parents(repository, revision):
    return git(repository, "show", "-s", "--format=%P", revision).decode().strip().split()


def objects(repository, revision):
    result = {}
    for item in git(repository, "ls-tree", "-r", "-z", revision).split(b"\0"):
        if item:
            header, path = item.split(b"\t", 1)
            mode, kind, oid = header.decode().split()
            result[path.decode()] = {"mode": mode, "type": kind, "oid": oid}
    return result


def regular(obj):
    return bool(obj) and obj["mode"] == "100644" and obj["type"] == "blob"


def checkout_differences(repository, expected):
    """Compare actual bytes, independent of index flags, filters and ignore rules.

    Only Git metadata and the two source-job report roots are omitted from the
    untracked inventory. Build and .swiftpm configuration are not exempt.
This runs in source-admission jobs before compilation; it does not claim to
prevent a later test process from mutating its separate runner's filesystem.
"""
    root = Path(repository).resolve()
    differences = []
    for name, obj in expected.items():
        path = root / name
        components = [root.joinpath(*Path(name).parts[:i]) for i in range(1, len(Path(name).parts) + 1)]
        if any(component.is_symlink() for component in components):
            differences.append(name)
            continue
        try:
            mode = path.lstat().st_mode
            if not stat.S_ISREG(mode):
                differences.append(name)
                continue
            data = path.read_bytes()
        except FileNotFoundError:
            differences.append(name)
            continue
        oid = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        git_mode = "100755" if mode & stat.S_IXUSR else "100644"
        if obj != {"mode": git_mode, "type": "blob", "oid": oid}:
            differences.append(name)
    output_roots = {".git", "test-results", "feedback-results"}
    unexpected = []
    for directory, directories, files in os.walk(root, followlinks=False):
        if Path(directory) == root:
            directories[:] = [d for d in directories if d not in output_roots]
            files = [f for f in files if f not in output_roots]
        for name in list(directories):
            path = Path(directory) / name
            if path.is_symlink():
                unexpected.append(path.relative_to(root).as_posix())
                directories.remove(name)
        for name in files:
            path = (Path(directory) / name).relative_to(root).as_posix()
            if path not in expected:
                unexpected.append(path)
    return sorted(set(differences)), sorted(set(unexpected))


def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise AuditError("Duplicate JSON field: " + key)
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(AuditError("Non-finite JSON")))


def read_record(repository, tree):
    obj = tree.get(ADMISSION_PATH)
    if not regular(obj):
        raise AuditError("Admission must be an existing regular 100644 JSON blob")
    raw = git(repository, "cat-file", "blob", obj["oid"])
    if len(raw) > MAX_RECORD_BYTES:
        raise AuditError("Admission record exceeds bounded size")
    record = strict_json(raw.decode("utf-8"))
    fields = {"schemaVersion", "reviewedBase", "reviewedSource", "reviewedTree",
              "authorRole", "reviews", "productionAdmission"}
    if not isinstance(record, dict) or set(record) != fields or type(record["schemaVersion"]) is not int or record["schemaVersion"] != 1:
        raise AuditError("Invalid admission schema")
    boundary = record["productionAdmission"]
    if (not isinstance(boundary, dict) or boundary != PRODUCTION_BOUNDARY
            or any(type(boundary.get(k)) is not type(v) for k, v in PRODUCTION_BOUNDARY.items())):
        raise AuditError("Production admission boundary changed")
    if not isinstance(record["authorRole"], str) or not record["authorRole"].strip():
        raise AuditError("Missing source author role")
    reviews = record["reviews"]
    if not isinstance(reviews, list) or not 1 <= len(reviews) <= 8:
        raise AuditError("Missing or excessive independent review records")
    seen = set()
    for review in reviews:
        if not isinstance(review, dict) or set(review) != {"reviewer", "source", "tree", "result", "sha256", "report"}:
            raise AuditError("Invalid review schema")
        reviewer = review["reviewer"]
        if (not isinstance(reviewer, str) or not reviewer.strip() or reviewer in seen
                or reviewer == record["authorRole"]):
            raise AuditError("Review role must be distinct from source author and other reviewers")
        seen.add(reviewer)
        if (review["source"] != record["reviewedSource"] or review["tree"] != record["reviewedTree"]
                or review["result"] != "PASS" or not isinstance(review["report"], str)):
            raise AuditError("Review does not approve the exact source/tree")
        if hashlib.sha256(review["report"].encode()).hexdigest() != review["sha256"]:
            raise AuditError("Independent review report hash mismatch")
        embedded = strict_json(review["report"])
        if (not isinstance(embedded, dict) or embedded.get("result") != "PASS"
                or embedded.get("reviewedSource") != record["reviewedSource"]
                or embedded.get("reviewedTree") != record["reviewedTree"]
                or embedded.get("reviewer") != reviewer):
            raise AuditError("Embedded review identity/result mismatch")
    return record


def legacy_audit(repository, revision, policy):
    # Execute fixed bytes, never import a working-tree policy or a review record.
    raw = git(repository, "cat-file", "blob", policy.legacy_gate_blob)
    with tempfile.TemporaryDirectory(prefix="riftlet-mainline-history-") as directory:
        payload = Path(directory) / "legacy.py"
        payload.write_bytes(raw)
        process = subprocess.run([sys.executable, "-B", str(payload), revision,
                                  "--repository", str(Path(repository).resolve())],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 env=git_environment(), timeout=180)
    report = strict_json(process.stdout.decode())
    passed = (process.returncode == 0 and isinstance(report, dict) and report.get("result") == "PASS"
              and report.get("revision") == revision and bool(report.get("checks"))
              and all(item.get("result") == "PASS" for item in report["checks"]))
    return passed, report


def audit(repository, revision="HEAD", policy=POLICY, context=None):
    """Custom policies/context are an in-process seam for isolated Git fixtures."""
    report = {"schemaVersion": 1, "result": "FAIL", "revisionRequested": revision,
              "metadataException": ADMISSION_PATH, "checks": [], "legacyAudits": {}}

    def check(name, passed, **details):
        report["checks"].append({"id": name, "result": "PASS" if passed else "FAIL", **details})

    def ancestor(older, newer):
        return git(repository, "merge-base", "--is-ancestor", older, newer, ancestor=True)

    def compare(name, expected, actual):
        e = {p: o for p, o in expected.items() if p != ADMISSION_PATH}
        a = {p: o for p, o in actual.items() if p != ADMISSION_PATH}
        check(name + ":exact-paths", set(e) == set(a), missing=sorted(set(e) - set(a)), unexpected=sorted(set(a) - set(e)))
        changes = [p for p in sorted(e) if e[p] != a.get(p)]
        check(name + ":exact-objects", not changes, protectedFileCount=len(e), differences=changes)

    try:
        actual_revision = resolve(repository, revision)
        actual = objects(repository, actual_revision)
        report.update(revision=actual_revision, tree=tree_id(repository, actual_revision), parents=parents(repository, actual_revision))
        for pin in (policy.foundation, policy.legacy_source, policy.website_source, *policy.foundation_parents):
            fixed_commit(repository, pin)
        check("foundation:tree", tree_id(repository, policy.foundation) == policy.foundation_tree)
        check("foundation:ordered-parents", parents(repository, policy.foundation) == list(policy.foundation_parents))
        foundation = objects(repository, policy.foundation)
        legacy_object = {"mode": "100644", "type": "blob", "oid": policy.legacy_gate_blob}
        check("foundation:legacy-gate", foundation.get(LEGACY_GATE_PATH) == legacy_object)
        check("legacy-source:gate", objects(repository, policy.legacy_source).get(LEGACY_GATE_PATH) == legacy_object)
        for label, rev in (("pr1", policy.legacy_source), ("main-foundation", policy.foundation)):
            passed, legacy = legacy_audit(repository, rev, policy)
            check("legacy:" + label, passed)
            report["legacyAudits"][label] = legacy

        record = read_record(repository, actual)
        base = fixed_commit(repository, record["reviewedBase"])
        source = fixed_commit(repository, record["reviewedSource"])
        approved = objects(repository, source)
        report.update(reviewedBase=base, reviewedSource=source, reviewedTree=record["reviewedTree"],
                      reviewers=[r["reviewer"] for r in record["reviews"]], productionAdmission=record["productionAdmission"])
        check("review:source-tree", tree_id(repository, source) == record["reviewedTree"])
        check("review:record-existed", regular(approved.get(ADMISSION_PATH)))
        check("ancestor:foundation-base", ancestor(policy.foundation, base))
        check("ancestor:base-source", base != source and ancestor(base, source))

        ps = report["parents"]
        merged = len(ps) == 2 and ps[0] == base
        candidate = ps[1] if merged else actual_revision
        report.update(compositionMode="reviewed-two-parent-merge" if merged else "reviewed-candidate",
                      candidate=candidate)
        check("candidate:admission-only-child", parents(repository, candidate) == [source])
        check("ancestor:source-candidate", ancestor(source, candidate))
        candidate_tree = objects(repository, candidate)
        compare("candidate", approved, candidate_tree)
        compare("checkout", approved, actual)
        check("merge:full-tree-equals-candidate", actual == candidate_tree)
        check("merge:exact-admission-blob", actual.get(ADMISSION_PATH) == candidate_tree.get(ADMISSION_PATH))

        locked = {p: o for p, o in foundation.items()
                  if p.startswith(policy.historical_prefixes) or p in policy.historical_gates}
        if not locked or not policy.historical_gates or not policy.historical_prefixes:
            raise AuditError("Historical preservation policy must not be empty")
        base_tree = objects(repository, base)
        changed = [p for p, obj in locked.items() if base_tree.get(p) != obj]
        check("base:foundation-history", not changed, differences=sorted(changed))
        # Evidence added by an earlier accepted PR becomes immutable too. Keep
        # original foundation identities if an invalid base tried replacing them.
        for path, obj in base_tree.items():
            if path.startswith(policy.historical_prefixes) or path in policy.historical_gates:
                locked.setdefault(path, obj)
        for label, tree in (("reviewed", approved), ("candidate", candidate_tree), ("checkout", actual)):
            changed = [p for p, obj in locked.items() if tree.get(p) != obj]
            check(label + ":immutable-history", not changed, protectedFileCount=len(locked), differences=sorted(changed))
            bad = [p for p, obj in tree.items() if obj["type"] != "blob" or obj["mode"] not in ("100644", "100755")]
            check(label + ":regular-files", not bad, differences=sorted(bad))
        website = objects(repository, policy.website_source)
        if not policy.website_paths or len(set(policy.website_paths)) != len(policy.website_paths):
            raise AuditError("Website policy must contain distinct exact paths")
        for path in policy.website_paths:
            obj = website.get(path)
            if not regular(obj):
                raise AuditError("Invalid fixed website object: " + path)
            check("website:" + path, all(t.get(path) == obj for t in (foundation, base_tree, approved, candidate_tree, actual)))

        if context is not None:
            event = context["event"]
            check("event:repository", context["repository"] == "haohongfei2001-png/Riftlet")
            check("event:checkout", context["sha"] == actual_revision == resolve(repository, "HEAD"))
            differences, unexpected = checkout_differences(repository, actual)
            check("checkout:actual-bytes-and-modes", not differences, differences=differences)
            check("checkout:no-untracked-inputs", not unexpected, unexpected=unexpected)
            name, ref = context["name"], context["ref"]
            if name == "pull_request":
                pr = event["pull_request"]
                check("event:pr-ref", type(event["number"]) is int and ref == "refs/pull/" + str(event["number"]) + "/merge")
                check("event:pr-base", pr["base"]["ref"] == "main" and pr["base"]["sha"] == base)
                check("event:pr-head", pr["head"]["sha"] == candidate)
                check("event:pr-ordered-merge", merged and ps == [base, pr["head"]["sha"]])
            elif name == "push":
                check("event:push-after", event["after"] == actual_revision and event["ref"] == ref)
                if ref == "refs/heads/main":
                    check("event:main-standard-merge", merged and ps == [base, candidate])
                    check("event:main-before", event["before"] == base)
                    check("event:main-not-forced-or-deleted", event.get("forced") is False and event.get("deleted") is False)
                else:
                    check("event:candidate-push", ref.startswith("refs/heads/") and not merged)
            else:
                raise AuditError("Unsupported formal event: " + str(name))
            report["event"] = {k: context[k] for k in ("name", "sha", "ref", "repository")}
    except (AuditError, OSError, UnicodeError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        check("audit:inputs", False, error=str(error))
    report["result"] = "PASS" if report["checks"] and all(c["result"] == "PASS" for c in report["checks"]) else "FAIL"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", default="HEAD")
    parser.add_argument("--repository", type=Path, default=Path("."))
    parser.add_argument("--github-event", action="store_true", help="Bind the audited commit to the actual Actions event")
    args = parser.parse_args()
    context = None
    if args.github_event:
        try:
            context = {"event": strict_json(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()),
                       "name": os.environ["GITHUB_EVENT_NAME"], "sha": os.environ["GITHUB_SHA"],
                       "ref": os.environ["GITHUB_REF"], "repository": os.environ["GITHUB_REPOSITORY"]}
        except (OSError, KeyError, ValueError, AuditError) as error:
            print(json.dumps({"result": "FAIL", "error": "Missing/invalid GitHub event: " + str(error)}))
            return 1
    report = audit(args.repository, args.revision, context=context)
    print(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False))
    print("MAINLINE_COMPOSITION_" + report["result"], file=sys.stderr)
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
