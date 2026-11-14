import AppKit
import CoreGraphics
let values: [Int64] = [0, 1, 101, 32767, 32768, 65535, 65536, 0x12345678, Int64(Int32.max)]
guard let source = CGEventSource(stateID: .privateState) else { print("SOURCE_UNAVAILABLE"); exit(77) }
for value in values {
    guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                            mouseCursorPosition: CGPoint(x: 0, y: 0), mouseButton: .left) else { exit(1) }
    down.setIntegerValueField(.mouseEventClickState, value: 1)
    down.setIntegerValueField(.mouseEventNumber, value: value)
    down.setIntegerValueField(.eventSourceUserData, value: 100000000000001)
    guard let event = NSEvent(cgEvent: down) else { exit(1) }
    print("sent=\(value) cg=\(down.getIntegerValueField(.mouseEventNumber)) native=\(event.eventNumber) backCG=\(event.cgEvent?.getIntegerValueField(.mouseEventNumber) ?? -999) tag=\(event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? -999)")
}
print("ALLOCATION_ONLY_NO_POST_NO_UI")
