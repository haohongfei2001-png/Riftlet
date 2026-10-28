"""Reject misleading or unsafe evidence manifests, using disposable PNG fixtures."""
import base64
import copy
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import struct
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/capture-native-visual-evidence.py"
SPEC = importlib.util.spec_from_file_location("native_visual_evidence", SCRIPT)
CAPTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAPTURE)


class NativeVisualManifestTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="riftlet-visual-manifest-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = "1" * 40
        self.checkout = "2" * 40
        self.png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aH1kAAAAASUVORK5CYII=")
        (self.root / "native.png").write_bytes(self.png)
        self.report = {"status": "CAPTURED_NATIVE_WINDOWSERVER", "source": self.source,
            "checkout": self.checkout, "syntheticOnly": True,
            "otherApplicationPixelsCaptured": False, "screenCapturePermissionRequested": False,
            "performanceBenchmark": False,
            "captureKind": "single-product-window",
            "systemAccessibilityAtStart": {"reduceMotion": False, "increaseContrast": False, "reduceTransparency": False},
            "systemAccessibilityAtEnd": {"reduceMotion": False, "increaseContrast": False, "reduceTransparency": False},
            **{key: "NOT_RUN" for key in ("physicalInput", "realScreenshot", "realUpload", "crossApplicationFocus", "productionWindowOrder")},
            "frames": [{"status": "CAPTURED_NATIVE_WINDOWSERVER", "file": "native.png", "pixels": [1, 1],
                        "bytes": len(self.png), "sha256": hashlib.sha256(self.png).hexdigest(), "resized": False,
                        "source": self.source, "checkout": self.checkout, "syntheticOnly": True, "receiptEvidence": False,
                        "pngProcessingOnMainThread": False,
                        "selectedOwnWindowCount": 1, "productWindowCount": 1, "ownWindowNumbersFrontToBack": [123],
                        "windowOrdering": "NSApplication.enumerateWindows(orderedFrontToBack)"}]}

    def verify(self, report=None):
        CAPTURE.verify_capture(self.root, report or self.report, self.source, self.checkout)

    def test_exact_manifest_and_explicit_unavailable_capture_are_distinct(self):
        self.verify()
        report = copy.deepcopy(self.report)
        report["status"] = "NOT_RUN"
        report["frames"] = [{"status": "NOT_RUN", "reason": "ownWindowServerCaptureUnavailable"}]
        self.verify(report)

    def test_missing_frames_cannot_be_claimed_as_captured(self):
        self.report["frames"] = []
        with self.assertRaisesRegex(ValueError, "missingFrames"):
            self.verify()

    def test_changed_pixels_or_bytes_are_rejected(self):
        self.report["frames"][0]["pixels"] = [2, 2]
        with self.assertRaisesRegex(ValueError, "pixelDimensionMismatch"):
            self.verify()
        self.report["frames"][0]["pixels"] = [1, 1]
        (self.root / "native.png").write_bytes(self.png + b"changed")
        with self.assertRaisesRegex(ValueError, "frameHashMismatch"):
            self.verify()

    def test_path_escape_and_symlink_are_rejected(self):
        self.report["frames"][0]["file"] = "../native.png"
        with self.assertRaisesRegex(ValueError, "unsafeFramePathOrStatus"):
            self.verify()
        self.report["frames"][0]["file"] = "linked.png"
        (self.root / "linked.png").symlink_to("native.png")
        with self.assertRaisesRegex(ValueError, "missingRegularFrame"):
            self.verify()

    def test_claims_cannot_be_promoted_to_real_input_or_upload(self):
        for key in ("physicalInput", "realUpload", "crossApplicationFocus"):
            with self.subTest(key=key):
                report = copy.deepcopy(self.report)
                report[key] = "PASS"
                with self.assertRaisesRegex(ValueError, "unsupportedAcceptanceClaim"):
                    self.verify(report)

    def test_png_processing_cannot_silently_block_the_native_run_loop(self):
        for value in (None, True, "false"):
            report = copy.deepcopy(self.report)
            report["frames"][0]["pngProcessingOnMainThread"] = value
            with self.assertRaisesRegex(ValueError, "pngProcessingMustLeaveNativeRunLoopAvailable"):
                self.verify(report)

    def test_partial_capture_and_wrong_source_fail_closed(self):
        self.report["frames"].append({"status": "NOT_RUN"})
        with self.assertRaisesRegex(ValueError, "partialCaptureClaimedComplete"):
            self.verify()
        self.report["source"] = self.checkout
        with self.assertRaisesRegex(ValueError, "sourceMismatch"):
            self.verify()

    def test_composite_cannot_pass_with_only_backdrop_or_no_product_pixels(self):
        self.report["captureKind"] = "owned-product-composite"
        frame = self.report["frames"][0]
        frame["productWindowCount"] = 0
        with self.assertRaisesRegex(ValueError, "missingProductWindow"):
            self.verify()
        frame.update(selectedOwnWindowCount=2, productWindowCount=1,
                     ownWindowNumbersFrontToBack=[456, 123], minimumProductDifferencePixels=64,
                     productDifferencePixelCount=0)
        with self.assertRaisesRegex(ValueError, "missingProductPixels"):
            self.verify()
        frame["productDifferencePixelCount"] = 64  # A one-pixel PNG cannot substantiate this.
        with self.assertRaisesRegex(ValueError, "missingProductPixels"):
            self.verify()

    def test_duplicate_window_ids_cannot_claim_an_extra_product_window(self):
        self.report["captureKind"] = "owned-product-composite"
        self.report["frames"][0].update(selectedOwnWindowCount=2, productWindowCount=1,
                                       ownWindowNumbersFrontToBack=[123, 123])
        with self.assertRaisesRegex(ValueError, "invalidOwnWindowSet"):
            self.verify()

    def test_actual_accessibility_snapshot_cannot_be_omitted_or_loosely_coerced(self):
        for value in (None, {}, {"reduceMotion": "false", "increaseContrast": False, "reduceTransparency": False}):
            self.report["systemAccessibilityAtStart"] = value
            with self.assertRaisesRegex(ValueError, "missingSystemAccessibility"):
                self.verify()

    def test_normal_cases_cannot_silently_use_reduced_motion_or_opaque_materials(self):
        self.report["helperReducedMotionOverride"] = False
        CAPTURE.verify_case_behavior([], self.report)
        for key in ("reduceMotion", "increaseContrast", "reduceTransparency"):
            report = copy.deepcopy(self.report)
            report["systemAccessibilityAtStart"][key] = True
            with self.assertRaisesRegex(ValueError, "normalSystemAccessibilityRequired"):
                CAPTURE.verify_case_behavior([], report)

    def test_magnet_filename_requires_real_start_source_and_expected_end(self):
        flags = ["--visual-timeline", "--visual-magnet"]
        self.report["helperReducedMotionOverride"] = False
        events = [
            {"event": "synthetic_asset_ready", "sourceProvided": True},
            {"event": "native_arrival_boundary", "phase": "decorationStarted", "mode": "magnet"},
            {"event": "native_arrival_boundary", "phase": "decorationEnded", "mode": "magnet", "reason": "finished"},
            {"event": "native_presentation_boundary", "phase": "swallowClose"}]
        self.report["events"] = events
        CAPTURE.verify_case_behavior(flags, self.report)
        events[0]["sourceProvided"] = False
        with self.assertRaisesRegex(ValueError, "magnetWasNotExercised"):
            CAPTURE.verify_case_behavior(flags, self.report)
        events[0]["sourceProvided"] = True
        with self.assertRaisesRegex(ValueError, "magnetCompletionNotObserved"):
            CAPTURE.verify_case_behavior(flags + ["--visual-cancel-arrival"], self.report)
        events[2]["reason"] = "cancelled"
        CAPTURE.verify_case_behavior(flags + ["--visual-cancel-arrival"], self.report)

    def test_reduced_system_capture_requires_real_policy_and_native_static_outcome(self):
        self.report["helperReducedMotionOverride"] = False
        flags = ["--visual-timeline", "--visual-magnet"]
        with self.assertRaisesRegex(ValueError, "reducedSystemAccessibilityRequired"):
            CAPTURE.verify_case_behavior(flags, self.report, "reduced")
        for key in ("systemAccessibilityAtStart", "systemAccessibilityAtEnd"):
            self.report[key] = {name: True for name in self.report[key]}
        self.report["events"] = [
            {"event": "native_arrival_boundary", "phase": "rowAvailable", "mode": "none"},
            {"event": "native_presentation_boundary", "phase": "swallowScheduled", "duration": 0.08},
            {"event": "native_presentation_boundary", "phase": "swallowClose"}]
        CAPTURE.verify_case_behavior(flags, self.report, "reduced")
        self.report["events"][0]["mode"] = "magnet"
        with self.assertRaisesRegex(ValueError, "reducedArrivalPolicyNotObserved"):
            CAPTURE.verify_case_behavior(flags, self.report, "reduced")

    def test_filter_is_limited_to_registered_cases_and_preserves_all_default_cases(self):
        self.assertEqual(len(CAPTURE.selected_cases([])), 46)
        self.assertEqual([name for name, _ in CAPTURE.selected_cases(["queue-dark", "entry-dark", "motion-magnet", "queue-dark"])],
                         ["queue-dark", "entry-dark", "motion-magnet"])
        with self.assertRaisesRegex(ValueError, "Unknown registered case"):
            CAPTURE.selected_cases(["../../other"])

    def test_feedback_records_require_exact_local_states_and_visible_content_observation(self):
        self.report["helperReducedMotionOverride"] = False
        flags = ["--visual-window", "feedback", "--visual-feedback-records"]
        with self.assertRaisesRegex(ValueError, "expandedLocalFeedbackRecordsNotObserved"):
            CAPTURE.verify_case_behavior(flags, self.report)
        event = {"event": "native_evidence_feedback_records", "fixtureRecordCount": 2,
                 "fixtureStates": ["cancelled", "queued"], "bodyAndStateMatched": True,
                 "expanded": True, "softwareSelection": True, "physical": False,
                 "networkEnabled": False, "receiptEvidence": False}
        self.report["events"] = [event]
        CAPTURE.verify_case_behavior(flags, self.report)
        for key, value in (("fixtureStates", ["delivered", "queued"]), ("expanded", False),
                           ("bodyAndStateMatched", False), ("receiptEvidence", True)):
            report = copy.deepcopy(self.report); report["events"][0][key] = value
            with self.assertRaisesRegex(ValueError, "expandedLocalFeedbackRecordsNotObserved"):
                CAPTURE.verify_case_behavior(flags, report)

    def movie_fixture(self):
        # A minimal container fixture for integrity/metadata rejection tests,
        # not a claim that these bytes contain playable native video.
        data = b"".join(struct.pack(">I4s", 8 + len(body), kind) + body
                        for kind, body in ((b"ftyp", b"qt  "), (b"moov", b""), (b"mdat", b"fixture")))
        (self.root / "native-motion.mov").write_bytes(data)
        self.report["movie"] = {"status": "RECORDED_NATIVE_WINDOWSERVER", "file": "native-motion.mov",
            "source": self.source, "checkout": self.checkout,
            "syntheticOnly": True, "receiptEvidence": False, "physicalInput": "NOT_RUN",
            "performanceBenchmark": False, "contentResized": False,
            "contentPixels": [1, 1], "encodedPixels": [2, 2], "paddingPixels": [1, 1],
            "presentationSeconds": [0.0, 0.038, 0.079], "encodedFrameCount": 3,
            "targetFrameRate": 30, "maximumPoolBuffers": 3,
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    def test_movie_integrity_and_independent_not_run(self):
        self.movie_fixture(); self.verify()
        self.report["movie"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "movieHashMismatch"): self.verify()
        self.report["movie"] = {"status": "NOT_RUN", "reason": "encoderUnavailable"}
        self.verify()  # PNG evidence stays valid, video remains explicitly NOT_RUN.

    def test_movie_pts_must_be_actual_monotonic_and_counted(self):
        self.movie_fixture()
        for times, count in (([0.0, 0.038, 0.038], 3), ([0.0, 0.079, 0.038], 3),
                             ([0.0, float("nan"), 0.079], 3), ([0.0, 0.038, 0.079], 4)):
            self.report["movie"].update(presentationSeconds=times, encodedFrameCount=count)
            with self.assertRaisesRegex(ValueError, "movieTimestampsInvalid"): self.verify()

    def test_movie_scope_padding_source_and_path_cannot_drift(self):
        for field, value, message in (("contentResized", True, "movieScopeMismatch"),
                ("paddingPixels", [3, 3], "movieDimensionsMismatch"),
                ("source", self.checkout, "movieSourceMismatch"),
                ("file", "../native-motion.mov", "unsafeMoviePathOrStatus")):
            self.movie_fixture(); self.report["movie"][field] = value
            with self.assertRaisesRegex(ValueError, message): self.verify()


if __name__ == "__main__":
    unittest.main()
