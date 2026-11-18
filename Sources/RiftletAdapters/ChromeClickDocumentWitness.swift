import Foundation

/// Runs at the ordinary click boundary in the Chrome Apple Events world. It
/// registers no upload observer and returns only a closed read-only result.
struct ChromeClickDocumentWitness {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }

    enum Host { case chrome, edge }

    func bindScript(address: String, program: WebPageProgram, host: Host = .chrome) throws -> String {
        // Each browser pins with the version its ordinary input route executes.
        // Older observation-only programs cannot acquire a click witness.
        let activeSource = host == .edge ? ChatGPTWebPageProgram.priorEdgeSource : ChatGPTWebPageProgram.sourceID
        guard program.sourceID == activeSource else { throw WebAdapterError.invalidRequest }
        let expected = String(decoding: try JSONEncoder().encode(address), as: UTF8.self)
        return "(()=>{try{return (\(program.functionSource))({action:'pinTarget',clickWitnessID:'\(id.uuidString)',address:\(expected)},{});}catch{return 'refused';}})()"
    }
}
