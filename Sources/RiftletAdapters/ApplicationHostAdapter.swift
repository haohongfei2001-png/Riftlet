/// Implementations freeze the actual foreground receiver and validate the same
/// process lifetime and window (plus the active tab for a browser). Frozen
/// values are ephemeral. They never confer permission to append or reconcile.
protocol ApplicationHostAdapter {
    associatedtype FrozenTarget: Equatable
    func freeze() throws -> FrozenTarget
    func revalidate(_ original: FrozenTarget) throws
}
