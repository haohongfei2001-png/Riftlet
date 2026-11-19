/// A single, target-bound handoff. A returned handoff describes delivery to the
/// input mechanism. Core admits upload START, completion and safe failure from
/// independent observations of the original operation.
@MainActor protocol AttachmentTransport {
    associatedtype Input
    associatedtype Handoff
    func handOff(_ input: Input) throws -> Handoff
}
