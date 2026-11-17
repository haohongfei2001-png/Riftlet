"""Recompute the 615/616 private capture, native, SQLite and isolated QA evidence offline."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from uuid import UUID


CASES = (615, 616)
ATTEMPT = "g7-terminal-pair-615-616-20261117"
TICKET_SHA = "23fc5912139cdbc6cdf1cb92785a7714bb8aed797b306d1252b12196c9b764c2"
HISTORY_SHA = "5360d70c724522794f96a0c42b9c0fee9c2e15bbf11525f6b9e9fc8163207b37"
SEALED_DB_SHA = "80f8097bbed43fcc1dcb89c64bf4fdd35057115fe0d67b68852eb0ab2cfc9ae1"
LEASE_KEYS = ("adapterID", "applicationID", "sessionID", "windowID", "tabID",
              "documentID", "composerID", "draftGeneration", "webDraftRoute")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path):
    require(path.is_file() and not path.is_symlink(), "missing or symbolic evidence")
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def opaque_id(value):
    return digest(str(UUID(value)).encode("ascii"))


def one(values):
    values = list(values)
    require(len(values) == 1, "expected exactly one match")
    return values[0]


def read(path):
    require(not path.is_symlink(), "unexpected symbolic source")
    return json.loads(path.read_bytes())


def native_receipt(rows, marker, sender, target):
    expected = [
        ("mouse_application_event", "down", None, True),
        ("mouse_dispatch_boundary", "windowEvent", "received", True),
        ("mouse_dispatch_boundary", "inputDown", "received", True),
        ("mouse_dispatch_boundary", "onDown", "received", True),
        ("mouse_dispatch_boundary", "gate", "accepted", True),
        ("selection_boundary", None, None, None),
        ("mouse_application_event", "up", None, False),
        ("mouse_dispatch_boundary", "windowEvent", "received", False),
        ("mouse_dispatch_boundary", "inputUp", "received", False),
        ("mouse_dispatch_boundary", "release", "selected", False),
    ]
    keys = ("configurationSHA256", "assetIDDigest", "attemptID", "productBinarySHA256",
            "diagnosticSessionDigest", "mouseProbeTag", "eventNumber", "windowNumber", "afterDiagnosticSequence")
    require(marker["status"] == "reservedBeforePost" and marker["assetIDDigest"] == target
            and marker["attemptID"] == ATTEMPT and all(marker[k] == sender[k] for k in keys), "wrong native reservation")
    tagged = [r for r in rows if r.get("mouseProbeTag") == marker["mouseProbeTag"]]
    require([(r["event"], r.get("phase"), r.get("status"), r.get("mouseDown")) for r in tagged] == expected,
            "native stages do not match the sole original click")
    require(all(r["diagnosticSessionDigest"] == marker["diagnosticSessionDigest"]
                and r["diagnosticSequence"] > marker["afterDiagnosticSequence"]
                and r["eventNumber"] == marker["eventNumber"] and r["windowNumber"] == marker["windowNumber"]
                and r["clickCount"] == 1 for r in tagged), "mixed native event")
    require(all(r.get("assetIDDigest") == target for r in tagged if r["event"] != "mouse_application_event")
            and tagged[5]["targetRequested"] is True and tagged[5]["source"] == "mouse", "wrong native selection")
    return tagged[2]["eventUptime"], tagged[5]["callbackUptime"]


def check_history(build, path):
    require(file_hash(path) == HISTORY_SHA, "old evidence index changed")
    items = read(path)["files"]
    for rel, stamp in items.items():
        rel = Path(rel)
        require(not rel.is_absolute() and ".." not in rel.parts, "invalid evidence location")
        original = build / rel
        require(original.stat().st_size == stamp["bytes"] and file_hash(original) == stamp["sha256"],
                "old evidence changed")
    return {"files": len(items), "bytes": sum(x["bytes"] for x in items.values()), "indexSHA256": HISTORY_SHA}


def draft_names(draft, ticket):
    require(draft["nativeTabID"] == ticket["nativeTabID"] and draft["nativeWindowID"] == ticket["nativeWindowID"]
            and draft["edgeWindow"] == ticket["edgeWindowCG"] and draft["pid"] == ticket["edgePID"]
            and draft["edgeBirth"] == ticket["edgeBirth"] and draft["frontmost"] is True and draft["exactTemporaryDraft"] is True
            and draft["textSHA256"] == ticket["textSHA256"] and draft["selectedWords"] is True
            and [draft["selectedRangeLocation"], draft["selectedRangeLength"]] == ticket["originalSelection"] == [61, 14]
            and draft["baselineImageCount"] == 1 and draft["priorImageCounts"] == [1]
            and draft["unexpectedAttachmentCount"] == 0, "draft identity, selection or baseline differs")
    names = Counter(draft["operationImageNames"])
    require(all(n == 1 for n in names.values()) and draft["attachmentImageCount"] == 1 + len(names), "duplicate attachment")
    return names


def verify(build):
    trial = build / "pr69-terminal-pair-20261117"
    obs = trial / "observations"
    qa = trial / "first-party-receipts"
    observer = build / "pr69-positive-fresh-20261117/processing-observer"
    markers = build / "pr69-runtime-20261115-restart/native-helper/attempts" / ATTEMPT
    paths = {}

    def load(label, path):
        paths[label] = path
        return read(path)

    def qa_file(prefix):
        return one(qa.glob(prefix + "-*.json"))

    history = check_history(build, trial / "history-inventory.json")
    ticket = load("stagedTicket", trial / "qa-ticket.json")
    require(file_hash(paths["stagedTicket"]) == TICKET_SHA and ticket["attemptID"] == ATTEMPT, "original ticket changed")
    require(ticket["actualRanks"] == [16, 17] and ticket["actualPages"] == [6, 6], "recorded layout differs")
    before = load("beforeSQLiteAndMedia", trial / "queue-frozen.json")
    snap = load("afterSQLiteAndMedia", trial / "actual-after-readonly.sqlite-projection.json")
    require(file_hash(paths["afterSQLiteAndMedia"]) == SEALED_DB_SHA, "sealed private SQLite projection changed")
    after = snap["state"]
    require([len(before[key]) for key in ("assets", "operations", "starts")] == [18, 9, 3]
            and [len(after[key]) for key in ("assets", "operations", "starts")] == [20, 11, 4], "ledger totals differ")
    for key, id_key in (("assets", "id"), ("operations", "id"), ("starts", "operation_id")):
        indexed = {row[id_key]: row for row in after[key]}
        require(len(indexed) == len(after[key]) and all(indexed.get(row[id_key]) == row for row in before[key]),
                "existing ledger rows changed")
    require(len(before["media"]) == 18 and len(snap["physicalMedia"]) == 20
            and all(snap["physicalMedia"].get(k) == v for k, v in before["media"].items()), "existing private PNG changed")
    result = load("nativeOutcome", obs / "outcome.json")
    prepared = load("nativeBefore", obs / "prepared.json")
    once = load("pairReservation", trial / "pair-615-616.once")
    config = load("exactSenderConfiguration", trial / ("sender-config-" + once["configSHA256"] + ".json"))
    require(config == prepared["identity"] and file_hash(paths["exactSenderConfiguration"]) == once["configSHA256"]
            and config["attemptID"] == ATTEMPT and once["attemptID"] == ATTEMPT, "wrong package or sender configuration")
    receipt = load("packageReceipt", build / "pr69-fresh-package-20261117/signed-package-receipt.json")
    require(receipt["executableSHA256"] == ticket["G7ExecutableSHA256"] == config["productBinarySHA256"],
            "candidate identity mismatch")
    old = load("previousPairOutcome", build / "pr69-positive-fresh-20261117/observations/outcome.json")
    previous_ops = [one(row["operations"]) for row in old["results"]]
    prior = Counter("riftlet-" + op["id"] + ".png" for op in previous_ops)
    require(len(prior) == 2 and draft_names(prepared["draft"], ticket) == prior, "three originals missing before")
    require(result["guardBeforeSecond"]["guard"]["armedTabMatches"] is True
            and result["guardBeforeSecond"]["guard"]["nativeTabID"] == ticket["nativeTabID"], "original tab guard mismatch")
    paths["ordinaryAppRawTrace"] = obs / "raw-events.jsonl"
    rows = [json.loads(line) for line in paths["ordinaryAppRawTrace"].read_bytes().splitlines()]
    sequences = [r["diagnosticSequence"] for r in rows]
    require(sequences == list(range(min(sequences), max(sequences) + 1))
            and len({r["diagnosticSessionDigest"] for r in rows}) == 1, "raw trace has gaps or mixed sessions")
    report, timing, by_name = [], [], {}
    new_targets = {r["seed"]: r for r in ticket["newTargets"]}
    old_leases = [json.loads(op["target_json"]) for op in previous_ops]
    bindings = {v["clickBindingID"] for v in old_leases}
    for n, seed in enumerate(CASES, start=1):
        target = new_targets[seed]
        asset = one(r for r in after["assets"] if r["id"] == target["uuid"])
        op = one(r for r in after["operations"] if r["asset_id"] == asset["id"])
        dbstarts = [r for r in after["starts"] if r["operation_id"] == op["id"]]
        opkey, assetkey = opaque_id(op["id"]), opaque_id(asset["id"])
        lease = json.loads(op["target_json"])
        require(all(lease[k] and all(lease[k] == old_lease[k] for old_lease in old_leases) for k in LEASE_KEYS)
                and lease["clickBindingID"] not in bindings, "draft lease or distinct click binding mismatch")
        bindings.add(lease["clickBindingID"])
        capture = load(f"capture{seed}", trial / f"capture-{seed}.json")
        imported = load(f"import{seed}", trial / f"import-{seed}.json")
        png = trial / f"pr69-fresh-20261117-{seed}.png"
        paths[f"originalPNG{seed}"] = png
        require(png.stat().st_size == imported["bytes"] == capture["bytes"] == target["bytes"]
                and file_hash(png) == imported["sha256"] == capture["sha256"] == target["sha256"] == snap["physicalMedia"][asset["id"]]
                and capture["fileName"] == png.name and capture["fixture"]["seed"] == seed
                and capture["systemScreenshotMetadata"] is True and capture["pngModifiedAfterCapture"] is False
                and imported["uuid"] == target["uuid"] and imported["assetDigest"] == assetkey, "wrong original")
        marker = load(f"once{seed}", markers / (assetkey + ".json"))
        sender = load(f"sender{seed}", obs / f"sender-{n}.json")
        require(marker["configurationSHA256"] == once["configSHA256"] and assetkey == once["assets"][n - 1], "reservation ordering")
        timing.append(native_receipt(rows, marker, sender, assetkey))
        rr = one(r for r in result["results"] if r["seed"] == seed)
        require(rr["operations"] == [op] and rr["original"] == target and rr["durableStartReceipts"] == dbstarts
                and rr["visibility"] == asset["visibility"] and rr["originalPNGPreserved"] is True, "disagreement with SQLite")
        operation_rows = [r for r in rows if r.get("operationIDDigest") == opkey]
        issues = [r for r in operation_rows if r["event"] == "web_command_refused"]
        entered = [r for r in operation_rows if r["event"] == "attachment_entry_result" and r.get("setterEntered") is True]
        swallowed = [r for r in operation_rows if r["event"] == "presentation_boundary" and r.get("phase") == "swallowActualStart"]
        if seed == 615:
            require(len(dbstarts) == 1 and len(swallowed) == 1 and entered and not issues
                    and any(r.get("changeReturned") is True and r.get("startObserved") is True for r in entered)
                    and [r.get("phase") for r in operation_rows if r["event"] == "presentation_boundary"]
                    == ["swallowScheduled", "swallowActualStart", "swallowClose"]
                    and (asset["status"], asset["visibility"]) == ("transferring", "swallowed"), "615 local START mismatch")
        else:
            refuse = one(issues)
            require(refuse["action"] == "chunk" and refuse["error"] == "invalidTarget"
                    and op["phase"] == "failed" and op["reason"] == "Verified pre-input rejection: localBeforeBegin: fileInputCommandNotInvoked"
                    and not dbstarts and not swallowed and not entered and (asset["status"], asset["visibility"]) == ("failed", "visible"),
                    "616 pre-input failure mismatch")
        by_name[seed] = "riftlet-" + op["id"] + ".png"
        report.append({"seed": seed, "originalBytes": png.stat().st_size, "pngSHA256": target["sha256"],
                       "nativeStages": 10, "operationCount": 1, "durableStarts": len(dbstarts),
                       "originalInputSetterObserved": bool(entered), "swallowStarted": bool(swallowed),
                       "visibility": asset["visibility"], "observerTerminal": "UNKNOWN",
                       "refusal": "chunk/invalidTarget" if issues else None,
                       "operationFilenameSHA256": digest(by_name[seed].encode("ascii"))})
    names = draft_names(result["draftAfter"], ticket)
    require(names == prior + Counter([by_name[615]]) and result["draftAfter"]["expectedOperationImageCounts"] == [1, 0],
            "four final attachments differ")
    down, callbacks = [round((timing[1][i] - timing[0][i]) * 1000, 3) for i in (0, 1)]
    require(down == result["nativeReceivedDownEventIntervalMs"] and callbacks == result["selectionCallbackIntervalMs"]
            and result["retryCount"] == 0, "native interval or retry mismatch")
    initial = load("observerInitialStatus", qa_file("initial-status"))
    arm = load("observerArm", qa_file("arm"))
    custody = load("observerArmCustody", trial / "observer-arm-custody.json")
    final = load("observerFinalStatus", qa_file("final-status"))
    require(initial == {"installed": False} and arm["armed"] is True and
            custody["sha256"] == file_hash(paths["observerArm"]) == prepared["actualObserverArmReceiptSHA256"]
            and custody["ticketSHA256"] == TICKET_SHA, "observer arm differs")
    require(arm["originalFiles"] == [{"seed": n, "size": new_targets[n]["bytes"], "sha256": new_targets[n]["sha256"]} for n in CASES],
            "observer scoped to different files")
    for key, file in (("readerSHA256", "future-observer.js"), ("wrapperSHA256", "scoped-fetch.js")):
        paths[key] = observer / file
        require(file_hash(paths[key]) == arm[key], "observer source differs")
    statuses = [load(f"observerPoll{i:02}", p) for i, p in enumerate(sorted(qa.glob("status-*.json")), start=1)]
    require(statuses and all(row["selectionPlanCount"] == 2 and row["installed"] is True
            and row["originalRequestMatches"] == 0 and row["matchedChanges"] in (0, 1)
            and row["files"] in ([], [{"seed": 615, "terminal": "UNKNOWN"}]) for row in statuses + [final]),
            "observer status differs")
    require(final["reason"] == "DEADLINE" and final["mounted"] is False and final["originalRestored"] is True
            and final["matchedChanges"] == 1 and final["files"] == [{"seed": 615, "terminal": "UNKNOWN"}],
            "observer final result differs")
    # Preserve the sealed references for reproducing spool, hit-map, fixture and sender verification.
    for key, path in {"fixtureSource": trial / "SmallNeutralFixture.swift", "fixtureExecutable": trial / "small-neutral-fixture",
                      "operatorSequence": trial / "observed-service-pair.py", "ordinaryPairRunner": trial / "pair615.py",
                      "hitMapEpochs": obs / "map-epochs.jsonl", "selectionDecisionLog": obs / "decisions.jsonl",
                      "originalObserverExecutable": observer / "original-pair-qa", "ordinarySender": build / "pr69-mouse-delivery-review/exact-mouse-v2",
                      "operatorNativeOutcome": qa_file("native-run")}.items():
        paths[key] = path
    for n, seed in enumerate(CASES, start=1):
        paths[f"captureReservation{seed}"] = trial / f"capture-{seed}.once"
        paths[f"captureWindow{seed}"] = trial / f"capture-{seed}-window.json"
        paths[f"nativeIntent{seed}"] = obs / f"intent-{n}.json"
    return {"schema": 1, "ordinaryPackageSHA256": ticket["G7ExecutableSHA256"],
            "captureBefore": {"assets": 18, "operations": 9, "starts": 3, "priorAttachments": 3},
            "captureAfter": {"assets": 20, "operations": 11, "starts": 4, "attachments": 4, "preservedSelectionLength": 14},
            "ranks": ticket["actualRanks"], "pages": ticket["actualPages"], "rawTraceRows": len(rows),
            "nativeDownIntervalMs": down, "nativeSelectionCallbackIntervalMs": callbacks, "images": report,
            "observer": {"matchedChanges": 1, "matchedOriginalProcessingRequests": 0, "explicitServiceTerminals": 0,
                         "statusPolls": len(statuses), "deadline": True, "originalFetchRestored": True},
            "priorNativeEvidence": history, "sourceSHA256": {k: file_hash(v) for k, v in sorted(paths.items())}}


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--build", type=Path, default=Path(__file__).resolve().parents[2], help="private artifact build directory")
    cli.add_argument("--expect", type=Path, help="compare with a previously generated shareable projection")
    cli.add_argument("--output", type=Path, help="create a new projection exclusively")
    args = cli.parse_args()
    result = verify(args.build)
    if args.expect:
        require(read(args.expect) == result, "published projection differs")
    text = json.dumps(result, ensure_ascii=True, sort_keys=True, indent=2) + "\n"
    if args.output:
        with args.output.open("x") as stream:
            stream.write(text)
    elif args.expect:
        print("PASS - native trace, two originals, sealed SQLite, scoped observer and prior evidence match")
    else:
        print(text, end="")
