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
            **{key: "NOT_RUN" for key in ("physicalInput", "realScreenshot", "realUpload", "crossApplicationFocus", "productionWindowOrder")},
            "frames": [{"status": "CAPTURED_NATIVE_WINDOWSERVER", "file": "native.png", "pixels": [1, 1],
                        "bytes": len(self.png), "sha256": hashlib.sha256(self.png).hexdigest(), "resized": False,
                        "source": self.source, "checkout": self.checkout, "syntheticOnly": True, "receiptEvidence": False}]}

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

    def test_partial_capture_and_wrong_source_fail_closed(self):
        self.report["frames"].append({"status": "NOT_RUN"})
        with self.assertRaisesRegex(ValueError, "partialCaptureClaimedComplete"):
            self.verify()
        self.report["source"] = self.checkout
        with self.assertRaisesRegex(ValueError, "sourceMismatch"):
            self.verify()

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
