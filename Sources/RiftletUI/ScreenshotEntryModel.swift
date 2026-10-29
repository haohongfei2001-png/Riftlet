import Foundation
import RiftletCapture

/// Logical screen points. The host supplies the screen and optional anchor;
/// this value neither reads nor writes the application's saved configuration.
public struct ScreenshotEntryConfiguration: Equatable, Sendable {
    public var controlSize: CGFloat = 36
    public var upperControlSize: CGFloat = 30
    public var slotPitch: CGFloat = 32
    public var anchorFromTop: CGFloat = 246
    public var anchorRightInset: CGFloat = 32
    public var screenPadding: CGFloat = 8
    public var shadowOutset: CGFloat = 14
    public var expansionDuration: TimeInterval = 0.180
    public var queueClearance: CGFloat = 30
    public var optics = ScreenshotEntryOpticalConfiguration()

    public init() {}

    var validated: Self {
        let finite = [controlSize, upperControlSize, slotPitch, anchorFromTop,
                      anchorRightInset, screenPadding, shadowOutset, queueClearance]
        guard finite.allSatisfy({ $0.isFinite }), (28...64).contains(controlSize),
              (24...controlSize).contains(upperControlSize),
              slotPitch >= upperControlSize, slotPitch <= 64,
              anchorFromTop >= 0, anchorRightInset >= 0,
              screenPadding >= 0, screenPadding <= 64,
              shadowOutset >= 0, shadowOutset <= 32,
              queueClearance > 0, queueClearance <= 128,
              expansionDuration.isFinite, (0...1).contains(expansionDuration),
              optics.isValid else { return Self() }
        return self
    }
}

public enum ScreenshotEntrySlot: Int, CaseIterable, Sendable {
    case anchor = 0, near = 1, far = 2, more = 3
}

public struct ScreenshotEntryLayout: Equatable, Sendable {
    public let anchor: CGPoint
    public let railFrame: CGRect
    public let visualWindowFrame: CGRect
    public let controlFrames: [CGRect]
    public var entryFrame: CGRect { controlFrames[0] }

    /// A nil result means this screen has no room for the complete control rail.
    public static func make(screenFrame: CGRect, visibleFrame: CGRect,
                            anchor proposedAnchor: CGPoint? = nil,
                            configuration input: ScreenshotEntryConfiguration = .init()) -> Self? {
        let c = input.validated
        let size = c.controlSize, height = size + 3 * c.slotPitch
        guard [screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height,
               visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height]
            .allSatisfy({ $0.isFinite }), screenFrame.width > 0, screenFrame.height > 0,
              visibleFrame.width >= size + 2 * c.screenPadding,
              visibleFrame.height >= height + 2 * c.screenPadding else { return nil }
        let fallback = CGPoint(x: screenFrame.maxX - c.anchorRightInset,
                               y: screenFrame.maxY - c.anchorFromTop)
        let requested = proposedAnchor.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil } ?? fallback
        let center = CGPoint(
            x: min(visibleFrame.maxX - c.screenPadding - size / 2,
                   max(visibleFrame.minX + c.screenPadding + size / 2, requested.x)),
            y: min(visibleFrame.maxY - c.screenPadding - height + size / 2,
                   max(visibleFrame.minY + c.screenPadding + size / 2, requested.y)))
        let rail = CGRect(x: center.x - size / 2, y: center.y - size / 2,
                          width: size, height: height)
        let controls = ScreenshotEntrySlot.allCases.map { slot -> CGRect in
            let hitSize = slot == .anchor ? size : c.upperControlSize
            return CGRect(x: center.x - hitSize / 2,
                          y: center.y + CGFloat(slot.rawValue) * c.slotPitch - hitSize / 2,
                          width: hitSize, height: hitSize)
        }
        return Self(anchor: center, railFrame: rail,
                    visualWindowFrame: rail.insetBy(dx: -c.shadowOutset, dy: -c.shadowOutset),
                    controlFrames: controls)
    }
}

enum ScreenshotEntryAction: Equatable {
    case begin(ScreenshotMode), select(ScreenshotMode), cancel, options
}

/// A session owns its physical mode slots. A setting changes the next session;
/// a selection changes only the active role, never any slot's mode or position.
struct ScreenshotEntrySession: Equatable {
    private(set) var defaultMode: ScreenshotMode
    private(set) var mode: ScreenshotMode
    private(set) var isExpanded = false
    private(set) var modes: [ScreenshotMode]

    init(defaultMode: ScreenshotMode = .window) {
        self.defaultMode = defaultMode
        mode = defaultMode
        modes = Self.slots(for: defaultMode)
    }

    private static func slots(for mode: ScreenshotMode) -> [ScreenshotMode] {
        [mode] + [ScreenshotMode.region, .window, .fullScreen].filter { $0 != mode }
    }

    mutating func setDefaultMode(_ value: ScreenshotMode) { defaultMode = value }

    mutating func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded {
            mode = defaultMode
            modes = Self.slots(for: defaultMode)
        }
    }

    mutating func setMode(_ value: ScreenshotMode) { mode = value }

    var activeSlot: ScreenshotEntrySlot {
        ScreenshotEntrySlot(rawValue: modes.firstIndex(of: mode) ?? 0) ?? .anchor
    }

    func action(for slot: ScreenshotEntrySlot) -> ScreenshotEntryAction? {
        guard isExpanded else { return slot == .anchor ? .begin(defaultMode) : nil }
        guard slot != .more else { return .options }
        let selected = modes[slot.rawValue]
        return selected == mode ? .cancel : .select(selected)
    }
}

public struct ScreenshotEntryOpticalConfiguration: Equatable, Sendable {
    public var glyphFull: CGFloat = 0.35
    public var glyphEnter: CGFloat = 0.60
    public var surfaceFull: CGFloat = 0.08
    public var surfaceEnter: CGFloat = 0.46
    public var exitScale: CGFloat = 1.5
    public var forecastDuration: TimeInterval = 0.700
    public var forecastDecay: TimeInterval = 0.240
    public init() {}

    var isValid: Bool {
        [glyphFull, glyphEnter, surfaceFull, surfaceEnter, exitScale].allSatisfy { $0.isFinite }
            && glyphFull >= 0 && glyphEnter > glyphFull && glyphEnter <= 2
            && surfaceFull >= 0 && surfaceEnter > surfaceFull && surfaceEnter <= 2
            && exitScale >= 1 && exitScale <= 3
            && forecastDuration.isFinite && forecastDuration > 0.180 && forecastDuration <= 2
            && forecastDecay.isFinite && forecastDecay > 0 && forecastDecay <= 2
    }
}

struct ScreenshotEntryAlphas: Equatable {
    var glyph: CGFloat = 0
    var surface: CGFloat = 0
}

/// The prototype's two independent optical envelopes. This model contains no
/// event interception, click threshold, screen query, or delayed activation.
struct ScreenshotEntryOptics {
    private(set) var alphas = ScreenshotEntryAlphas()
    private(set) var point: CGPoint?
    private var previous: (point: CGPoint, time: TimeInterval)?
    private var velocity = CGPoint.zero // points per millisecond, as in the prototype
    private var lastPointerAt: TimeInterval = 0
    private var forecast: CGFloat = 0
    private var glyphMemory: CGFloat = 0
    private var surfaceMemory: CGFloat = 0
    private var pointerIsDown = false
    private var lastFrameAt: TimeInterval?
    private(set) var isSettled = true

    mutating func observe(point newPoint: CGPoint?, at time: TimeInterval,
                          anchor: CGPoint, screenFrame: CGRect,
                          pointerIsDown: Bool = false,
                          configuration c: ScreenshotEntryOpticalConfiguration = .init()) {
        self.pointerIsDown = pointerIsDown
        guard let p = newPoint, p.x.isFinite, p.y.isFinite,
              screenFrame.contains(p), time.isFinite else {
            point = nil; previous = nil; velocity = .zero; forecast = 0
            glyphMemory = 0; surfaceMemory = 0; isSettled = false
            return
        }
        var raw: CGPoint?
        if let old = previous {
            let elapsed = (time - old.time) * 1_000
            if elapsed > 0 && elapsed < 180 {
                let v = CGPoint(x: (p.x - old.point.x) / max(2, elapsed),
                                y: (p.y - old.point.y) / max(2, elapsed))
                raw = v
                let weight = 1 - exp(-elapsed / 28)
                velocity.x += (v.x - velocity.x) * weight
                velocity.y += (v.y - velocity.y) * weight
            } else { velocity = .zero }
        }
        point = p; previous = (p, time); lastPointerAt = time; forecast = 0
        if let raw {
            let dx = anchor.x - p.x, dy = anchor.y - p.y
            let distance = hypot(dx, dy), speed = hypot(velocity.x, velocity.y)
            let dot = dx * velocity.x + dy * velocity.y
            let alignment = dot / max(0.001, distance * speed)
            let arrival = dot / max(0.0001, speed * speed)
            let miss = hypot(dx - velocity.x * arrival, dy - velocity.y * arrival)
            if dx * raw.x + dy * raw.y > 0 && arrival > 0 {
                forecast = Self.smooth(0.5, 0.96, alignment) * exp(-miss * miss / 10_000)
                    * (1 - Self.smooth(180, c.forecastDuration * 1_000, arrival))
                    * (1 - Self.smooth(0.82 * screenFrame.width, 1.35 * screenFrame.width, distance))
                    * Self.smooth(0.02, 0.18, speed)
            }
        }
        isSettled = false
    }

    mutating func resume(anchor: CGPoint, screenWidth: CGFloat,
                         configuration c: ScreenshotEntryOpticalConfiguration,
                         afterCancel: Bool) {
        // Preserve the actual displayed alpha; only the spatial memory changes.
        previous = nil; velocity = .zero; forecast = 0; pointerIsDown = false
        let d = point.map { hypot(anchor.x - $0.x, anchor.y - $0.y) } ?? .infinity
        glyphMemory = field(d, width: screenWidth, full: c.glyphFull, enter: c.glyphEnter,
                            exitScale: afterCancel ? c.exitScale : 1)
        surfaceMemory = field(d, width: screenWidth, full: c.surfaceFull, enter: c.surfaceEnter,
                              exitScale: afterCancel ? c.exitScale : 1)
        lastFrameAt = nil; isSettled = false
    }

    mutating func resumeClock() { lastFrameAt = nil; isSettled = false }

    mutating func target(at time: TimeInterval, anchor: CGPoint, screenWidth: CGFloat,
                         queueFrames: [CGRect], expanded: Bool, pressed: Bool,
                         configuration c: ScreenshotEntryConfiguration) -> ScreenshotEntryAlphas {
        if expanded || pressed { return ScreenshotEntryAlphas(glyph: 1, surface: 1) }
        guard let point, !pointerIsDown else {
            glyphMemory = 0; surfaceMemory = 0
            return ScreenshotEntryAlphas()
        }
        let d = hypot(anchor.x - point.x, anchor.y - point.y), o = c.optics
        glyphMemory = max(field(d, width: screenWidth, full: o.glyphFull, enter: o.glyphEnter),
                          min(glyphMemory, field(d, width: screenWidth, full: o.glyphFull,
                                                 enter: o.glyphEnter, exitScale: o.exitScale)))
        surfaceMemory = max(field(d, width: screenWidth, full: o.surfaceFull, enter: o.surfaceEnter),
                            min(surfaceMemory, field(d, width: screenWidth, full: o.surfaceFull,
                                                     enter: o.surfaceEnter, exitScale: o.exitScale)))
        let prediction = forecast * exp(-max(0, time - lastPointerAt) / o.forecastDecay)
        let availability = Self.availability(at: point, queueFrames: queueFrames,
                                             clearance: c.queueClearance)
        return ScreenshotEntryAlphas(glyph: max(glyphMemory, prediction) * availability,
                                      surface: max(surfaceMemory, 0.18 * prediction) * availability)
    }

    @discardableResult
    mutating func advance(at time: TimeInterval, anchor: CGPoint, screenWidth: CGFloat,
                          queueFrames: [CGRect], expanded: Bool, pressed: Bool = false,
                          configuration c: ScreenshotEntryConfiguration = .init()) -> ScreenshotEntryAlphas {
        let dt = lastFrameAt.map { min(34, max(1, (time - $0) * 1_000)) } ?? 1_000 / 60
        lastFrameAt = time
        let goal = target(at: time, anchor: anchor, screenWidth: screenWidth,
                          queueFrames: queueFrames, expanded: expanded, pressed: pressed, configuration: c)
        alphas.glyph = step(alphas.glyph, goal.glyph, dt: dt, rise: 18, fall: 170, up: 0.26, down: 0.08)
        alphas.surface = step(alphas.surface, goal.surface, dt: dt, rise: 96, fall: 150, up: 0.065, down: 0.06)
        let predicting = !expanded && point != nil
            && forecast * exp(-max(0, time - lastPointerAt) / c.optics.forecastDecay) > 0.00015
        isSettled = abs(alphas.glyph - goal.glyph) <= 0.00015
            && abs(alphas.surface - goal.surface) <= 0.00015 && !predicting
        if isSettled { lastFrameAt = nil }
        return alphas
    }

    static func availability(at point: CGPoint, queueFrames: [CGRect], clearance: CGFloat) -> CGFloat {
        queueFrames.reduce(CGFloat(1)) { value, frame in
            guard !frame.isEmpty, !frame.isNull, !frame.isInfinite,
                  [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }) else { return value }
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            return value * smooth(0, max(1, clearance), hypot(dx, dy))
        }
    }

    private func field(_ distance: CGFloat, width: CGFloat, full: CGFloat, enter: CGFloat,
                       exitScale: CGFloat = 1) -> CGFloat {
        1 - Self.smooth(full * width, enter * width * exitScale, distance)
    }

    private func step(_ value: CGFloat, _ goal: CGFloat, dt: CGFloat,
                      rise: CGFloat, fall: CGFloat, up: CGFloat, down: CGFloat) -> CGFloat {
        let rising = goal > value
        let delta = (goal - value) * (1 - exp(-dt / (rising ? rise : fall)))
        let cap = (rising ? up : down) * min(1, dt / (1_000 / 60))
        let next = min(1, max(0, value + max(-cap, min(cap, delta))))
        if goal == 0 && next < 0.00015 { return 0 }
        if goal == 1 && next > 0.99985 { return 1 }
        return next
    }

    static func smooth(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        let x = min(1, max(0, (value - lower) / max(0.0001, upper - lower)))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}

/// Reversing an unfinished expansion continues from its current height. There
/// are no delayed completion handlers that can close a newly opened session.
struct ScreenshotEntryRailMotion {
    private(set) var value: CGFloat = 0
    private(set) var goal: CGFloat = 0
    private var from: CGFloat = 0
    private var start: TimeInterval = 0
    private var duration: TimeInterval = 0.180
    var isSettled: Bool { value == goal }

    mutating func setExpanded(_ expanded: Bool, at time: TimeInterval,
                              duration: TimeInterval, animated: Bool) {
        advance(at: time)
        let next: CGFloat = expanded ? 1 : 0
        guard next != goal else { if !animated { value = next }; return }
        from = value; goal = next; start = time
        self.duration = max(0.064, duration * abs(next - value))
        if !animated || duration == 0 { value = goal }
    }

    mutating func advance(at time: TimeInterval) {
        guard value != goal else { return }
        let p = min(1, max(0, (time - start) / duration))
        value = p == 1 ? goal : from + (goal - from) * ScreenshotEntryOptics.smooth(0, 1, p)
    }

    mutating func shiftClock(by elapsed: TimeInterval) { start += max(0, elapsed) }
}

/// The cancel cover may travel between fixed mode slots, while the action at
/// the destination has already changed. A reverse starts at its current place.
struct ScreenshotEntryCancelMotion {
    private(set) var value: CGFloat = 0
    private(set) var goal: CGFloat = 0
    private var from: CGFloat = 0
    private var start: TimeInterval = 0
    var isSettled: Bool { value == goal }

    mutating func move(to slot: ScreenshotEntrySlot, at time: TimeInterval, animated: Bool) {
        advance(at: time)
        let next = CGFloat(min(2, slot.rawValue))
        guard next != goal else { if !animated { value = next }; return }
        from = value; goal = next; start = time
        if !animated { value = next }
    }

    mutating func advance(at time: TimeInterval) {
        guard value != goal else { return }
        let progress = min(1, max(0, (time - start) / 0.100))
        value = progress == 1 ? goal : from + (goal - from) * ScreenshotEntryOptics.smooth(0, 1, progress)
    }

    mutating func shiftClock(by elapsed: TimeInterval) { start += max(0, elapsed) }
}
