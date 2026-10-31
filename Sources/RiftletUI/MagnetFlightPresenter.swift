import AppKit
import QuartzCore

public enum MagnetFlightEndReason: String, Sendable {
    case finished, superseded, clicked, hidden, geometryChanged, reduceMotion
    case captureObserved, settingsChanged, cancelled, timedOut, closed
}

public struct MagnetFlightCompletion: Equatable, Sendable {
    public let assetID: UUID
    public let generation: UInt
    public let reason: MagnetFlightEndReason
}

/// Raw delegate timing is diagnostic only. A stopped callback with false does
/// not report a completed flight, and none of these events grants upload state.
public struct MagnetAnimationObservation: Sendable {
    public enum Phase: String, Sendable { case started, stopped }
    public let phase: Phase
    public let uptime: TimeInterval
    public let finished: Bool?
    public let wasMainThread: Bool
}

public struct MagnetFlightDiagnostics: Sendable {
    public let assetID: UUID?
    public let generation: UInt
    public let activePanelCount: Int
    public let windowNumber: Int?
    public let ignoresMouseEvents: Bool
    public let canBecomeKey: Bool
    public let canBecomeMain: Bool
    public let retainedImageCount: Int
    public let sampledFrameCount: Int
}

public extension MagnetMotionPlan {
    /// Shared by the desktop decoration and the settings NSView preview. The
    /// caller supplies the image and fixed clip. No asset/queue operation exists.
    func makeLayerAnimation(relativeTo origin: CGPoint) -> CAAnimationGroup {
        let times = keyframeTimes
        let samples = times.map { sample(at: $0).frame }
        let positions = CAKeyframeAnimation(keyPath: "position")
        positions.values = samples.map {
            NSValue(point: CGPoint(x: $0.midX - origin.x, y: $0.midY - origin.y))
        }
        let bounds = CAKeyframeAnimation(keyPath: "bounds")
        bounds.values = samples.map { NSValue(rect: CGRect(origin: .zero, size: $0.size)) }
        for animation in [positions, bounds] {
            animation.keyTimes = times.map { NSNumber(value: $0 / totalDuration) }
            animation.calculationMode = .linear
            animation.duration = totalDuration
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
        }
        let group = CAAnimationGroup()
        group.animations = [positions, bounds]
        group.duration = totalDuration
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.isRemovedOnCompletion = true
        return group
    }

    func applyFinalState(to imageLayer: CALayer, relativeTo origin: CGPoint) {
        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageLayer.bounds = CGRect(origin: .zero, size: finalFrame.size)
        imageLayer.position = CGPoint(x: finalFrame.midX - origin.x,
                                      y: finalFrame.midY - origin.y)
    }
}

private final class MagnetDecorationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        level = .floating
        // Match the row's availability in the active full-screen Space, while
        // letting Mission Control hide this ephemeral decoration. A Space change
        // also explicitly cancels it; physical Spaces/Stage Manager remain a gate.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        setAccessibilityHidden(true)
        // Apple now documents SharingType.none as legacy and explicitly advises
        // against using it for capture exclusion. This short-lived decoration
        // cannot promise omission from another client's system screenshot.
    }
}

private final class MagnetDecorationView: NSView {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

private final class MagnetAnimationEnd: NSObject, CAAnimationDelegate {
    let callback: @MainActor (Bool) -> Void
    let observe: @MainActor (MagnetAnimationObservation) -> Void
    init(observe: @escaping @MainActor (MagnetAnimationObservation) -> Void,
         callback: @escaping @MainActor (Bool) -> Void) { self.observe = observe; self.callback = callback }

    func animationDidStart(_ anim: CAAnimation) {
        let event = MagnetAnimationObservation(phase: .started, uptime: ProcessInfo.processInfo.systemUptime,
            finished: nil, wasMainThread: Thread.isMainThread)
        DispatchQueue.main.async { [observe] in observe(event) }
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        let event = MagnetAnimationObservation(phase: .stopped, uptime: ProcessInfo.processInfo.systemUptime,
            finished: flag, wasMainThread: Thread.isMainThread)
        // A completion already delivered on the UI thread must not queue
        // another turn behind a due watchdog. Off-main delegates still hop
        // safely; only the real finished flag can finish a flight successfully.
        if Thread.isMainThread {
            MainActor.assumeIsolated { observe(event); callback(flag) }
        } else {
            DispatchQueue.main.async { [observe, callback] in observe(event); callback(flag) }
        }
    }
}

/// Owns at most one non-activating, mouse-transparent decoration. It does NOT
/// own queue order, asset storage, click identity, upload or retry authority.
/// Completion says only that a decoration ended, never that an upload did.
@MainActor
public final class MagnetFlightPresenter {
    private struct Flight {
        let assetID: UUID
        let generation: UInt
        let panel: MagnetDecorationPanel
        let rootLayer: CALayer
        let imageLayer: CALayer
        let endDelegate: MagnetAnimationEnd
        let timeout: DispatchWorkItem
        let sampledFrameCount: Int
        let completion: (MagnetFlightCompletion) -> Void
    }

    private var flight: Flight?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var isClosed = false
    public private(set) var generation: UInt = 0
    public var currentAssetID: UUID? { flight?.assetID }
    public var activePanelCount: Int { flight == nil ? 0 : 1 }

    public var diagnostics: MagnetFlightDiagnostics {
        MagnetFlightDiagnostics(assetID: flight?.assetID, generation: generation,
            activePanelCount: activePanelCount, windowNumber: flight?.panel.windowNumber,
            ignoresMouseEvents: flight?.panel.ignoresMouseEvents ?? true,
            canBecomeKey: flight?.panel.canBecomeKey ?? false,
            canBecomeMain: flight?.panel.canBecomeMain ?? false,
            retainedImageCount: flight == nil ? 0 : 1,
            sampledFrameCount: flight?.sampledFrameCount ?? 0)
    }

    public init() {
        observe(NSApplication.didChangeScreenParametersNotification, center: .default)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: workspace)
        observe(NSWorkspace.willSleepNotification, center: workspace)
        observe(NSWorkspace.screensDidSleepNotification, center: workspace)
        observe(NSWorkspace.didWakeNotification, center: workspace)
        let motion = workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self?.cancel(reason: .reduceMotion)
                }
            }
        }
        observers.append((workspace, motion))
    }

    /// False means instant static fallback. The caller must keep its normal row
    /// visible and clickable. No delayed start/retry is scheduled after failure.
    @discardableResult
    public func start(assetID: UUID, image: CGImage, plan: MagnetMotionPlan,
                      backingScale: CGFloat, elapsedSinceAssetReady: TimeInterval = 0,
                      onAnimationObservation: @escaping (MagnetAnimationObservation) -> Void = { _ in },
                      onCompletion: @escaping (MagnetFlightCompletion) -> Void) -> Bool {
        let invocationCA = CACurrentMediaTime()
        let assetReadyCA = invocationCA - elapsedSinceAssetReady
        generation &+= 1
        let token = generation
        cancel(reason: .superseded)
        // A completion may synchronously start a newer flight. Do not overwrite
        // that reentrant owner or leave its native window orphaned.
        guard generation == token, flight == nil,
              !isClosed, backingScale.isFinite, (1...4).contains(backingScale),
              elapsedSinceAssetReady.isFinite, elapsedSinceAssetReady >= 0,
              elapsedSinceAssetReady < plan.totalDuration,
              image.width > 0, image.height > 0,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              plan.overlayFrame.width * plan.overlayFrame.height * backingScale * backingScale <= 32_000_000,
              NSScreen.screens.contains(where: { $0.frame == plan.screenFrame }) else { return false }
        let panel = MagnetDecorationPanel(frame: plan.overlayFrame)
        let view = MagnetDecorationView(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.wantsLayer = true
        let root = CALayer()
        root.frame = view.bounds
        root.contentsScale = backingScale
        root.masksToBounds = true
        view.layer = root
        panel.contentView = view

        let imageLayer = CALayer()
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.cornerRadius = 1.5
        imageLayer.masksToBounds = true
        imageLayer.contentsScale = backingScale
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .linear
        let clipMask = CAShapeLayer()
        // Use actual native window coordinates, preserving a fractional edge if
        // WindowServer rounds the transparent panel's outer rectangle.
        clipMask.frame = root.bounds
        let clip = CGRect(x: (plan.leftSide ? plan.clippingEdgeX : plan.screenFrame.minX) - panel.frame.minX,
                          y: plan.screenFrame.minY - panel.frame.minY,
                          width: plan.leftSide ? plan.screenFrame.maxX - plan.clippingEdgeX : plan.clippingEdgeX - plan.screenFrame.minX,
                          height: plan.screenFrame.height)
        clipMask.path = CGPath(rect: clip, transform: nil)
        clipMask.fillColor = NSColor.black.cgColor
        root.mask = clipMask
        root.addSublayer(imageLayer)

        let end = MagnetAnimationEnd(observe: onAnimationObservation) { [weak self] finished in
            guard finished else { return }
            self?.finish(generation: token, reason: .finished)
        }
        let timeout = DispatchWorkItem { [weak self] in
            // A safety cleanup if a render-server completion is not delivered.
            // Never infer success or resume a business operation from this timer.
            DispatchQueue.main.async { [weak self] in
                self?.finish(generation: token, reason: .timedOut)
            }
        }
        let animation = plan.makeLayerAnimation(relativeTo: panel.frame.origin)
        // Before the render server activates this already-timed animation, its
        // first sample must cover the final model pose. Keep the final model
        // and normal removal so completion cannot flash back to the source.
        animation.fillMode = .backwards
        animation.delegate = end
        let remaining = plan.totalDuration - (CACurrentMediaTime() - assetReadyCA)
        guard remaining > 0 else { panel.close(); return false }
        flight = Flight(assetID: assetID, generation: token, panel: panel,
                        rootLayer: root, imageLayer: imageLayer, endDelegate: end,
                        timeout: timeout, sampledFrameCount: plan.keyframeTimes.count,
                        completion: onCompletion)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plan.applyFinalState(to: imageLayer, relativeTo: panel.frame.origin)
        // Asset readiness is the visual clock origin, not optional image decode.
        animation.beginTime = imageLayer.convertTime(assetReadyCA, from: nil)
        imageLayer.add(animation, forKey: "riftlet.magnet.flight")
        CATransaction.commit()
        // Publish the model and animation as one update before AppKit orders
        // the new native window; orderFront may display its contents eagerly.
        panel.orderFrontRegardless()
        guard generation == token, flight?.generation == token, panel.isVisible else {
            finish(generation: token, reason: .cancelled)
            return false
        }
        // This is bounded resource cleanup, NOT the animation clock or a
        // completion criterion. WindowServer/delegate delivery can lag the
        // final rendered frame during capture/composition. Keep the original
        // 560 ms trajectory and live input islands; allow 500 ms to deliver a
        // genuine finished=true callback before reporting timedOut. A timeout
        // never becomes finished and never changes upload/retry authority.
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, plan.totalDuration - (CACurrentMediaTime() - assetReadyCA)) + 0.500, execute: timeout)
        return true
    }

    /// A mismatched old asset identity cannot cancel a replacement decoration.
    public func cancel(assetID: UUID? = nil, reason: MagnetFlightEndReason = .cancelled) {
        guard let active = flight, assetID == nil || active.assetID == assetID else { return }
        finish(generation: active.generation, reason: reason)
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        cancel(reason: .closed)
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    private func finish(generation token: UInt, reason: MagnetFlightEndReason) {
        guard let active = flight, active.generation == token else { return }
        // Clear authority BEFORE removing animations; their delayed delegates
        // must be harmless even if removal invokes animationDidStop.
        flight = nil
        active.timeout.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        active.imageLayer.removeAllAnimations()
        active.imageLayer.contents = nil
        active.imageLayer.removeFromSuperlayer()
        active.rootLayer.mask = nil
        active.rootLayer.removeAllAnimations()
        active.panel.orderOut(nil)
        active.panel.contentView = nil
        active.panel.close()
        active.completion(MagnetFlightCompletion(assetID: active.assetID,
                                                generation: active.generation, reason: reason))
        CATransaction.commit()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.cancel(reason: .geometryChanged) }
        }
        observers.append((center, observer))
    }

    deinit {
        observers.forEach { $0.0.removeObserver($0.1) }
        // Explicit close is the normal path. Also release native resources if a
        // host drops the presenter during teardown without invoking close.
        if let active = flight {
            active.timeout.cancel()
            let panel = active.panel
            let imageLayer = active.imageLayer
            DispatchQueue.main.async {
                imageLayer.removeAllAnimations()
                imageLayer.contents = nil
                imageLayer.removeFromSuperlayer()
                panel.orderOut(nil)
                panel.contentView = nil
                panel.close()
            }
        }
    }
}
