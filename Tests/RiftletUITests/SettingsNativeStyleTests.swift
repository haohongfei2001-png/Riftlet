import AppKit
import XCTest
@testable import RiftletUI

final class SettingsNativeStyleTests: XCTestCase {
    @MainActor private func resolved(_ color: NSColor, in appearance: NSAppearance) throws -> NSColor {
        var value: NSColor?
        appearance.performAsCurrentDrawingAppearance { value = color.usingColorSpace(.sRGB) }
        return try XCTUnwrap(value)
    }

    private func assertComponents(_ actual: NSColor, _ expected: NSColor,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.0001, file: file, line: line)
    }

    private func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    @MainActor func testSameCachedColorsResolveNativeLightAndDarkWithoutChangingV2Tokens() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let matches: [NSAppearance.Name] = [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua, .aqua, .darkAqua]
        guard light.bestMatch(from: matches) == .aqua, dark.bestMatch(from: matches) == .darkAqua else {
            throw XCTSkip("System currently supplies high-contrast matching; ordinary palette test does not change that preference")
        }
        let tokens: [(SettingsColorRole, UInt32, UInt32)] = [
            (.window, 0xf7f9f8, 0x1c2420), (.surface, 0xffffff, 0x26312b),
            (.sidebar, 0xedf1ee, 0x19241e), (.ink, 0x172521, 0xedf3ef),
            (.secondary, 0x59675f, 0xadbab1), (.border, 0xdce2de, 0x3b4840),
            (.selection, 0xdcebe4, 0x294d3d), (.accent, 0x087f73, 0x65d2bb),
            (.accentInk, 0x086d63, 0x65d2bb), (.warning, 0x9b6429, 0xe8bc7e),
            (.warningBackground, 0xfaf3e7, 0x3a3020)
        ]
        for (role, lightToken, darkToken) in tokens {
            let cached = SettingsNativeStyle.color(role)
            assertComponents(try resolved(cached, in: light), rgb(lightToken))
            assertComponents(try resolved(cached, in: dark), rgb(darkToken))
            assertComponents(try resolved(cached, in: light), rgb(lightToken))
        }
    }

    @MainActor func testCachedTextAndBorderUseActualHighContrastAppearanceWhenAvailable() throws {
        // init(appearanceNamed:bundle:) loads a bundle resource; it cannot make
        // a portable subclass fixture from built-in names. Check the actual
        // effective appearance without modifying accessibility preferences.
        let appearance = NSApplication.shared.effectiveAppearance
        let match = appearance.bestMatch(from: [.accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
        guard match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua else {
            throw XCTSkip("Actual OS high-contrast appearance unavailable: NOT_RUN; no system preference changed")
        }
        let cachedLabel = SettingsNativeStyle.label("Synthetic caption", role: "caption")
        let cached: [(SettingsColorRole, NSColor)] = [(.secondary, try XCTUnwrap(cachedLabel.textColor)),
            (.ink, SettingsNativeStyle.color(.ink)), (.border, SettingsNativeStyle.color(.border))]
        let normal = try XCTUnwrap(NSAppearance(named: .aqua))
        for (role, color) in cached {
            let before = try resolved(color, in: normal)
            let system: NSColor = role == .border ? .separatorColor : .labelColor
            assertComponents(try resolved(color, in: appearance), try resolved(system, in: appearance))
            assertComponents(try resolved(color, in: normal), before)
        }
    }
}
