"""Disk-only admission tests with synthetic target receipts."""
import base64
import hashlib
import json
import unittest
from rapid_pair_admission import ROUTE, admit_pair, current_window, digest, observation


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.route = dict(zip(ROUTE, ["com.google.Chrome", "process-birth", "3", "4"]))
        self.created = dict(self.route, pid=17, family="chrome", phase="qaAddressConfirmed")
        self.before = dict(pid=17, sessionID="process-birth", dynamicSignature=True,
                           bundle="com.google.Chrome", windowIDs=["1"])
        self.page = dict(editor=True, uploadEntry=True, signedIn=True, documentID="doc",
                         composerID="editor", draftEpoch="generation", preparedBindingSHA256=[digest("a"), digest("b")])
        self.scope = dict(self.created, systemUptime=10.0, exactTemporaryURL=True, originalSelection=True,
                          originalSoleTab=True, systemForeground=True, dynamicSignature=True,
                          bundle=self.before["bundle"], currentWindowIDs=["3","5"], page=self.page)
        self.rows = [dict(assetID=str(i), sha256=digest(f"file{i}"), pixelsSHA256=digest(f"pixel{i}"),
                          inputWindowID=i, visualWindowID=i+10, state="VERIFIED_READ_ONLY", sampleCount=9,
                          maxReferenceRGBDifference=1, readOnlyPacketRoundtrip="VERIFIED",
                          profile="qa", pid=9, kernelCandidateIdentity="candidate-birth") for i in (1,2)]
        self.trace = [dict(event="preclick_lease", phase="armed", acknowledgedUptime=9,
                           requestIDDigest=key, hostEpochDigest=digest("epoch"))
                      for key in self.page["preparedBindingSHA256"]]

    def envelope(self):
        data = json.dumps(self.scope).encode()
        return {"payload": self.scope, "payloadBase64": base64.b64encode(data).decode(),
                "sha256": hashlib.sha256(data).hexdigest()}

    def snapshot(self):
        return observation(self.envelope(), self.created, self.before, self.route)

    def test_unrelated_window_closed_and_another_opened(self):
        result = admit_pair(self.rows, self.snapshot(), self.trace, 10.1)
        self.assertEqual(len(result["bindings"]), 2)

    def test_original_route_failures(self):
        for key, value in (("currentWindowIDs",["1","5"]), ("currentWindowIDs",["3","3"]),
                           ("originalSoleTab",False), ("originalSelection",False), ("sessionID","reused-pid")):
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                current_window(self.created,self.before["windowIDs"],dict(self.scope,**{key:value}))

    def test_bad_or_expired_receipt(self):
        envelope = self.envelope()
        for change in ({"sha256":"0"*64}, {"payload":dict(self.scope, pid=19)}):
            with self.assertRaises(ValueError):
                observation(dict(envelope,**change), self.created,self.before,self.route)
        with self.assertRaises(ValueError):
            admit_pair(self.rows,self.snapshot(),self.trace,13)

    def test_two_armed_records_are_insufficient(self):
        for pins in ([],[digest("a")],[digest("c"),digest("d")],[digest("a"),digest("a")]):
            self.page["preparedBindingSHA256"] = pins
            with self.subTest(count=len(pins)),self.assertRaises(ValueError):
                admit_pair(self.rows,self.snapshot(),self.trace,10.1)

    def test_competing_draft_wrong_epoch_and_spent_binding(self):
        snapshot = self.snapshot()
        snapshot["retainedTargets"][1]["draftGeneration"]="different"
        with self.assertRaises(ValueError):
            admit_pair(self.rows,snapshot,self.trace,10.1)
        self.trace[-1]["hostEpochDigest"]=digest("different")
        with self.assertRaises(ValueError):
            admit_pair(self.rows,self.snapshot(),self.trace,10.1)
        self.trace[-1].update(hostEpochDigest=digest("epoch"),phase="frozen")
        with self.assertRaises(ValueError):
            admit_pair(self.rows,self.snapshot(),self.trace,10.1)


if __name__ == "__main__":
    unittest.main()
