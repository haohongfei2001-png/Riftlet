import AppKit
import XCTest
@testable import RiftletUI

/// AppKit control actions; no browser, capture or durable user data.
final class QuietEdgeSettingsTests: XCTestCase {
    @MainActor private func find<T: NSView>(_ id: String, in view: NSView, as: T.Type) -> T? {
        if view.identifier?.rawValue == id { return view as? T }
        return view.subviews.lazy.compactMap { self.find(id, in: $0, as: T.self) }.first
    }
    @MainActor func testGeometryAndSixPositionsUseExplicitSavedHostValues() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer unavailable") }
        var value = RiftSettingsSnapshot(); var changes: [RiftSettingsChange] = []
        let controller = RiftSetupController(onRecheck:{},onOpenSource:{},onPermission:{},onDismiss:{},onSettingsChange:{ change in
            changes.append(change)
            switch change {
            case let .geometry(h,d,n): value.configuration.hiddenFraction=h;value.configuration.outerInset=d;value.configuration.visibleCountPreference=n
            case .placement(let p):value.configuration.placement=p
            default:break
            }
            return value
        })
        defer { controller.close() }
        controller.updateSettings(value); controller.show(section:.display)
        let root = try XCTUnwrap(NSApp.windows.first{$0.identifier == RiftSetupController.windowIdentifier}?.contentView)
        let h = try XCTUnwrap(find("settings.occlusion",in:root,as:NSTextField.self))
        let d = try XCTUnwrap(find("settings.inset",in:root,as:NSTextField.self))
        let n = try XCTUnwrap(find("settings.visibleCount",in:root,as:NSTextField.self))
        let save = try XCTUnwrap(find("settings.geometrySave",in:root,as:NSButton.self))
        h.stringValue="90";d.stringValue="0";n.stringValue="10"
        XCTAssertTrue(changes.isEmpty)
        save.performClick(nil)
        XCTAssertEqual(changes,[.geometry(hiddenFraction:0.9,outerInset:0,visibleCount:10)])
        for p in RiftPlacement.allCases {
            let button = try XCTUnwrap(find("settings.placement."+p.rawValue,in:root,as:NSButton.self))
            button.performClick(nil);XCTAssertEqual(value.configuration.placement,p)
        }
        let before=changes.count;n.stringValue="1.5";save.performClick(nil)
        XCTAssertEqual(changes.count,before,"Invalid count cannot be silently rounded")
    }
    @MainActor func testFailedGeometryWriteRestoresSavedValues() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("WindowServer unavailable") }
        let controller=RiftSetupController(onRecheck:{},onOpenSource:{},onPermission:{},onDismiss:{},onSettingsChange:{_ in throw CocoaError(.fileWriteNoPermission)})
        defer {controller.close()}
        controller.updateSettings(.init());controller.show(section:.display)
        let root=try XCTUnwrap(NSApp.windows.first{$0.identifier == RiftSetupController.windowIdentifier}?.contentView)
        let h=try XCTUnwrap(find("settings.occlusion",in:root,as:NSTextField.self));h.stringValue="75"
        try XCTUnwrap(find("settings.geometrySave",in:root,as:NSButton.self)).performClick(nil)
        XCTAssertEqual(h.stringValue,"25")
    }
}
