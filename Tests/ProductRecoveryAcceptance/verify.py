#!/usr/bin/env python3
"""Read-only cross-checks for the local application runs. Emit no private QA identifiers."""

import argparse, base64, hashlib, json, sqlite3
from pathlib import Path


def read(file):
    return json.loads(file.read_bytes())


def sha(file):
    with file.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def check(condition, why):
    if not condition:
        raise ValueError(why)


def state(folder, label):
    d = read(folder / (label + ".json"))
    url = (folder / (label + ".sqlite")).resolve().as_uri() + "?mode=ro&immutable=1"
    with sqlite3.connect(url, uri=True) as cx:
        cx.row_factory = sqlite3.Row
        check(
            cx.execute("PRAGMA integrity_check").fetchone()[0] == "ok",
            "SQLite integrity",
        )
        check(
            not cx.execute("PRAGMA foreign_key_check").fetchall(), "SQLite foreign key"
        )
        for t in d["db"]:
            rows = [dict(r) for r in cx.execute("SELECT * FROM " + t)]
            check(
                d["db"][t] == rows, label + " screenshot/backup database disagreement"
            )
        cp = {
            k: json.loads(base64.b64decode(v))
            for k, v in cx.execute(
                "SELECT key,value FROM checkpoints WHERE key LIKE 'transfer-dispatch-call-v1:%' OR key LIKE 'transfer-late-original-card-v1:%'"
            )
        }
        handled = cx.execute("SELECT count(*) FROM handled_attachments").fetchone()[0]
    page = d["page"]
    src = read(folder / "screenshot.json")
    check(
        page["source"] == "CONTROLLED_PRODUCT_RECOVERY_FIXTURE" and src["systemMarker"],
        "genuine controlled origin",
    )
    check(len(d["db"]["assets"]) == 1 and src["bytes"] > 0, "one source in isolation")
    check(
        page["previousAttachmentPreserved"] and page["originalDocument"],
        "original page and old attachment",
    )
    check(
        page["inputs"]
        == page["changes"]
        == page["setterEntries"]
        == page["setterReturns"]
        == len(page["files"]),
        "distinct setter/events/files",
    )
    check(
        page["duplicates"]
        == page["foreignSetters"]
        == page["sends"]
        == page["submits"]
        == 0,
        "unexpected side effect",
    )
    for f in page["files"]:
        check(
            f["sha256"] == src["sha256"]
            and f["bytes"] == src["bytes"]
            and f["changeCount"] == 1,
            "full original file",
        )
    for path in [
        next(folder.glob("app-support/*/capture-source/*.png")),
        next(folder.glob("app-support/*/media/*.png")),
    ]:
        check(sha(path) == src["sha256"], "private original and collected bytes")
    if page["originalDraft"]:
        check(
            page["originalComposer"] and page["selectionInOriginalEditor"],
            "original editor",
        )
        check(
            (page["text"], page["selection"], page["anchor"], page["focus"])
            == (
                "Riftlet QA: preserve this original draft while attaching images.",
                "preserve this original draft",
                12,
                40,
            ),
            "text and selection",
        )
    previews = {f["operationID"].upper(): f for f in page["files"]}
    for st in d["db"]["upload_starts"]:
        rec = json.loads(st["receipt_json"])
        op = st["operation_id"]
        check(
            op in previews
            and rec["operationID"] == op
            and src["sha256"] == rec["assetSHA256"]
            and rec["attachmentAcceptanceEvidence"]["inputCount"] == 1,
            "real once-only START/PNG lineage",
        )
    for row in d["db"]["operations"]:
        key = "transfer-dispatch-call-v1:" + row["id"]
        if key not in cp:
            continue
        v = cp[key]
        check(
            v["operationID"] == row["id"]
            and v["assetID"] == row["asset_id"]
            and v["target"] == json.loads(row["target_json"])
            and v["assetSHA256"] == src["sha256"],
            "frozen dispatch mismatch",
        )
    return d, cp, handled


def verify(inputs):
    results = {}
    rebirth = None
    refs = {}
    snapshotHashes = set()
    for tag, folder in inputs.items():
        b = read(folder / "binary-manifest.json")
        ar = next((k, v) for k, v in b["sha256"].items() if k.endswith("/source.tar"))
        check(sha(Path(ar[0])) == ar[1], "frozen original source hash")
        snapshotHashes.add(ar[1])
        traces = [read(f) for f in folder.glob("transport-*.json")]
        down = {
            x["uptime"]
            for x in traces
            if x["event"] == "appkitDelivered" and x["type"] == 1
        }
        frozen = [x for x in traces if x["event"] == "ownedConsumedByAppKit"]
        check(
            all(x["uptime"] in down for x in frozen),
            "actual AppKit mouse-down for each freeze",
        )
        ref = {
            f.name: sha(f)
            for f in folder.iterdir()
            if f.is_file()
            and (
                f.suffix == ".sqlite"
                or f.name == "binary-manifest.json"
                or f.name == "screenshot.json"
                or (f.suffix == ".json" and f.name[0].isupper())
            )
        }
        refs[tag] = ref
        if tag == "A":
            a, _, _ = state(folder, "A-initial")
            z, _, _ = state(folder, "A-after")
            o = a["db"]["operations"][0]
            check(
                o["phase"] == "failed"
                and not a["db"]["upload_starts"]
                and a["page"]["inputs"] == 0
                and a["ui"]["rows"],
                "original pre-input rejection",
            )
            check(
                z["db"]["operations"][0] == o
                and len(z["db"]["operations"]) == 2
                and z["page"]["inputs"] == len(z["db"]["upload_starts"]) == 1,
                "A independent new click",
            )
            check(len(frozen) == 2, "two actual selections")
            results["A"] = {
                "status": "PASS",
                "originalInputs": 0,
                "newInputs": 1,
                "newStarts": 1,
                "originalRetained": True,
            }
        elif tag == "B":
            a, _, _ = state(folder, "B-unknown")
            z, _, handled = state(folder, "B-neutral-unknown")
            check(
                a["page"]["inputs"]
                == z["page"]["inputs"]
                == len(z["db"]["upload_starts"])
                == 1
                and len(frozen) == 1,
                "B unique real attachment",
            )
            old, new = a["db"]["operations"][0], z["db"]["operations"][0]
            rec = json.loads(new["receipt_json"])
            check(
                old["id"] == new["id"]
                and old["phase"] == new["phase"] == "unknown"
                and rec["hasError"]
                and rec["outcome"] == "unknown"
                and handled == 0,
                "B pending neutral abnormality",
            )
            check(
                not z["ui"]["rows"]
                and any(
                    ("结果尚未确认" in t or "Result unconfirmed" in t)
                    for t in z["ui"]["text"]
                ),
                "B exposure",
            )
            results["B"] = {
                "status": "PASS",
                "starts": 1,
                "phase": "unknown",
                "userVisibleNeutralError": True,
                "continuedWithoutRetry": True,
                "handled": False,
            }
        elif tag == "rebirth":
            source, scp, _ = state(folder, "Reborn-visible")
            after, acp, _ = state(folder, "Reborn-attached")
            old = source["db"]["operations"][0]
            new = after["db"]["operations"][1]
            call = lambda cp, op: cp["transfer-dispatch-call-v1:" + op["id"]]
            receipt = json.loads(old["receipt_json"])
            check(
                source["page"]["inputs"] == 1
                and len(source["db"]["operations"]) == 1
                and source["ui"]["rows"],
                "clickable original error without auto-input",
            )
            check(
                source["db"]["assets"][0]["visibility_reason"] == "safeFailure"
                and receipt["hasError"]
                and receipt["originalCardFailureInvocationID"]
                == call(scp, old)["invocationID"],
                "positive original named member",
            )
            check(
                after["db"]["operations"][0] == old
                and after["page"]["inputs"]
                == len(after["db"]["upload_starts"])
                == len(frozen)
                == 2
                and new["attempt"] == 2
                and call(acp, new)["invocationID"] != call(scp, old)["invocationID"],
                "explicit click on original reborn image",
            )
            rebirth = {
                "status": "PASS",
                "automaticInputs": 0,
                "newInputs": 1,
                "newStarts": 1,
                "originalErrorPreserved": True,
            }
        elif tag in ["C", "F", "G"]:
            h, oldCp, _ = state(folder, "H-cancel")
            before, bCp, _ = state(folder, "D-existing")
            z, zCp, _ = state(folder, "C-explicit")
            check(
                h["db"] == before["db"]
                and h["page"]["inputs"] == before["page"]["inputs"] == 1
                and bCp == oldCp,
                "H cancel unchanged",
            )
            sheet = read(folder / "D-warning.json")
            check(
                sheet["sheets"] == 1
                and before["page"]["files"][0]["present"]
                and any("重复" in v or "duplicate" in v for v in sheet["text"]),
                "D real sheet on existing attachment",
            )
            old, new = z["db"]["operations"]
            id1, id2 = old["id"], new["id"]
            check(
                len(frozen) == 2
                and len(z["db"]["attachment_reselections"]) == 1
                and z["db"]["attachment_reselections"][0]
                == dict(successor_id=id2, predecessor_id=id1),
                "parent/child IDs",
            )
            check(
                old == h["db"]["operations"][0]
                and id1 != id2
                and new["attempt"] == 2
                and len(z["db"]["upload_starts"]) == 2
                and z["page"]["inputs"] == 2,
                "C independent unique STARTs",
            )
            key = lambda i: "transfer-dispatch-call-v1:" + i
            oldcall, newcall = zCp[key(id1)], zCp[key(id2)]
            check(
                oldCp[key(id1)] == oldcall
                and oldcall["invocationID"] != newcall["invocationID"]
                and oldcall["target"]["clickBindingID"]
                != newcall["target"]["clickBindingID"],
                "unique destinations",
            )
            check(
                {x["binding"].upper() for x in frozen}
                == {
                    oldcall["target"]["clickBindingID"].upper(),
                    newcall["target"]["clickBindingID"].upper(),
                },
                "frozen and dispatched binding",
            )
            if tag == "C":
                neutral, _, _ = state(folder, "B-neutral-unknown")
                receipt = json.loads(neutral["db"]["operations"][0]["receipt_json"])
                check(
                    receipt["outcome"] == "unknown"
                    and receipt["hasError"]
                    and neutral["page"]["inputs"] == 1,
                    "indeterminate precursor required",
                )
                results["C"] = {
                    "status": "PASS",
                    "sourceHadAttributedUnconfirmedError": True,
                    "newInvocations": 1,
                    "newInputs": 1,
                    "newStarts": 1,
                    "oldOperationPreserved": True,
                }
            if tag == "F":
                results.update(
                    D={
                        "status": "PASS",
                        "originalCardPresent": True,
                        "duplicateRiskShown": True,
                    },
                    H={
                        "status": "PASS",
                        "newInvocations": 0,
                        "newInputs": 0,
                        "newStarts": 0,
                    },
                )
                end, endCp, _ = state(folder, "F-late")
                latekey = "transfer-late-original-card-v1:" + id1
                check(
                    latekey in endCp
                    and end["db"] == z["db"]
                    and end["page"]["inputs"] == 2
                    and endCp[key(id1)] == oldcall
                    and endCp[key(id2)] == newcall,
                    "F must be isolated",
                )
                late = endCp[latekey]
                check(
                    late["operationID"] == id1
                    and late["assetSHA256"] == oldcall["assetSHA256"]
                    and late["hasError"]
                    and late["belongsToOriginalDraft"]
                    and late["originalCardFailureInvocationID"]
                    == oldcall["invocationID"]
                    and late["attachmentID"]
                    == json.loads(z["db"]["upload_starts"][0]["receipt_json"])[
                        "attachmentID"
                    ],
                    "old late identity",
                )
                results["F"] = {
                    "status": "PASS",
                    "independentLateRecord": 1,
                    "newOperationChanged": False,
                    "extraInputs": 0,
                }
            if tag == "G":
                g, gcp, _ = state(folder, "G-restart")
                check(
                    g["db"]["operations"] == [old]
                    and g["db"]["upload_starts"] == z["db"]["upload_starts"][:1]
                    and gcp[key(id1)] == oldcall
                    and g["page"]["inputs"] == 1,
                    "G persisted original",
                )
                check(
                    len({x["pid"] for x in traces if x["event"] == "productUIReady"})
                    == 2,
                    "G distinct app lifetimes",
                )
                results["G"] = {
                    "status": "PASS",
                    "applicationProcesses": 2,
                    "automaticInputs": 0,
                    "explicitRecoveryAfterRestart": True,
                }
        elif tag == "E":
            a, _, _ = state(folder, "H-cancel")
            end, _, _ = state(folder, "E-final")
            check(
                not end["page"]["originalDraft"]
                and len(frozen) == 2
                and end["db"]["operations"] == a["db"]["operations"]
                and end["page"]["inputs"] == 1,
                "different draft blocked",
            )
            results["E"] = {
                "status": "PASS",
                "attemptedOnNewDraft": True,
                "newFileInputs": 0,
                "newOperations": 0,
            }
    check(
        len(snapshotHashes) == 1 and set(results) == set("ABCDEFGH"),
        "single candidate and eight complete gates",
    )
    return {
        "suite": "CONTROLLED_PRODUCT_RECOVERY_FIXTURE",
        "literalSignedPackage": False,
        "thirdPartyRequests": 0,
        "sends": 0,
        "formSubmits": 0,
        "sourceArchiveSHA256": next(iter(snapshotHashes)),
        "results": results,
        "confirmedFailureRebirth": rebirth,
        "receiptSHA256": refs,
    }


if __name__ == "__main__":
    a = argparse.ArgumentParser()
    for k in "ABCFEG":
        a.add_argument("--" + k, required=True, type=Path)
    a.add_argument("--rebirth", required=True, type=Path)
    args = a.parse_args()
    print(json.dumps(verify(vars(args)), indent=2, sort_keys=True))
