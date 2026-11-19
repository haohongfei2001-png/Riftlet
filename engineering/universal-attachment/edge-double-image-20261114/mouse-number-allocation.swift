import AppKit
import CoreGraphics
let source = CGEventSource(stateID: .privateState)!
for (index, tag) in [Int64(100000000000001), Int64(100000000000002)].enumerated() {
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 0, y: 0), mouseButton: .left)!
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    down.setIntegerValueField(.eventSourceUserData, value: tag)
    let native = NSEvent(cgEvent: down)!
    print("pair=\(index + 1) defaultCGNumber=\(down.getIntegerValueField(.mouseEventNumber)) nativeNumber=\(native.eventNumber) tagPreserved=\(native.cgEvent?.getIntegerValueField(.eventSourceUserData) == tag)")
    down.setIntegerValueField(.mouseEventNumber, value: Int64(index + 101))
    let numbered = NSEvent(cgEvent: down)!
    print("pair=\(index + 1) explicitCGNumber=\(down.getIntegerValueField(.mouseEventNumber)) nativeNumber=\(numbered.eventNumber) tagPreserved=\(numbered.cgEvent?.getIntegerValueField(.eventSourceUserData) == tag)")
}
print("ALLOCATION_ONLY_NO_POST_NO_UI")
