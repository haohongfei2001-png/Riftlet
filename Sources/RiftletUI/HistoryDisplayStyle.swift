import Foundation

/// Presentation only. This is never stored on an asset or in the history database.
public enum HistoryDisplayStyle: String, CaseIterable, Sendable {
    case current
    case imageGrid

    public var title: String { title(copy: .current) }

    public func title(copy: ProductCopy) -> String {
        switch self {
        case .current: return copy.text("当前视图", "List")
        case .imageGrid: return copy.text("图像网格", "Image Grid")
        }
    }
}
