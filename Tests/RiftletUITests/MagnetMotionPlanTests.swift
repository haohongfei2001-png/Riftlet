import AppKit
import QuartzCore
import XCTest
@testable import RiftletUI

final class MagnetMotionPlanTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let source = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let destination = CGRect(x: 1378, y: 673, width: 72, height: 56)

    private func plan(_ parameters: MagnetMotionParameters = .init()) throws -> MagnetMotionPlan {
        try XCTUnwrap(MagnetMotionPlan(sourceRect: source, targetImageFrame: destination,
                                      clippingEdgeX: 1432, screenFrame: screen, parameters: parameters))
    }

    func testOneContinuousImageEndsAtExactLayoutWithFixedOcclusion() throws {
        let p = try plan()
        XCTAssertEqual(p.totalDuration, 0.560, accuracy: 0.000001)
        XCTAssertEqual(p.sample(at: p.totalDuration).frame, destination)
        XCTAssertEqual(p.visibleFrame(at: p.totalDuration), CGRect(x: 1378, y: 673, width: 54, height: 56))
        XCTAssertEqual(p.sample(at: 100).frame, destination)
        let ratio = destination.width / destination.height
        for index in 0...1000 {
            let sample = p.sample(at: p.totalDuration * Double(index) / 1000)
            XCTAssertEqual(sample.frame.width / sample.frame.height, ratio, accuracy: 0.000001)
            XCTAssertTrue(sample.frame.minX.isFinite && sample.frame.minY.isFinite)
            let visible = p.visibleFrame(at: p.totalDuration * Double(index) / 1000)
            XCTAssertLessThanOrEqual(visible.maxX, 1432.000001)
            if !visible.isEmpty { XCTAssertTrue(p.overlayFrame.insetBy(dx: -0.001, dy: -0.001).contains(visible)) }
        }
    }

    func testFourPhaseBoundariesHaveContinuousFramesAndHiddenTurnaround() throws {
        let p = try plan()
        let settleStart = p.parameters.formationDuration + p.parameters.chargeDuration + p.parameters.attractionDuration
        let boundaries = [p.parameters.formationDuration,
                          p.parameters.formationDuration + p.parameters.chargeDuration,
                          settleStart, p.totalDuration]
        // Positional continuity is required; the hidden reversal does not claim C1 velocity continuity.
        let h = 0.00000001
        for boundary in boundaries {
            let left = p.sample(at: boundary - h).frame
            let at = p.sample(at: boundary).frame
            let right = p.sample(at: boundary + h).frame
            XCTAssertEqual(left.midX, at.midX, accuracy: 0.0002)
            XCTAssertEqual(left.midY, at.midY, accuracy: 0.0002)
            XCTAssertEqual(left.width, at.width, accuracy: 0.0002)
            XCTAssertEqual(right.midX, at.midX, accuracy: 0.0002)
            XCTAssertEqual(right.width, at.width, accuracy: 0.0002)
        }
        XCTAssertEqual(p.sample(at: settleStart).stage, .settling)
        XCTAssertEqual(p.sample(at: settleStart).frame.minX, p.clippingEdgeX)
        XCTAssertEqual(p.visibleFrame(at: settleStart).width, 0)
        XCTAssertLessThan(p.visibleFrame(at: settleStart - h).width, 0.0002)
        XCTAssertLessThan(p.visibleFrame(at: settleStart + h).width, 0.0002)
        XCTAssertEqual(p.sample(at: p.totalDuration).stage, .settled)
    }

    func testPublishedDesignReferenceGoldenSamples() throws {
        // Reference fixture from the design film: source center(840,550), 8:5;
        // AppKit row center=670 and edge=1426. Screen points, no Retina multiplier.
        let p = try XCTUnwrap(MagnetMotionPlan(sourceRect: CGRect(x: 440, y: 300, width: 800, height: 500),
            targetImageFrame: CGRect(x: 1372, y: 647.5, width: 72, height: 45),
            clippingEdgeX: 1426, screenFrame: screen))
        XCTAssertEqual(p.initialFrame, CGRect(x: 720, y: 475, width: 240, height: 150))
        XCTAssertEqual(p.sample(at: 0.0615).frame.width, 80.75, accuracy: 0.000001)
        XCTAssertEqual(p.sample(at: 0.0615).frame.midX, 840, accuracy: 0.000001)
        XCTAssertEqual(p.sample(at: 0.123).frame.width, 58, accuracy: 0.000001)
        let halfway = p.sample(at: 0.354)
        XCTAssertEqual(halfway.frame.midX, 970.7593925719526, accuracy: 0.000001)
        XCTAssertEqual(halfway.frame.midY, 575.2268924576115, accuracy: 0.000001)
        XCTAssertEqual(halfway.frame.width, 60.943137453388, accuracy: 0.000001)
        XCTAssertEqual(p.visibleFrame(at: 0.484).width, 0, accuracy: 0.000001)
        XCTAssertEqual(p.sample(at: 0.522).frame.minX, 1378.75, accuracy: 0.000001)
        XCTAssertEqual(p.sample(at: 0.560).frame.minX, 1372, accuracy: 0.000001)
    }

    func testChargeIsBoundedAndAlignedToAttractionInsteadOfRandomShake() throws {
        let p = try plan()
        let dx = p.occludedFrame.midX - p.smallFrame.midX
        let dy = p.occludedFrame.midY - p.smallFrame.midY
        let length = hypot(dx, dy)
        var signed: [CGFloat] = []
        for index in 0...100 {
            let frame = p.sample(at: p.parameters.formationDuration
                + p.parameters.chargeDuration * Double(index) / 100).frame
            let ox = frame.midX - p.smallFrame.midX
            let oy = frame.midY - p.smallFrame.midY
            XCTAssertLessThanOrEqual(hypot(ox, oy), 1.2 + 0.000001)
            XCTAssertEqual(ox * dy - oy * dx, 0, accuracy: 0.000001)
            signed.append((ox * dx + oy * dy) / length)
        }
        XCTAssertTrue(signed.contains(where: { $0 > 0.1 }))
        XCTAssertTrue(signed.contains(where: { $0 < -0.1 }))
        XCTAssertEqual(signed.first!, 0, accuracy: 0.000001)
        XCTAssertEqual(signed.last!, 0, accuracy: 0.000001)
    }

    func testAttractionAcceleratesMonotonicallyUntilFullyOccluded() {
        let samples = (0...1000).map { MagnetMotionPlan.attractionProgress(Double($0) / 1000) }
        let increments = zip(samples, samples.dropFirst()).map { $1 - $0 }
        XCTAssertTrue(increments.allSatisfy { $0 >= -1e-12 })
        XCTAssertEqual(samples[500], 0.21022410381342863, accuracy: 1e-12)
        XCTAssertTrue(zip(increments, increments.dropFirst()).allSatisfy { $1 >= $0 - 1e-12 })
        XCTAssertEqual(samples.first!, 0)
        XCTAssertEqual(samples.last!, 1)
    }

    func testInitialAndSmallFootprintsAreBoundedAndTinySourceIsNotUpscaledInitially() throws {
        let p = try plan()
        XCTAssertLessThanOrEqual(p.initialFrame.width, 240)
        XCTAssertLessThanOrEqual(p.initialFrame.height, 150)
        XCTAssertLessThanOrEqual(p.smallFrame.width, 58)
        XCTAssertLessThanOrEqual(p.smallFrame.height, 46)
        let tiny = try XCTUnwrap(MagnetMotionPlan(sourceRect: CGRect(x: 300, y: 300, width: 4, height: 3),
            targetImageFrame: destination, clippingEdgeX: 1432, screenFrame: screen))
        XCTAssertLessThanOrEqual(tiny.initialFrame.width, 4)
        XCTAssertLessThanOrEqual(tiny.initialFrame.height, 3)
        XCTAssertEqual(tiny.initialFrame.size, tiny.smallFrame.size)
        XCTAssertEqual(p.requiredPixelSize(backingScale: 2), Int(ceil(p.initialFrame.width * 2)))
        XCTAssertEqual(p.requiredPixelSize(backingScale: .nan), 0)
    }

    func testNegativeAndVerticallyOffsetDisplaysUseGlobalPointsWithoutScalingTwice() throws {
        let moved = try XCTUnwrap(MagnetMotionPlan(sourceRect: source.offsetBy(dx: -1440, dy: 900),
            targetImageFrame: destination.offsetBy(dx: -1440, dy: 900),
            clippingEdgeX: -8, screenFrame: screen.offsetBy(dx: -1440, dy: 900)))
        let p = try plan()
        for time in p.keyframeTimes {
            let expected = p.sample(at: time).frame.offsetBy(dx: -1440, dy: 900)
            let actual = moved.sample(at: time).frame
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.000001)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.000001)
            XCTAssertEqual(actual.size, expected.size)
        }
    }

    func testUnsafeSourceAndDestinationGeometryFallsBackInsteadOfClamping() {
        let badSources = [CGRect.zero,
                          CGRect(x: 300, y: 300, width: -100, height: 100),
                          CGRect(x: 300, y: 300, width: 100, height: -100),
                          CGRect(x: CGFloat.nan, y: 10, width: 100, height: 100),
                          CGRect(x: -40, y: 10, width: 100, height: 100),
                          CGRect(x: 1400, y: 10, width: 100, height: 100),
                          CGRect(x: 1433, y: 500, width: 4, height: 4)]
        for source in badSources {
            XCTAssertNil(MagnetMotionPlan(sourceRect: source, targetImageFrame: destination,
                                          clippingEdgeX: 1432, screenFrame: screen))
        }
        XCTAssertNil(MagnetMotionPlan(sourceRect: source, targetImageFrame: destination.offsetBy(dx: -500, dy: 0),
                                      clippingEdgeX: 1432, screenFrame: screen))
        XCTAssertNil(MagnetMotionPlan(sourceRect: source, targetImageFrame: destination,
                                      clippingEdgeX: .infinity, screenFrame: screen))
        XCTAssertNil(MagnetMotionPlan(sourceRect: source,
            targetImageFrame: CGRect(x: 1450, y: 673, width: -72, height: 56),
            clippingEdgeX: 1432, screenFrame: screen))
    }

    func testMalformedParametersNeverCreateAnUnboundedOrEmptyAnimation() {
        var values: [MagnetMotionParameters] = []
        var p = MagnetMotionParameters(); p.formationDuration = .nan; values.append(p)
        p = .init(); p.chargeDuration = -1; values.append(p)
        p = .init(); p.attractionDuration = 0; values.append(p)
        p = .init(); p.settleDuration = 0; values.append(p)
        p = .init(); p.accelerationPower = .nan; values.append(p)
        p = .init(); p.chargeAmplitude = 10; values.append(p)
        p = .init(); p.initialMaximumSize.width = .infinity; values.append(p)
        p = .init(); p.samplesPerSecond = 1_000_000; values.append(p)
        p = .init(); p.accelerationPower = 100; values.append(p)
        for p in values {
            XCTAssertFalse(p.isValid)
            XCTAssertNil(MagnetMotionPlan(sourceRect: source, targetImageFrame: destination,
                                          clippingEdgeX: 1432, screenFrame: screen, parameters: p))
        }
    }

    func testCoreAnimationValuesShareTheSinglePlanAndContainEveryBoundary() throws {
        let p = try plan()
        let origin = p.overlayFrame.origin
        let animation = p.makeLayerAnimation(relativeTo: origin)
        XCTAssertEqual(animation.duration, p.totalDuration)
        XCTAssertEqual(animation.animations?.count, 2)
        XCTAssertLessThanOrEqual(p.keyframeTimes.count, 140)
        XCTAssertTrue(p.keyframeTimes.contains(p.parameters.formationDuration))
        XCTAssertTrue(p.keyframeTimes.contains(p.parameters.formationDuration + p.parameters.chargeDuration))
        XCTAssertTrue(p.keyframeTimes.contains(p.parameters.formationDuration + p.parameters.chargeDuration + p.parameters.attractionDuration))
        let positions = try XCTUnwrap(animation.animations?.first as? CAKeyframeAnimation)
        XCTAssertEqual(positions.calculationMode, .linear)
        let points = try XCTUnwrap(positions.values as? [NSValue])
        XCTAssertEqual(points.first?.pointValue,
            CGPoint(x: p.initialFrame.midX - origin.x, y: p.initialFrame.midY - origin.y))
        XCTAssertEqual(points.last?.pointValue,
            CGPoint(x: destination.midX - origin.x, y: destination.midY - origin.y))
    }

    func testAccelerationCurveCanBeTunedWithoutChangingTheArrivalEndpoint() throws {
        var early = MagnetMotionParameters(); early.accelerationPower = 2
        var late = MagnetMotionParameters(); late.accelerationPower = 8
        let earlier = try plan(early), later = try plan(late)
        let midpoint = early.formationDuration + early.chargeDuration + early.attractionDuration / 2
        XCTAssertGreaterThan(earlier.sample(at: midpoint).travelProgress, later.sample(at: midpoint).travelProgress)
        XCTAssertEqual(earlier.sample(at: earlier.totalDuration).frame, destination)
        XCTAssertEqual(later.sample(at: later.totalDuration).frame, destination)
        for power in 2...8 {
            let progress = (0...1000).map { MagnetMotionPlan.attractionProgress(Double($0) / 1000,
                                                                              accelerationPower: Double(power)) }
            XCTAssertTrue(zip(progress, progress.dropFirst()).allSatisfy { $1 >= $0 - 1e-12 })
        }
    }

    func testTinyNearbySourceCannotBeClippedByAnEndpointOnlyWindowEnvelope() throws {
        let p = try XCTUnwrap(MagnetMotionPlan(sourceRect: CGRect(x: 1388, y: 699.5, width: 4, height: 3),
            targetImageFrame: destination, clippingEdgeX: 1432, screenFrame: screen))
        for index in 0...1000 {
            let time = p.totalDuration * Double(index) / 1000
            let visible = p.visibleFrame(at: time)
            if !visible.isEmpty { XCTAssertTrue(p.overlayFrame.insetBy(dx: -0.001, dy: -0.001).contains(visible)) }
        }
        XCTAssertLessThan(p.overlayFrame.width, screen.width, "Decoration stays bounded to the flight envelope")
    }
}
