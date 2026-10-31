import Foundation
import CoreGraphics

/// Tunable engineering candidate, not a declaration of the final product default
/// or of physical-Mac visual acceptance. Values are seconds and AppKit points.
public struct MagnetMotionParameters: Equatable, Sendable {
    public var formationDuration: TimeInterval = 0.123
    public var chargeDuration: TimeInterval = 0.101
    public var attractionDuration: TimeInterval = 0.260
    public var initialMaximumSize = CGSize(width: 240, height: 150)
    public var smallMaximumSize = CGSize(width: 58, height: 46)
    public var chargeAmplitude: CGFloat = 1.2
    public var minimumTravel: CGFloat = 24
    public var settleDuration: TimeInterval = 0.076
    /// Design candidate t^2.25 attraction; reverse only after complete occlusion.
    public var accelerationPower: Double = 2.25
    /// Explicit keyframe interpolation; no per-frame Swift timer or display link.
    public var samplesPerSecond: Double = 240

    public init() {}

    public var totalDuration: TimeInterval {
        formationDuration + chargeDuration + attractionDuration + settleDuration
    }

    public var isValid: Bool {
        let times = [formationDuration, chargeDuration, attractionDuration, settleDuration]
        return times.allSatisfy { $0.isFinite && $0 > 0 }
            && totalDuration <= 1.2
            && Self.validSize(initialMaximumSize, maximum: CGSize(width: 240, height: 150))
            && Self.validSize(smallMaximumSize, maximum: initialMaximumSize)
            && chargeAmplitude.isFinite && (0...1.5).contains(chargeAmplitude)
            && minimumTravel.isFinite && (0...256).contains(minimumTravel)
            && accelerationPower.isFinite && (1...8).contains(accelerationPower)
            && samplesPerSecond.isFinite && (60...240).contains(samplesPerSecond)
    }

    private static func validSize(_ value: CGSize, maximum: CGSize) -> Bool {
        value.width.isFinite && value.height.isFinite
            && value.width > 0 && value.height > 0
            && value.width <= maximum.width && value.height <= maximum.height
    }
}

public enum MagnetMotionStage: String, Sendable {
    case forming, charging, attracting, settling, settled
}

public struct MagnetMotionSample: Equatable, Sendable {
    public let frame: CGRect
    public let stage: MagnetMotionStage
    /// Monotonic along the original source-to-target vector during attraction.
    public let travelProgress: Double
}

/// A single image travels to the exact final RiftLayout image rectangle. Its
/// right side crosses one fixed clipping plane. At complete occlusion it reverses
/// into the final slot. The hidden turnaround preserves visible-area continuity;
/// it deliberately does not claim C1 velocity continuity.
///
/// All rectangles use the SAME display's AppKit global point coordinates.
/// This type validates geometry, not screenshot-metadata provenance. The caller
/// must independently establish a credible source rectangle before construction.
public struct MagnetMotionPlan: Equatable, Sendable {
    public let leftSide: Bool
    public let sourceRect: CGRect
    public let screenFrame: CGRect
    public let clippingEdgeX: CGFloat
    public let initialFrame: CGRect
    public let smallFrame: CGRect
    public let finalFrame: CGRect
    /// Entire image behind the fixed clipping plane, before final reveal.
    public let occludedFrame: CGRect
    /// Bounded transparent window, clipped to the physical display and edge.
    public let overlayFrame: CGRect
    public let parameters: MagnetMotionParameters
    private let direction: CGVector

    public var totalDuration: TimeInterval { parameters.totalDuration }

    public init?(sourceRect: CGRect, targetImageFrame: CGRect,
                 clippingEdgeX: CGFloat, screenFrame: CGRect,
                 parameters: MagnetMotionParameters = .init(), leftSide: Bool = false) {
        if leftSide {
            let axis = screenFrame.minX + screenFrame.maxX
            func reflect(_ r: CGRect) -> CGRect { CGRect(x: axis - r.maxX, y: r.minY, width: r.width, height: r.height) }
            guard let right = MagnetMotionPlan(sourceRect: reflect(sourceRect), targetImageFrame: reflect(targetImageFrame),
                clippingEdgeX: axis - clippingEdgeX, screenFrame: screenFrame, parameters: parameters) else { return nil }
            self.leftSide = true; self.sourceRect = sourceRect; self.screenFrame = screenFrame
            self.clippingEdgeX = clippingEdgeX; self.initialFrame = reflect(right.initialFrame)
            self.smallFrame = reflect(right.smallFrame); self.finalFrame = targetImageFrame
            self.occludedFrame = reflect(right.occludedFrame); self.overlayFrame = reflect(right.overlayFrame)
            self.parameters = parameters; self.direction = CGVector(dx: -right.direction.dx, dy: right.direction.dy)
            return
        }
        self.leftSide = false
        guard parameters.isValid,
              Self.validRect(sourceRect), Self.validRect(targetImageFrame),
              Self.validRect(screenFrame),
              screenFrame.width <= 32_768, screenFrame.height <= 32_768,
              targetImageFrame.width <= 256, targetImageFrame.height <= 256,
              clippingEdgeX.isFinite,
              clippingEdgeX > screenFrame.minX, clippingEdgeX <= screenFrame.maxX,
              targetImageFrame.minX < clippingEdgeX,
              targetImageFrame.maxX >= clippingEdgeX,
              screenFrame.contains(sourceRect),
              targetImageFrame.minX >= screenFrame.minX,
              targetImageFrame.minY >= screenFrame.minY,
              targetImageFrame.maxY <= screenFrame.maxY else { return nil }

        let center = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        let initialSize = Self.fit(aspect: targetImageFrame.size,
            within: CGSize(width: min(sourceRect.width, parameters.initialMaximumSize.width),
                           height: min(sourceRect.height, parameters.initialMaximumSize.height)))
        let smallSize = Self.fit(aspect: targetImageFrame.size,
            within: CGSize(width: min(initialSize.width, parameters.smallMaximumSize.width),
                           height: min(initialSize.height, parameters.smallMaximumSize.height)))
        let initial = Self.frame(center: center, size: initialSize)
        let small = Self.frame(center: center, size: smallSize)
        let occluded = CGRect(x: clippingEdgeX, y: targetImageFrame.minY,
                              width: targetImageFrame.width, height: targetImageFrame.height)
        let dx = occluded.midX - center.x
        let dy = occluded.midY - center.y
        let distance = hypot(dx, dy)
        guard distance.isFinite, distance >= max(0.01, parameters.minimumTravel),
              initial.maxX <= clippingEdgeX else { return nil }

        let direction = CGVector(dx: dx / distance, dy: dy / distance)
        // Charge has a deterministic signed displacement along the attraction
        // vector. Reject geometry where even this tiny envelope could be clipped
        // at its source; do not move or invent the source to make it fit.
        let chargeBounds = small.insetBy(dx: -abs(direction.dx) * parameters.chargeAmplitude,
                                        dy: -abs(direction.dy) * parameters.chargeAmplitude)
        guard screenFrame.contains(chargeBounds), chargeBounds.maxX <= clippingEdgeX else { return nil }

        let clip = CGRect(x: screenFrame.minX, y: screenFrame.minY,
                          width: clippingEdgeX - screenFrame.minX, height: screenFrame.height)
        // Position and size have independent smooth curves. For a tiny source
        // near the destination, the interpolated left/top edge can extend beyond
        // the union of the endpoint rectangles. Bound the complete center segment
        // by the largest travel footprint; otherwise the window itself could
        // accidentally clip the image before it reaches the intended rift plane.
        let travelWidth = max(small.width, targetImageFrame.width)
        let travelHeight = max(small.height, targetImageFrame.height)
        let travelBounds = CGRect(x: min(center.x, occluded.midX) - travelWidth / 2,
                                  y: min(center.y, occluded.midY) - travelHeight / 2,
                                  width: abs(dx) + travelWidth, height: abs(dy) + travelHeight)
        guard travelBounds.minX >= screenFrame.minX,
              travelBounds.minY >= screenFrame.minY,
              travelBounds.maxY <= screenFrame.maxY else { return nil }
        let overlay = initial.union(chargeBounds).union(travelBounds).union(targetImageFrame).intersection(clip)
        guard Self.validRect(overlay) else { return nil }

        self.sourceRect = sourceRect
        self.screenFrame = screenFrame
        self.clippingEdgeX = clippingEdgeX
        self.initialFrame = initial
        self.smallFrame = small
        self.finalFrame = targetImageFrame
        self.occludedFrame = occluded
        self.overlayFrame = overlay
        self.parameters = parameters
        self.direction = direction
    }

    /// Sharp enough for the largest actual footprint, capped independently of
    /// original full-screen pixel dimensions. Decode asynchronously off the UI.
    public func requiredPixelSize(backingScale: CGFloat) -> Int {
        guard backingScale.isFinite, backingScale > 0, backingScale <= 4 else { return 0 }
        let longest = [initialFrame.width, initialFrame.height,
                       smallFrame.width, smallFrame.height,
                       finalFrame.width, finalFrame.height].max() ?? 0
        return min(768, max(1, Int(ceil(longest * backingScale))))
    }

    public func sample(at elapsed: TimeInterval) -> MagnetMotionSample {
        let t = elapsed.isFinite ? max(0, elapsed) : 0
        if t >= totalDuration {
            return MagnetMotionSample(frame: finalFrame, stage: .settled, travelProgress: 1)
        }
        let p = parameters
        if t < p.formationDuration {
            let u = t / p.formationDuration
            let progress = Self.outCubic(u)
            return MagnetMotionSample(
                frame: Self.frame(center: CGPoint(x: initialFrame.midX, y: initialFrame.midY),
                    size: Self.interpolate(initialFrame.size, smallFrame.size, progress)),
                stage: .forming, travelProgress: 0)
        }
        if t < p.formationDuration + p.chargeDuration {
            let u = (t - p.formationDuration) / p.chargeDuration
            // 1.5 deterministic directional cycles, smoothly zero at both ends.
            // No random jitter, rotation, glow, bounce or perpetual oscillation.
            let envelope = sin(.pi * u) * (1 - u)
            let displacement = p.chargeAmplitude * CGFloat(sin(3 * .pi * u) * envelope)
            return MagnetMotionSample(
                frame: smallFrame.offsetBy(dx: direction.dx * displacement, dy: direction.dy * displacement),
                stage: .charging, travelProgress: 0)
        }
        let attractionStart = p.formationDuration + p.chargeDuration
        let settleStart = attractionStart + p.attractionDuration
        if t < settleStart {
            let u = (t - attractionStart) / p.attractionDuration
            let progress = Self.attractionProgress(u, accelerationPower: p.accelerationPower)
            let center = CGPoint(x: smallFrame.midX + (occludedFrame.midX - smallFrame.midX) * CGFloat(progress),
                                 y: smallFrame.midY + (occludedFrame.midY - smallFrame.midY) * CGFloat(progress))
            return MagnetMotionSample(frame: Self.frame(center: center,
                size: Self.interpolate(smallFrame.size, finalFrame.size, progress)),
                stage: .attracting, travelProgress: progress)
        }
        let reveal = Self.outCubic((t - settleStart) / p.settleDuration)
        return MagnetMotionSample(frame: occludedFrame.offsetBy(
            dx: (finalFrame.minX - occludedFrame.minX) * CGFloat(reveal), dy: 0),
            stage: .settling, travelProgress: 1)
    }

    /// Exact visible part of the same sprite at a sample, including the final
    /// 25%-hidden layout when that fraction is selected by RiftConfiguration.
    public func visibleFrame(at elapsed: TimeInterval) -> CGRect {
        let clip = CGRect(x: screenFrame.minX, y: screenFrame.minY,
                          width: clippingEdgeX - screenFrame.minX, height: screenFrame.height)
        let frame = sample(at: elapsed).frame
        let actualClip = leftSide ? CGRect(x: clippingEdgeX, y: screenFrame.minY, width: screenFrame.maxX - clippingEdgeX, height: screenFrame.height) : clip
        let visible = frame.intersection(actualClip)
        return visible.isEmpty ? CGRect(x: clippingEdgeX, y: frame.minY, width: 0, height: frame.height) : visible
    }

    /// Includes exact phase boundaries as well as a bounded uniform sampling.
    /// Core Animation interpolates these explicit values on the render server.
    public var keyframeTimes: [TimeInterval] {
        let count = max(2, Int(ceil(totalDuration * parameters.samplesPerSecond)))
        let times = (0...count).map { Double($0) * totalDuration / Double(count) }
            + [parameters.formationDuration, parameters.formationDuration + parameters.chargeDuration,
               parameters.formationDuration + parameters.chargeDuration + parameters.attractionDuration]
        return Array(Set(times)).sorted()
    }

    /// Design-candidate attraction, with no hidden braking segment or overshoot.
    /// Turnaround occurs while completely clipped, not in public visible space.
    public static func attractionProgress(_ value: Double, accelerationPower: Double = 2.25) -> Double {
        guard value.isFinite else { return value == .infinity ? 1 : 0 }
        guard accelerationPower.isFinite else { return 0 }
        return pow(min(1, max(0, value)), min(8, max(1, accelerationPower)))
    }

    private static func outCubic(_ u: Double) -> Double {
        1 - pow(1 - min(1, max(0, u)), 3)
    }

    private static func interpolate(_ a: CGSize, _ b: CGSize, _ progress: Double) -> CGSize {
        CGSize(width: a.width + (b.width - a.width) * CGFloat(progress),
               height: a.height + (b.height - a.height) * CGFloat(progress))
    }

    private static func fit(aspect: CGSize, within box: CGSize) -> CGSize {
        let ratio = min(box.width / aspect.width, box.height / aspect.height)
        return CGSize(width: aspect.width * ratio, height: aspect.height * ratio)
    }

    private static func frame(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
               width: size.width, height: size.height)
    }

    private static func validRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
    }
}
