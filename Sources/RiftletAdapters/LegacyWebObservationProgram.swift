import Foundation

/// Routes observation of a retained v6/v7/v8 operation to its original observer.
/// Every input-side action uses the current program. Missing historical state
/// remains unknown; this wrapper cannot reconstruct leases or cleared proofs.
public enum LegacyWebObservationProgram {
    public static func wrapping(_ current: WebPageProgram) throws -> WebPageProgram {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Riftlet_RiftletAdapters.bundle"),
                  let packaged = Bundle(url: url) else { throw WebAdapterError.programUnavailable }
            resources = packaged
        } else {
            resources = Bundle.module
        }
        guard let url = resources.url(forResource: "legacy-web-observe", withExtension: "js"),
              let legacy = try? String(contentsOf: url, encoding: .utf8), !legacy.isEmpty,
              !current.functionSource.isEmpty else { throw WebAdapterError.programUnavailable }
        let source = """
        function riftletVersionedWebProgram(command,native) {
          if (command.action === 'observe') {
            const old = (\(legacy))(command,native);
            if (old !== null) return old;
          }
          return (\(current.functionSource))(command,native);
        }
        """
        guard source.utf8.count <= 128 * 1024 else { throw WebAdapterError.programUnavailable }
        // Keep the current input program's public source identifier. Historical
        // observation responses carry their own explicit v6/v7/v8 evidence IDs.
        return WebPageProgram(sourceID: current.sourceID, functionSource: source)
    }
}
