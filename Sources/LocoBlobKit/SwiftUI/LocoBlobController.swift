import CoreGraphics
import Foundation
import Observation
import SwiftUI
#if canImport(CoreMotion) && !os(macOS)
import CoreMotion
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Configuration for spawning an initial blob inside `LocoBlobView`.
public struct LocoBlobSeed: Sendable {
    public var appearance: LocoBlobAppearance
    public var size: Int
    /// Normalized position `(0...1, 0...1)` inside the view (`nil` = random upper-middle spawn).
    public var normalizedPosition: CGPoint?

    public init(
        appearance: LocoBlobAppearance = .kulche,
        size: Int = 3,
        normalizedPosition: CGPoint? = nil
    ) {
        self.appearance = appearance
        self.size = size
        self.normalizedPosition = normalizedPosition
    }
}

/// Imperative controller that drives a `LocoBlobWorld` inside SwiftUI.
///
/// Its settings and blob counts are observable; blob motion itself is redrawn every frame by `LocoBlobView`.
///
/// Hold a `@State private var controller = LocoBlobController()` in any SwiftUI view to spawn,
/// jump, split, join, tilt, change expressions, or react to blob events!
@MainActor
@Observable
public final class LocoBlobController {
    @ObservationIgnored public let world: LocoBlobWorld
    public var pointsPerWorldUnit: CGFloat

    public var showDebugMesh: Bool = false
    public var enableGyroscope: Bool = false {
        didSet { updateGyroscopeState() }
    }
    public private(set) var blobCount: Int = 0
    public private(set) var totalBlobSize: Int = 0

    @ObservationIgnored internal var visualStates: [Int: LocoBlobVisualState] = [:]
    @ObservationIgnored private var lastFrameDate: Date?
    @ObservationIgnored private var accumulator: TimeInterval = 0
    @ObservationIgnored private var hasSeeded = false
    @ObservationIgnored private var pendingSeeds: [LocoBlobSeed]

    #if canImport(CoreMotion) && !os(macOS)
    @ObservationIgnored private nonisolated(unsafe) let motionManager = CMMotionManager()
    #endif

    public init(
        blobs: [LocoBlobSeed] = [LocoBlobSeed(appearance: .kulche, size: 3)],
        pointsPerWorldUnit: CGFloat = LocoBlobConstants.defaultPointsPerWorldUnit,
        enableGyroscope: Bool = false
    ) {
        self.world = LocoBlobWorld()
        self.pointsPerWorldUnit = pointsPerWorldUnit
        self.pendingSeeds = blobs
        self.enableGyroscope = enableGyroscope

        world.onBlobStructureChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncPublishedCounts()
            }
        }
        updateGyroscopeState()
    }

    deinit {
        #if canImport(CoreMotion) && !os(macOS)
        motionManager.stopDeviceMotionUpdates()
        #endif
    }

    // MARK: - Public Controls

    @discardableResult
    public func spawn(
        _ appearance: LocoBlobAppearance = .kulche,
        size: Int = 2,
        atViewPoint viewPoint: CGPoint? = nil,
        inViewSize viewSize: CGSize? = nil
    ) -> LocoBlob {
        let worldPt: CGPoint?
        if let vp = viewPoint, let vs = viewSize {
            worldPt = viewToWorld(vp, in: vs)
        } else {
            worldPt = nil
        }
        let blob = world.spawnBlob(at: worldPt, size: size, appearance: appearance)
        visualStates[blob.id] = LocoBlobVisualState()
        syncPublishedCounts()
        return blob
    }

    public func jump(charge: CGFloat = 0.85, requireContact: Bool = false) {
        world.triggerJump(charge: charge, requireContact: requireContact)
    }

    @discardableResult
    public func splitAll() -> Bool {
        let didSplit = world.splitAll()
        if didSplit { syncPublishedCounts() }
        return didSplit
    }

    public func setJoining(_ joining: Bool) {
        world.isJoining = joining
    }

    public func setTilt(radians: CGFloat?) {
        world.targetTiltRadians = radians
    }

    public func setExpression(_ expression: LocoBlobExpression?) {
        for blob in world.blobs {
            blob.expressionOverride = expression
        }
    }

    public func setStiffness(_ multiplier: CGFloat) {
        world.stiffnessMultiplier = multiplier
    }

    public func setGravityMultiplier(_ multiplier: CGFloat) {
        world.gravityMultiplier = multiplier
    }

    public func clearAll() {
        world.clearBlobs()
        visualStates.removeAll()
        syncPublishedCounts()
    }

    /// Replaces obstacle rects using standard SwiftUI view-space `CGRect`s (top-left origin, Y-down).
    public func setViewSpaceObstacles(_ rects: [CGRect], in viewSize: CGSize, isBouncy: Bool = false) {
        let s = pointsPerWorldUnit
        world.obstacles = rects.enumerated().map { idx, r in
            let worldRect = CGRect(
                x: r.minX / s,
                y: (viewSize.height - r.maxY) / s,
                width: r.width / s,
                height: r.height / s
            )
            return .rect(id: "ui-\(idx)", worldRect, isBouncy: isBouncy)
        }
    }

    // MARK: - Coordinate Conversion (SwiftUI Y-down <-> Physics Y-up)

    public func viewToWorld(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: point.x / pointsPerWorldUnit,
            y: (viewSize.height - point.y) / pointsPerWorldUnit
        )
    }

    // MARK: - Internal Frame Stepping

    internal func updateContainerSize(_ viewSize: CGSize) {
        guard viewSize.width > 10, viewSize.height > 10 else { return }
        let s = pointsPerWorldUnit
        let newBounds = CGRect(x: 0, y: 0, width: viewSize.width / s, height: viewSize.height / s)
        world.bounds = newBounds

        if !hasSeeded {
            hasSeeded = true
            for seed in pendingSeeds {
                let pt: CGPoint?
                if let norm = seed.normalizedPosition {
                    pt = CGPoint(
                        x: newBounds.width * norm.x,
                        y: newBounds.height * (1.0 - norm.y)
                    )
                } else {
                    pt = nil
                }
                let b = world.spawnBlob(at: pt, size: seed.size, appearance: seed.appearance)
                visualStates[b.id] = LocoBlobVisualState()
            }
            syncPublishedCounts()
        }
    }

    internal func step(date: Date, viewSize: CGSize) {
        updateContainerSize(viewSize)
        pollGyroscopeIfNeeded(viewSize: viewSize)

        let dt: TimeInterval
        if let prev = lastFrameDate {
            dt = min(0.05, max(0, date.timeIntervalSince(prev)))
        } else {
            dt = LocoBlobConstants.fixedDeltaTime
        }
        lastFrameDate = date

        accumulator += dt
        let stepDt = LocoBlobConstants.fixedDeltaTime
        var substeps = 0
        while accumulator >= stepDt && substeps < 3 {
            world.stepFixedFrame()
            stepVisualStates()
            accumulator -= stepDt
            substeps += 1
        }
    }

    private func stepVisualStates() {
        var activeIds = Set<Int>()
        for blob in world.blobs {
            activeIds.insert(blob.id)
            var vs = visualStates[blob.id] ?? LocoBlobVisualState()
            let rot = blob.faceRotationRadians
            let vel = blob.averageVelocity()
            let localVx = vel.dx * cos(-rot) - vel.dy * sin(-rot)
            vs.step(localVelX: localVx)
            visualStates[blob.id] = vs
        }
        if visualStates.count > activeIds.count {
            visualStates = visualStates.filter { activeIds.contains($0.key) }
        }
    }

    private func syncPublishedCounts() {
        let nextCount = world.blobs.count
        let nextTotal = world.totalBlobSize
        if blobCount != nextCount { blobCount = nextCount }
        if totalBlobSize != nextTotal { totalBlobSize = nextTotal }
    }

    private func updateGyroscopeState() {
        #if canImport(CoreMotion) && !os(macOS)
        if enableGyroscope {
            if motionManager.isDeviceMotionAvailable {
                motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
                motionManager.startDeviceMotionUpdates()
            }
        } else {
            motionManager.stopDeviceMotionUpdates()
            world.targetTiltRadians = nil
        }
        #endif
    }

    private func pollGyroscopeIfNeeded(viewSize: CGSize) {
        #if canImport(CoreMotion) && !os(macOS)
        guard enableGyroscope, let motion = motionManager.deviceMotion else { return }
        let g = motion.gravity
        #if canImport(UIKit)
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first ?? .unknown
        let rawTilt: CGFloat
        switch orientation {
        case .portrait:           rawTilt = CGFloat(g.x)
        case .portraitUpsideDown: rawTilt = CGFloat(-g.x)
        case .landscapeRight:     rawTilt = CGFloat(-g.y)
        case .landscapeLeft:      rawTilt = CGFloat(g.y)
        default:                  rawTilt = viewSize.width > viewSize.height ? CGFloat(-g.y) : CGFloat(g.x)
        }
        #else
        let rawTilt = CGFloat(g.x)
        #endif
        let deadzone: CGFloat = 0.035
        let adjusted: CGFloat = abs(rawTilt) < deadzone ? 0 : (rawTilt > 0 ? rawTilt - deadzone : rawTilt + deadzone)
        world.targetTiltRadians = max(-1.0, min(1.0, adjusted * 1.75)) * LocoBlobConstants.maxWorldTiltRadians
        #endif
    }
}
