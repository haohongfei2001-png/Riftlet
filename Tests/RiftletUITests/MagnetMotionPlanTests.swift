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
        XCTAssertEqual(p.totalDuration, 0.440, accuracy: 0.000001)
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
            XCTAssertTrue(p.overlayFrame.insetBy(dx: -0.001, dy: -0.001).contains(visible))
        }
    }

    func testFormationAndChargeJoinWithoutFrameOrVelocityJump() throws {
        let p = try plan()
        let boundaries = [p.parameters.formationDuration,
                          p.parameters.formationDuration + p.parameters.chargeDuration,
                          p.totalDuration]
        let h = 0.000001
        for boundary in boundaries {
            let left = p.sample(at: boundary - h).frame
            let at = p.sample(at: boundary).frame
            let right = p.sample(at: boundary + h).frame
            XCTAssertEqual(left.midX, at.midX, accuracy: 0.000001)
            XCTAssertEqual(left.midY, at.midY, accuracy: 0.000001)
            XCTAssertEqual(left.width, at.width, accuracy: 0.000001)
            XCTAssertEqual(right.midX, at.midX, accuracy: 0.000001)
            XCTAssertEqual(right.width, at.width, accuracy: 0.000001)
            XCTAssertLessThan(abs((at.midX - left.midX) / h), 0.02)
            XCTAssertLessThan(abs((right.midX - at.midX) / h), 0.02)
            XCTAssertLessThan(abs((at.width - left.width) / h), 0.02)
            XCTAssertLessThan(abs((right.width - at.width) / h), 0.02)
        }
    }

    func testChargeIsBoundedAndAlignedToAttractionInsteadOfRandomShake() throws {
        let p = try plan()
        let dx = p.finalFrame.midX - p.smallFrame.midX
        let dy = p.finalFrame.midY - p.smallFrame.midY
        let length = hypot(dx, dy)
        var signed: [CGFloat] = []
        for index in 0...100 {
            let frame = p.sample(at: p.parameters.formationDuration
                + p.parameters.chargeDuration * Double(index) / 100).frame
            let ox = frame.midX - p.smallFrame.midX
            let oy = frame.midY - p.smallFrame.midY
            XCTAssertLessThanOrEqual(hypot(ox, oy), 1.3 + 0.000001)
            XCTAssertEqual(ox * dy - oy * dx, 0, accuracy: 0.000001)
            signed.append((ox * dx + oy * dy) / length)
        }
        XCTAssertTrue(signed.contains(where: { $0 > 0.1 }))
        XCTAssertTrue(signed.contains(where: { $0 < -0.1 }))
        XCTAssertEqual(signed.first!, 0, accuracy: 0.000001)
        XCTAssertEqual(signed.last!, 0, accuracy: 0.000001)
    }

    func testAttractionAcceleratesMostOfTheFlightThenBrakesMonotonically() {
        let samples = (0...1000).map { MagnetMotionPlan.attractionProgress(Double($0) / 1000) }
        let increments = zip(samples, samples.dropFirst()).map { $1 - $0 }
        XCTAssertTrue(increments.allSatisfy { $0 >= -1e-12 })
        XCTAssertLessThan(samples[500], 0.20, "First half travels under one fifth of the distance")
        let maximum = increments.enumerated().max(by: { $0.element < $1.element })!.offset
        XCTAssertTrue((710...718).contains(maximum), "Acceleration continues through approximately 5/7")
        XCTAssertLessThan(increments[20], increments[250])
        XCTAssertLessThan(increments[250], increments[600])
        XCTAssertGreaterThan(increments[800], increments[950])
        XCTAssertEqual(samples.first!, 0)
        XCTAssertEqual(samples.last!, 1)
    }

    func testInitialAndSmallFootprintsAreBoundedAndTinySourceIsNotUpscaledInitially() throws {
        let p = try plan()
        XCTAssertLessThanOrEqual(p.initialFrame.width, 200)
        XCTAssertLessThanOrEqual(p.initialFrame.height, 130)
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
                          CGRect(x: .nan, y: 10, width: 100, height: 100),
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
        XCTAssertLessThanOrEqual(p.keyframeTimes.count, 110)
        XCTAssertTrue(p.keyframeTimes.contains(p.parameters.formationDuration))
        XCTAssertTrue(p.keyframeTimes.contains(p.parameters.formationDuration + p.parameters.chargeDuration))
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
                                                                              accelerationPower: power) }
            XCTAssertTrue(zip(progress, progress.dropFirst()).allSatisfy { $1 >= $0 - 1e-12 })
        }
    }

    func testTinyNearbySourceCannotBeClippedByAnEndpointOnlyWindowEnvelope() throws {
        let p = try XCTUnwrap(MagnetMotionPlan(sourceRect: CGRect(x: 1388, y: 699.5, width: 4, height: 3),
            targetImageFrame: destination, clippingEdgeX: 1432, screenFrame: screen))
        var extendedBeyondEndpointUnion = false
        let endpoints = p.initialFrame.union(p.finalFrame)
        for index in 0...1000 {
            let time = p.totalDuration * Double(index) / 1000
            let visible = p.visibleFrame(at: time)
            if visible.minX < endpoints.minX { extendedBeyondEndpointUnion = true }
            XCTAssertTrue(p.overlayFrame.insetBy(dx: -0.001, dy: -0.001).contains(visible))
        }
        XCTAssertTrue(extendedBeyondEndpointUnion, "Fixture exercises the real independent-size/position envelope risk")
    }
}
