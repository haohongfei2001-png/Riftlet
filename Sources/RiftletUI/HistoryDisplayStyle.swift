import Foundation

/// Presentation only. This is never stored on an asset or in the history database.
public enum HistoryDisplayStyle: String, CaseIterable, Sendable {
    case current
    case imageGrid

    public var title: String {
        switch self {
        case .current: return "当前视图"
        case .imageGrid: return "图像网格"
        }
    }
}
