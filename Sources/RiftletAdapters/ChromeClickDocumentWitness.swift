import Foundation

/// Runs at the ordinary click boundary in the Chrome Apple Events world. It
/// registers no upload observer and returns only a closed read-only result.
struct ChromeClickDocumentWitness {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }

    func bindScript(address: String, program: WebPageProgram) throws -> String {
        guard program.sourceID == ChatGPTWebPageProgram.sourceID else { throw WebAdapterError.invalidRequest }
        let expected = String(decoding: try JSONEncoder().encode(address), as: UTF8.self)
        return "(()=>{try{return (\(program.functionSource))({action:'pinTarget',clickWitnessID:'\(id.uuidString)',address:\(expected)},{});}catch{return 'refused';}})()"
    }
}
