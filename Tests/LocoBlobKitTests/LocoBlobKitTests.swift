import CoreGraphics
import XCTest
@testable import LocoBlobKit

final class LocoBlobKitTests: XCTestCase {
    func testVertexCountAndRadiusScaling() {
        XCTAssertEqual(LocoBlobConstants.vertexCount(forSize: 1), 8)
        XCTAssertEqual(LocoBlobConstants.vertexCount(forSize: 2), 16)
        XCTAssertEqual(LocoBlobConstants.vertexCount(forSize: 13), 16)
        XCTAssertEqual(LocoBlobConstants.vertexCount(forSize: 14), 32)
        XCTAssertEqual(LocoBlobConstants.vertexCount(forSize: 20), 32)

        let r1 = LocoBlobConstants.radius(forSize: 1)
        let r4 = LocoBlobConstants.radius(forSize: 4)
        // Area-preserving: radius(4) == 2 * radius(1)
        XCTAssertEqual(r4, r1 * 2.0, accuracy: 1e-4)
    }

    func testWorldSimulationGravityAndFloorRest() {
        let world = LocoBlobWorld(bounds: CGRect(x: 0, y: 0, width: 140, height: 100))
        let blob = world.spawnBlob(at: CGPoint(x: 70, y: 70), size: 3, appearance: .kulche)
        let startY = blob.core.y

        for _ in 0..<120 {
            world.stepFixedFrame()
        }

        // Blob should fall and settle cleanly above the floor without collapsing or NaN
        XCTAssertLessThan(blob.core.y, startY)
        XCTAssertGreaterThanOrEqual(blob.core.y, blob.radius * 0.5)
        XCTAssertFalse(blob.core.x.isNaN || blob.core.y.isNaN)
        XCTAssertGreaterThan(blob.contactCount, 0)
    }

    func testSplitAndContourStitchingMerge() {
        let world = LocoBlobWorld(bounds: CGRect(x: 0, y: 0, width: 160, height: 120))
        let blob = world.spawnBlob(at: CGPoint(x: 80, y: 40), size: 4, appearance: .priffy)

        // Advance past 17-frame split cooldown
        for _ in 0..<25 {
            world.stepFixedFrame()
        }

        XCTAssertTrue(world.split(blobId: blob.id))
        XCTAssertEqual(world.blobs.count, 4)
        XCTAssertEqual(world.totalBlobSize, 4)
        XCTAssertTrue(world.blobs.allSatisfy { $0.appearance == .priffy })

        // Hold Join until blobs attract and contour-stitch back into fewer/larger blobs
        world.isJoining = true
        for _ in 0..<240 {
            world.stepFixedFrame()
        }

        XCTAssertLessThan(world.blobs.count, 4)
        XCTAssertEqual(world.totalBlobSize, 4)
    }

    func testObstacleCollisionAndBSplineRendering() {
        let world = LocoBlobWorld(bounds: CGRect(x: 0, y: 0, width: 120, height: 120))
        world.obstacles = [
            .rect(CGRect(x: 40, y: 20, width: 40, height: 12)),
            .circle(center: CGPoint(x: 90, y: 30), radius: 10, isBouncy: true)
        ]
        let blob = world.spawnBlob(at: CGPoint(x: 60, y: 65), size: 2, appearance: .tupley)
        for _ in 0..<90 {
            world.stepFixedFrame()
        }
        // Should rest on top of the obstacle box (y = 32) instead of falling through to y = 0
        XCTAssertGreaterThan(blob.core.y, 32.0)

        // Verify pure CoreGraphics renderer draws into an offscreen bitmap cleanly for all 6 characters
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 256,
            height: 256,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create bitmap CGContext")
            return
        }

        for appearance in LocoBlobAppearance.classicCast {
            blob.appearance = appearance
            LocoBlobRenderer.draw(blob: blob, in: ctx, scale: 3.0, showDebugMesh: true)
        }
        XCTAssertNotNil(ctx.makeImage())
    }

    func testFaceLocalVelocityKeepsVerticalMotion() {
        // Upright blob (rotation 0) moving straight up: local velocity must be straight up too.
        let blob = LocoBlob(id: 1, center: CGPoint(x: 50, y: 50), size: 3, initialVelocity: CGVector(dx: 0, dy: 2))
        XCTAssertEqual(blob.faceRotationRadians, 0, accuracy: 1e-9)
        let local = blob.faceLocalVelocity
        XCTAssertEqual(local.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(local.dy, 2, accuracy: 1e-9)

        // Rotating the whole blob must not change the velocity's length.
        let tilted = LocoBlob(id: 2, center: .zero, size: 3, initialVelocity: CGVector(dx: 1, dy: 1))
        for i in 0..<tilted.vertexCount {
            let p = tilted.cur[i]
            let q = tilted.prev[i]
            tilted.cur[i] = CGPoint(x: p.x * cos(0.6) - p.y * sin(0.6), y: p.x * sin(0.6) + p.y * cos(0.6))
            tilted.prev[i] = CGPoint(x: q.x * cos(0.6) - q.y * sin(0.6), y: q.x * sin(0.6) + q.y * cos(0.6))
        }
        let v = tilted.faceLocalVelocity
        XCTAssertEqual(hypot(v.dx, v.dy), sqrt(2.0), accuracy: 1e-6)
    }

    func testSplitAllRespectsMaxBlobCount() {
        let world = LocoBlobWorld(bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
        world.spawnBlob(at: CGPoint(x: 150, y: 60), size: 20)
        for i in 0..<15 {
            world.spawnBlob(at: CGPoint(x: 10 + CGFloat(i) * 18, y: 150), size: 1)
        }
        for _ in 0..<30 {
            world.stepFixedFrame()
        }

        world.splitAll()

        XCTAssertLessThanOrEqual(world.blobs.count, LocoBlobConstants.maxBlobCount)
        XCTAssertEqual(world.totalBlobSize, 35)
    }

    func testGrowAndShrinkIgnoreNonPositiveDelta() {
        let blob = LocoBlob(id: 1, center: .zero, size: 3)

        blob.grow(by: -5)
        XCTAssertEqual(blob.size, 3)
        blob.grow(by: 0)
        XCTAssertEqual(blob.size, 3)

        XCTAssertFalse(blob.shrink(by: -5))
        XCTAssertEqual(blob.size, 3)
        XCTAssertFalse(blob.shrink(by: 0))
        XCTAssertEqual(blob.size, 3)

        XCTAssertTrue(blob.shrink(by: 2))
        XCTAssertEqual(blob.size, 1)
        XCTAssertFalse(blob.shrink(by: 1))
        XCTAssertEqual(blob.size, 1)
    }

    func testFastBlobDoesNotTunnelThroughThinCapsule() {
        let world = LocoBlobWorld(bounds: CGRect(x: 0, y: 0, width: 140, height: 200))
        world.obstacles = [
            .capsule(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 140, y: 100), thickness: 1.0)
        ]
        let blob = world.spawnBlob(at: CGPoint(x: 70, y: 150), size: 1, initialVelocity: CGVector(dx: 0, dy: -4))

        for _ in 0..<120 {
            world.stepFixedFrame()
        }

        XCTAssertGreaterThan(blob.core.y, 100, "Blob fell through a 1-unit shelf")
    }

    func testFastBlobDoesNotTunnelThroughThinRect() {
        let world = LocoBlobWorld(bounds: CGRect(x: 0, y: 0, width: 140, height: 200))
        world.obstacles = [.rect(CGRect(x: 0, y: 99, width: 140, height: 1.5))]
        let blob = world.spawnBlob(at: CGPoint(x: 70, y: 150), size: 2, initialVelocity: CGVector(dx: 0, dy: -4.4))

        for _ in 0..<120 {
            world.stepFixedFrame()
        }

        XCTAssertGreaterThan(blob.core.y, 100.5, "Blob fell through a 1.5-unit rect")
    }
}
