import AppKit
import RiftletUI

/// A complete, selectable local body with a bounded viewport. Long reports do
/// not turn the record list into thousands of lines or truncate the saved text.
@MainActor
final class FeedbackRecordBodyView: NSScrollView {
    private let body = NSTextView()
    private var viewportHeight: NSLayoutConstraint!
    private var measuredWidth: CGFloat = 0

    init(text: String, recordID: String) {
        super.init(frame: .zero)
        drawsBackground = false; borderType = .noBorder
        hasVerticalScroller = true; autohidesScrollers = true
        body.isEditable = false; body.isSelectable = true; body.isRichText = false
        body.drawsBackground = false; body.font = RiftVisualStyle.bodyFont; body.textColor = RiftVisualStyle.ink
        body.isVerticallyResizable = true; body.isHorizontallyResizable = false
        body.minSize = .zero; body.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        body.autoresizingMask = [.width]; body.textContainer?.widthTracksTextView = true
        body.textContainer?.lineFragmentPadding = 0; body.textContainerInset = NSSize(width: 0, height: 4)
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
        body.defaultParagraphStyle = paragraph; body.string = text
        body.identifier = NSUserInterfaceItemIdentifier("feedback.record.body.\(recordID)")
        body.setAccessibilityLabel("本机反馈 RF-\(recordID.prefix(8)) 的正文")
        documentView = body
        viewportHeight = heightAnchor.constraint(equalToConstant: 26); viewportHeight.isActive = true
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = contentSize.width
        guard width > 1, abs(width - measuredWidth) > 0.5,
              let container = body.textContainer, let manager = body.layoutManager else { return }
        measuredWidth = width
        body.setFrameSize(NSSize(width: width, height: max(26, body.frame.height)))
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = max(26, ceil(manager.usedRect(for: container).height) + 8)
        body.setFrameSize(NSSize(width: width, height: height))
        let visibleHeight = min(100, height)
        if abs(viewportHeight.constant - visibleHeight) > 0.5 { viewportHeight.constant = visibleHeight }
    }
}
