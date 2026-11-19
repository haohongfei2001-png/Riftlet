import Foundation

@main struct DiagnosticsScopeProbe {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fixtures = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        var count = 0
        for fixture in fixtures {
            let reply = fixture["reply"] as! [String: Any]
            let raw = reply["entryDiagnostics"] as! [String: Any]
            guard let parsed = AttachmentEntryDiagnostics.read(raw), let edge = parsed.edgeCalibration else {
                fatalError("actual page diagnostic sidecar did not decode")
            }
            for (key, value) in fixture["expected"] as! [String: NSNumber] {
                let traceKey = "edge" + key.prefix(1).uppercased() + key.dropFirst()
                precondition((edge.traceFields[traceKey] as? NSNumber) == value, traceKey)
            }
            let observation = reply["observation"] as! [String: Any]
            precondition(observation["state"] as? String == "inputTriggered")
            precondition(observation["uploadStart"] == nil && observation["completionEvidence"] == nil)
            precondition(parsed.traceFields["uploadStart"] == nil && parsed.traceFields["completionEvidence"] == nil)
            count += 1
        }
        let raw = (fixtures[0]["reply"] as! [String: Any])["entryDiagnostics"] as! [String: Any]
        for (key, value): (String, Any) in [("privateDraftText", "secret"), ("matchedNodes", 513),
            ("progressPercentMaximum", 101), ("originalTextUnchanged", 1), ("sampleNumber", 0)] {
            var changed = raw, facts = raw["edgeCalibration"] as! [String: Any]
            facts[key] = value; changed["edgeCalibration"] = facts
            let decoded = AttachmentEntryDiagnostics.read(changed)
            precondition(decoded?.stage == .observation && decoded?.edgeCalibration == nil)
            count += 1
        }
        print("PASS: \(count) actual JS-to-Swift reader cases (4 scope/state samples and 5 malformed sidecars); not XCTest or live commercial evidence")
    }
}
