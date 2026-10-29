import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("natural_timeline", Path(__file__).with_name("timeline.py"))
timeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(timeline)


def fixture():
    manifest = {"version": 1, "runID": "run-a", "bootID": "boot-a", "clock": timeline.CLOCK,
        "trials": [{"id": "N1", "scenario": "existing-chat", "source": "CGEvent", "assetID": "asset-new",
                    "priorOperationCount": 0, "sourceEvidence": {"token": 60457},
                    "captureCompletion": {"kind": "interval", "lowerUptime": 1.0, "upperUptime": 1.2,
                                          "evidence": "capture-release-to-verified-copy"}}]}
    context = {"captureRequestID": "request-a", "armAttemptID": "attempt-a", "hostEpoch": "epoch-a"}
    def app(event, **values):
        return {"event": event, "runID": "run-a", "clock": timeline.CLOCK, **values}
    rows = [
        app("arm_attempt_started", uptime=0.1, **context),
        {"event": "native_bridge", "requestID": "request-a", "action": "captureTarget", "phase": "complete",
         "queuedUptime": 0.12, "startedUptime": 0.13, "endedUptime": 0.215,
         "transportSucceeded": True, **context},
        {"event": "capture_ack", "phase": "native_validated", "requestID": "request-a", "accepted": True,
         "nativeReceivedUptime": 0.2, "nativeValidatedUptime": 0.21, "targetDigest": "digest-a", **context},
        app("arm_completion", startedUptime=0.1, mainPublishedUptime=0.231, adapterValidatedUptime=0.22,
            effectiveAckUptime=0.23, effectiveCaptureRequestID="request-a", effectiveArmAttemptID="attempt-a",
            publicationResult="publishedNewTarget", epochAccepted=True, armed=True, captureAttempted=True,
            error="none", reusedExistingArmedTarget=False, targetDigest="digest-a", **context),
        app("capture_source_verified", assetID="asset-new", firstObservedUptime=1.0,
            validatedCopyUptime=1.2, durableCommitUptime=1.21),
        app("capture_durable_delivery", assetID="asset-new", readyUptime=1.22, callbackUptime=1.25),
        app("input_windows_observed", assetID="asset-new", phase="initialOrder", uptime=1.26,
            windowsVisible=True, windowServerHitMeasured=False, pixelPresentationMeasured=False),
        app("input_windows_observed", assetID="asset-new", phase="imageDelivery", uptime=1.28,
            windowsVisible=True, imageDecoded=True),
        app("native_input_receipt", assetID="asset-new", eventUptime=1.3, callbackUptime=1.31,
            eventNumber=41, windowNumber=53, eventSourceUserData=60457, gateAccepted=True),
        app("selection_boundary", assetID="asset-new", source="mouse", eventUptime=1.3,
            originalEventUptime=1.3, callbackUptime=1.31, eventNumber=41, windowNumber=53,
            eventSourceUserData=60457, effectiveCaptureRequestID="request-a", effectiveArmAttemptID="attempt-a",
            targetDigest="digest-a", hostEpoch="epoch-a", frozen=True, freezeResult="accepted",
            hostEpochMatches=True, foregroundSessionMatches=True, ackUptime=0.23),
    ]
    return manifest, rows


def row(rows, event):
    return next(r for r in rows if r["event"] == event)


class TimelineTests(unittest.TestCase):
    def test_exact_join_keeps_software_input_and_unmeasured_boundaries_separate(self):
        manifest, rows = fixture()
        report = timeline.analyze(manifest, rows)
        trial = report["trials"][0]
        self.assertEqual(trial["status"], "ACK_BEFORE_CLICK_PROVEN")
        self.assertEqual(trial["ackEvidence"]["ackMarginMS"], 1070)
        self.assertEqual(trial["latencyMS"]["importReadyToMainCallback"], 30)
        self.assertEqual(trial["captureCompletion"]["status"], "INTERVAL_ATTESTED")
        self.assertIn("exactSystemCaptureCompletion", trial["missingStages"])
        self.assertIn("firstWindowServerHitAvailability", trial["missingStages"])
        self.assertEqual(trial["attachmentSuccess"], "NOT_VERIFIED")
        self.assertFalse(trial["hardwareDeviceProvenByTrace"])
        self.assertEqual(report["bySource"]["CGEvent"]["preClickACKRate"], 1)
        self.assertIsNone(report["bySource"]["physical"]["preClickACKRate"])
        self.assertIsNone(report["bySource"]["CGEvent"]["attachmentSuccessRate"])

    def test_line_order_does_not_create_causality(self):
        manifest, rows = fixture()
        self.assertEqual(timeline.analyze(manifest, rows), timeline.analyze(manifest, list(reversed(rows))))

    def test_pending_late_ack_never_becomes_original_authority(self):
        manifest, rows = fixture()
        selection = row(rows, "selection_boundary")
        for name in ("effectiveCaptureRequestID", "effectiveArmAttemptID", "targetDigest", "ackUptime"):
            selection.pop(name)
        selection.update(frozen=False, freezeResult="refused", refusalReason="noPublishedTarget",
                         hostEpochMatches=False, foregroundSessionMatches=False,
                         inFlightCaptureRequestID="request-a", inFlightArmAttemptID="attempt-a")
        row(rows, "capture_ack").update(nativeReceivedUptime=1.4, nativeValidatedUptime=1.42)
        row(rows, "arm_completion").update(effectiveAckUptime=1.43, mainPublishedUptime=1.44)
        report = timeline.analyze(manifest, rows)
        trial = report["trials"][0]
        self.assertEqual(trial["status"], "REFUSED")
        self.assertFalse(trial["pendingCaptureDiagnostic"]["authorizesOriginalClick"])
        self.assertEqual(trial["pendingCaptureDiagnostic"]["appACKOffsetMS"], 130)
        self.assertEqual(report["bySource"]["CGEvent"]["preClickACKRate"], 0)

    def test_wrong_invocation_epoch_digest_or_reused_publication_cannot_join(self):
        for field, value in (("armAttemptID", "other"), ("captureRequestID", "other"),
                             ("hostEpoch", "other"), ("targetDigest", "other"),
                             ("publicationResult", "acceptedExistingTarget")):
            with self.subTest(field=field):
                manifest, rows = fixture()
                row(rows, "arm_completion")[field] = value
                self.assertEqual(timeline.analyze(manifest, rows)["trials"][0]["status"], "ACK_NOT_PROVEN")

    def test_refused_epoch_foreground_and_failed_capture_never_qualify(self):
        for event, field in (("capture_ack", "accepted"), ("arm_completion", "epochAccepted"),
                             ("arm_completion", "captureAttempted"), ("native_bridge", "transportSucceeded"),
                             ("selection_boundary", "foregroundSessionMatches"),
                             ("selection_boundary", "hostEpochMatches")):
            with self.subTest(event=event, field=field):
                manifest, rows = fixture()
                row(rows, event)[field] = False
                self.assertEqual(timeline.analyze(manifest, rows)["trials"][0]["status"], "ACK_NOT_PROVEN")

    def test_late_equal_or_nonfinite_effective_ack_is_not_backdated(self):
        for value in (1.3, 1.4, float("nan"), float("inf"), -1, True):
            with self.subTest(value=value):
                manifest, rows = fixture()
                row(rows, "selection_boundary")["ackUptime"] = value
                row(rows, "arm_completion")["effectiveAckUptime"] = value
                self.assertEqual(timeline.analyze(manifest, rows)["trials"][0]["status"], "ACK_NOT_PROVEN")

    def test_publication_observation_after_event_remains_distinct_from_effective_ack(self):
        manifest, rows = fixture()
        row(rows, "arm_completion")["mainPublishedUptime"] = 1.3001
        trial = timeline.analyze(manifest, rows)["trials"][0]
        self.assertEqual(trial["status"], "ACK_BEFORE_CLICK_PROVEN")
        self.assertFalse(trial["ackEvidence"]["publicationObservationBeforeClick"])

    def test_capture_inversion_does_not_revoke_ack_but_invalidates_affected_durations(self):
        cases = (("capture_source_verified", "firstObservedUptime", 5),
                 ("capture_source_verified", "validatedCopyUptime", 5),
                 ("capture_source_verified", "durableCommitUptime", 5),
                 ("capture_durable_delivery", "readyUptime", 5))
        for event, field, value in cases:
            with self.subTest(field=field):
                manifest, rows = fixture()
                row(rows, event)[field] = value
                report = timeline.analyze(manifest, rows)
                trial = report["trials"][0]
                self.assertEqual(trial["status"], "ACK_BEFORE_CLICK_PROVEN")
                self.assertEqual(trial["captureChainStatus"], "INCONSISTENT")
                self.assertTrue(trial["invalidStages"])
                # No duration may use an inconsistent endpoint, but the
                # independently ordered presentation branch can remain valid.
                self.assertTrue(any(value is None for value in trial["latencyMS"].values()))
        manifest, rows = fixture()
        row(rows, "capture_source_verified")["validatedCopyUptime"] = 5
        trial = timeline.analyze(manifest, rows)["trials"][0]
        self.assertEqual(trial["latencyMS"]["importReadyToMainCallback"], 30)
        self.assertIsNone(trial["latencyMS"]["sourceValidatedToWindowObservation"])
        self.assertEqual(trial["originalEventOffsetsMS"]["fromInputWindowObservation"], 40)
        self.assertEqual(trial["originalEventOffsetsMS"]["fromSourceValidatedCopy"], -3700)
        self.assertIn("fromSourceValidatedCopy", trial["invalidEventOffsetBaselines"])
        report = timeline.analyze(manifest, rows)
        self.assertIsNone(report["bySource"]["CGEvent"]["originalEventOffsetDistributionMS"]["fromSourceValidatedCopy"])

    def test_window_observation_can_precede_importer_return_and_main_delivery_stamps(self):
        manifest, rows = fixture()
        row(rows, "capture_source_verified")["durableCommitUptime"] = 2
        row(rows, "capture_durable_delivery").update(readyUptime=2.01, callbackUptime=2.02)
        trial = timeline.analyze(manifest, rows)["trials"][0]
        self.assertEqual(trial["captureChainStatus"], "PARTIAL")
        self.assertFalse(trial["invalidStages"])
        self.assertEqual(trial["status"], "ACK_BEFORE_CLICK_PROVEN")
        self.assertEqual(trial["latencyMS"]["sourceValidatedToWindowObservation"], 60)
        self.assertEqual(trial["latencyMS"]["importReadyToMainCallback"], 10)

    def test_original_event_before_window_observation_is_signed_offset_not_capture_failure(self):
        for event_time in (1.2599, 0.25):
            # First case: a press between orderFront and the observation.
            # Second case: CGEvent created before capture and delivered later.
            with self.subTest(event_time=event_time):
                manifest, rows = fixture()
                row(rows, "native_input_receipt")["eventUptime"] = event_time
                row(rows, "selection_boundary").update(eventUptime=event_time, originalEventUptime=event_time)
                report = timeline.analyze(manifest, rows)
                trial = report["trials"][0]
                self.assertEqual(trial["captureChainStatus"], "PARTIAL")
                self.assertFalse(trial["invalidStages"])
                self.assertEqual(trial["status"], "ACK_BEFORE_CLICK_PROVEN")
                self.assertLess(trial["originalEventOffsetsMS"]["fromInputWindowObservation"], 0)
                self.assertFalse(trial["originalEventOffsetsAreLatencies"])
                self.assertNotIn("windowOrderToClick", trial["latencyMS"])
                self.assertLess(report["bySource"]["CGEvent"]["originalEventOffsetDistributionMS"]["fromInputWindowObservation"]["min"], 0)

    def test_missing_capture_stages_are_not_filled_and_nonadjacent_inversion_is_detected(self):
        manifest, rows = fixture()
        row(rows, "capture_source_verified")["validatedCopyUptime"] = 5
        row(rows, "capture_source_verified").pop("durableCommitUptime")
        rows = [r for r in rows if r["event"] != "capture_durable_delivery"]
        trial = timeline.analyze(manifest, rows)["trials"][0]
        self.assertEqual(trial["captureChainStatus"], "INCONSISTENT")
        self.assertIn("sourceValidatedCopyUpperBound>inputWindowsOrdered", trial["invalidStages"])
        self.assertIsNone(trial["times"]["durableCommit"])
        self.assertIsNone(trial["latencyMS"]["importReadyToMainCallback"])
        self.assertIn("durableCommit", trial["missingStages"])

    def test_image_delivery_after_click_is_reported_without_inventing_wrong_order(self):
        manifest, rows = fixture()
        next(r for r in rows if r.get("phase") == "imageDelivery")["uptime"] = 1.5
        trial = timeline.analyze(manifest, rows)["trials"][0]
        self.assertEqual(trial["captureChainStatus"], "PARTIAL")
        self.assertFalse(trial["invalidStages"])
        self.assertEqual(trial["latencyMS"]["sourceValidatedToImageDelivery"], 300)
        self.assertEqual(trial["originalEventOffsetsMS"]["fromSourceValidatedCopy"], 100)

    def test_t0_cannot_contradict_verified_copy_or_be_inferred_from_file_time(self):
        for completion in ({"kind": "exact", "uptime": 5, "evidence": "operator receipt"},
                           {"kind": "interval", "lowerUptime": 5, "upperUptime": 6, "evidence": "receipt"}):
            with self.subTest(kind=completion["kind"]):
                manifest, rows = fixture()
                manifest["trials"][0]["captureCompletion"] = completion
                trial = timeline.analyze(manifest, rows)["trials"][0]
                self.assertEqual(trial["captureChainStatus"], "INCONSISTENT")
                self.assertEqual(trial["captureCompletion"]["temporalCheck"], "CONTRADICTS_VALIDATED_COPY")
                self.assertIsNone(trial["latencyMS"]["sourceValidatedToWindowObservation"])
                self.assertIn("fromSourceValidatedCopy", trial["invalidEventOffsetBaselines"])
                self.assertEqual(trial["status"], "ACK_BEFORE_CLICK_PROVEN")
        manifest, rows = fixture()
        manifest["trials"][0]["captureCompletion"]["upperUptime"] = 6
        trial = timeline.analyze(manifest, rows)["trials"][0]
        self.assertEqual(trial["captureChainStatus"], "PARTIAL")
        self.assertEqual(trial["captureCompletion"]["temporalCheck"], "OVERLAPS_VALIDATED_COPY_BOUND")
        self.assertEqual(trial["captureCompletion"]["upperUptime"], 6)
        manifest["trials"][0].pop("captureCompletion")
        trial = timeline.analyze(manifest, rows)["trials"][0]
        self.assertEqual(trial["captureCompletion"]["status"], "NOT_MEASURED")

    def test_mouse_without_human_observation_cannot_become_physical(self):
        manifest, rows = fixture()
        manifest["trials"][0]["source"] = "physical"
        self.assertEqual(timeline.analyze(manifest, rows)["trials"][0]["status"], "NOT_EVALUABLE")

    def test_token_mismatch_and_wrong_window_excluded(self):
        for field, value in (("eventSourceUserData", 7), ("windowNumber", 9), ("eventNumber", 10)):
            with self.subTest(field=field):
                manifest, rows = fixture()
                row(rows, "native_input_receipt")[field] = value
                self.assertEqual(timeline.analyze(manifest, rows)["trials"][0]["status"], "NOT_EVALUABLE")

    def test_multiple_presses_cannot_hide_first_refusal(self):
        manifest, rows = fixture()
        earlier = copy.deepcopy(row(rows, "native_input_receipt"))
        earlier.update(eventUptime=1.29, gateAccepted=False)
        rows.append(earlier)
        report = timeline.analyze(manifest, rows)
        self.assertEqual(report["trials"][0]["status"], "NOT_EVALUABLE")
        self.assertIsNone(report["bySource"]["CGEvent"]["preClickACKRate"])

    def test_native_gate_refusal_is_a_real_attempt_not_a_missing_selection(self):
        manifest, rows = fixture()
        rows = [r for r in rows if r["event"] != "selection_boundary"]
        row(rows, "native_input_receipt")["gateAccepted"] = False
        report = timeline.analyze(manifest, rows)
        self.assertEqual(report["trials"][0]["status"], "REFUSED")
        self.assertEqual(report["trials"][0]["refusalReason"], "nativeGateRefused")
        self.assertEqual(report["bySource"]["CGEvent"]["qualifiedNativeTrials"], 1)

    def test_old_operation_missing_selection_and_not_run_not_success(self):
        manifest, rows = fixture()
        manifest["trials"][0]["priorOperationCount"] = 1
        self.assertEqual(timeline.analyze(manifest, rows)["trials"][0]["status"], "NOT_EVALUABLE")
        manifest["trials"][0] = {"id": "N1", "scenario": "startup", "source": "physical",
                                  "notRunReason": "No human hardware actor"}
        report = timeline.analyze(manifest, [])
        self.assertEqual(report["trials"][0]["status"], "NOT_RUN")
        self.assertIsNone(report["bySource"]["physical"]["preClickACKRate"])
        self.assertEqual(report["bySource"]["physical"]["status"], "NOT_RUN")

    def test_reused_asset_duplicate_trial_and_ambiguous_ack_fail_closed(self):
        manifest, rows = fixture()
        duplicate = copy.deepcopy(manifest["trials"][0])
        duplicate["id"] = "N2"
        manifest["trials"].append(duplicate)
        with self.assertRaisesRegex(timeline.EvidenceError, "reused_trial_asset"):
            timeline.analyze(manifest, rows)
        manifest, rows = fixture()
        rows.append(copy.deepcopy(row(rows, "capture_ack")))
        self.assertEqual(timeline.analyze(manifest, rows)["trials"][0]["status"], "ACK_NOT_PROVEN")

    def test_clock_run_and_boot_mixing_rejected(self):
        for event, field, value in (("selection_boundary", "runID", "run-b"),
                                    ("capture_ack", "clock", "wallClock"),
                                    ("selection_boundary", "bootID", "boot-b")):
            with self.subTest(field=field):
                manifest, rows = fixture()
                row(rows, event)[field] = value
                with self.assertRaises(timeline.EvidenceError):
                    timeline.analyze(manifest, rows)

    def test_immutable_file_hash_and_sidecar_run_are_required(self):
        manifest, rows = fixture()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            content = "ordinary log text\n" + "\n".join(
                ("RIFTLET_ARRIVAL_TRACE " if r["event"] == "input_windows_observed" else "")
                + json.dumps(r) for r in rows) + "\n"
            (root / "app.log").write_text(content)
            manifest["traces"] = [{"path": "app.log", "sha256": hashlib.sha256(content.encode()).hexdigest(),
                                   "runID": "run-a", "bootID": "boot-a", "clock": timeline.CLOCK}]
            path = root / "manifest.json"
            path.write_text(json.dumps(manifest))
            loaded, actual, hashes = timeline.load(path)
            self.assertEqual(actual, rows)
            self.assertEqual(len(hashes), 1)
            self.assertEqual(timeline.analyze(loaded, actual)["trials"][0]["status"], "ACK_BEFORE_CLICK_PROVEN")
            (root / "app.log").write_text(content + "later event\n")
            with self.assertRaisesRegex(timeline.EvidenceError, "trace_hash"):
                timeline.load(path)
            (root / "app.log").write_text(content)
            manifest["traces"][0]["bootID"] = "boot-b"
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(timeline.EvidenceError, "sidecar"):
                timeline.load(path)


if __name__ == "__main__":
    unittest.main()
