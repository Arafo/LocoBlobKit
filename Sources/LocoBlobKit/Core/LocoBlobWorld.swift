import CoreGraphics
import Foundation

/// Self-contained 60 Hz LocoRoco soft-body physics container.
///
/// Use this directly in SpriteKit games, SwiftUI apps, macOS widgets, or interactive UI demos.
/// Operates in LocoRoco world units (`+X` right, `+Y` up).
public final class LocoBlobWorld {
    public private(set) var blobs: [LocoBlob] = []

    /// Enclosure bounds in world units (blobs bounce inside this rectangle).
    public var bounds: CGRect

    /// Optional custom solid obstacles (ramps, bumpers, UI cards) inside the world.
    public var obstacles: [LocoBlobObstacle] = []

    /// Optional closed walls; disable `hasCeiling` if you want blobs to drop in from above!
    public var hasFloor: Bool = true
    public var hasWalls: Bool = true
    public var hasCeiling: Bool = true

    /// Gravity scale multiplier (`1.0` = authentic LocoRoco `0.098` units/frame²; `0.0` = zero-G floating blobs!).
    public var gravityMultiplier: CGFloat = 1.0

    /// Surface friction (`standardFriction = 0.6005`, `iceFriction = -0.055`).
    public var friction: CGFloat = LocoBlobConstants.standardFriction

    /// Global stiffness multiplier (`1.0` = authentic LocoRoco; lower = softer/gelatinous, higher = firmer).
    public var stiffnessMultiplier: CGFloat = 1.0 {
        didSet {
            for blob in blobs { blob.stiffnessMultiplier = stiffnessMultiplier }
        }
    }

    /// World tilt angle in radians (clamped to `±30°`). Rotates gravity smoothly.
    public var tiltAngle: CGFloat = 0.0
    public var tiltLeftHeld: Bool = false
    public var tiltRightHeld: Bool = false
    /// When non-nil, smoothly tracks this analog target tilt (e.g. from CoreMotion gyroscope).
    public var targetTiltRadians: CGFloat? = nil

    private var tiltHoldDelayRemaining: Int = 0
    private var tiltReturnSpeedMult: CGFloat = 1.0

    /// Join & Jump controls
    public var isJoining: Bool = false
    /// When `false` (default), joining only merges blobs with matching appearances (e.g. yellow + yellow).
    /// Set `true` to let any two blobs merge into the larger blob's appearance.
    public var allowCrossAppearanceMerge: Bool = false

    public var isChargingJump: Bool = false
    public private(set) var jumpCharge: CGFloat = 0.0
    public var isPaused: Bool = false

    // Interactive drag / fling state (touch or mouse)
    private var draggedBlobId: Int? = nil
    private var dragTarget: CGPoint = .zero
    private var lastDragTarget: CGPoint = .zero
    private var dragVelocity: CGVector = .zero

    // Event callbacks
    public var onBlobStructureChanged: (() -> Void)?
    public var onBlobJumped: ((LocoBlob, CGFloat) -> Void)?
    public var onBlobSplit: ((LocoBlob, [LocoBlob]) -> Void)?
    public var onBlobMerged: ((LocoBlob) -> Void)?
    public var onBlobBounced: ((LocoBlob, CGPoint) -> Void)?

    private var nextBlobId: Int = 1
    private var joinHopFrames: Int = 0

    public init(bounds: CGRect = CGRect(x: 0, y: 0, width: 140, height: 100)) {
        self.bounds = bounds
    }

    /// Rotated gravity vector per 60 Hz frame.
    public var gravityVector: CGVector {
        let g = LocoBlobConstants.gravityMagnitude * gravityMultiplier
        return CGVector(dx: sin(tiltAngle) * g, dy: -cos(tiltAngle) * g)
    }

    /// Up vector perpendicular to current tilted gravity.
    public var worldUpVector: CGVector {
        CGVector(dx: -sin(tiltAngle), dy: cos(tiltAngle))
    }

    /// Weighted center of all active blobs.
    public var groupCenter: CGPoint {
        guard !blobs.isEmpty else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        var sx: CGFloat = 0, sy: CGFloat = 0, totalWeight: CGFloat = 0
        for b in blobs {
            let w = CGFloat(b.size)
            sx += b.core.x * w
            sy += b.core.y * w
            totalWeight += w
        }
        return CGPoint(x: sx / totalWeight, y: sy / totalWeight)
    }

    public var totalBlobSize: Int {
        blobs.reduce(0) { $0 + $1.size }
    }

    // MARK: - Spawning & Lifecycle

    @discardableResult
    public func spawnBlob(
        at center: CGPoint? = nil,
        size: Int = 2,
        appearance: LocoBlobAppearance = .kulche,
        initialVelocity: CGVector = .zero
    ) -> LocoBlob {
        let pos = center ?? CGPoint(
            x: bounds.midX + CGFloat.random(in: -bounds.width * 0.25...bounds.width * 0.25),
            y: bounds.midY + CGFloat.random(in: -bounds.height * 0.1...bounds.height * 0.25)
        )
        let blob = LocoBlob(
            id: allocateId(),
            center: pos,
            size: size,
            appearance: appearance,
            initialVelocity: initialVelocity,
            stiffnessMultiplier: stiffnessMultiplier
        )
        blobs.append(blob)
        onBlobStructureChanged?()
        return blob
    }

    public func removeBlob(id: Int) {
        if draggedBlobId == id { draggedBlobId = nil }
        blobs.removeAll { $0.id == id }
        onBlobStructureChanged?()
    }

    public func clearBlobs() {
        draggedBlobId = nil
        blobs.removeAll()
        onBlobStructureChanged?()
    }

    /// Returns the topmost blob containing `worldPoint`, if any.
    public func blob(at worldPoint: CGPoint, hitPadding: CGFloat = 2.0) -> LocoBlob? {
        for blob in blobs.reversed() {
            if blob.contains(point: worldPoint, padding: hitPadding) {
                return blob
            }
        }
        return nil
    }

    // MARK: - Actions: Jump, Split, Join, Drag, Poke

    /// Triggers a jump on all grounded blobs (or all blobs if `requireContact == false`).
    public func triggerJump(charge: CGFloat? = nil, requireContact: Bool = true) {
        let c = charge ?? jumpCharge
        let powerFrac = LocoBlobConstants.jumpStrength(forCharge: c)
        let up = worldUpVector
        for blob in blobs {
            if blob.applyJump(worldUp: up, powerFraction: powerFrac, requireContact: requireContact) {
                onBlobJumped?(blob, c)
            }
        }
        jumpCharge = 0
        isChargingJump = false
    }

    /// Splits a specific blob into `size` individual size-1 blobs.
    @discardableResult
    public func split(blobId: Int) -> Bool {
        guard let idx = blobs.firstIndex(where: { $0.id == blobId }) else { return false }
        let blob = blobs[idx]
        guard blob.canSplit(), blobs.count - 1 + blob.size <= LocoBlobConstants.maxBlobCount else {
            return false
        }
        guard let children = blob.split(nextId: allocateId, isPointClear: { [weak self] pt, r in
            self?.isPointClear(pt, clearance: r) ?? true
        }) else {
            return false
        }
        if draggedBlobId == blob.id { draggedBlobId = nil }
        blobs.remove(at: idx)
        blobs.append(contentsOf: children)
        onBlobStructureChanged?()
        onBlobSplit?(blob, children)
        return true
    }

    /// Splits every splittable blob in the world.
    @discardableResult
    public func splitAll() -> Bool {
        var didSplit = false
        var nextList: [LocoBlob] = []
        // Projected final blob count: every blob counts once until it is replaced by its children.
        var projectedCount = blobs.count
        for blob in blobs {
            if blob.canSplit() && projectedCount - 1 + blob.size <= LocoBlobConstants.maxBlobCount,
               let children = blob.split(nextId: allocateId, isPointClear: { [weak self] pt, r in
                   self?.isPointClear(pt, clearance: r) ?? true
               }) {
                projectedCount += children.count - 1
                nextList.append(contentsOf: children)
                onBlobSplit?(blob, children)
                didSplit = true
            } else {
                nextList.append(blob)
            }
        }
        if didSplit {
            draggedBlobId = nil
            blobs = nextList
            onBlobStructureChanged?()
        }
        return didSplit
    }

    /// Begins grabbing a blob under `worldPoint` so the user can squish and fling it around.
    @discardableResult
    public func beginDrag(at worldPoint: CGPoint) -> LocoBlob? {
        guard let hit = blob(at: worldPoint, hitPadding: 3.0) else { return nil }
        draggedBlobId = hit.id
        dragTarget = worldPoint
        lastDragTarget = worldPoint
        dragVelocity = .zero
        hit.jumpExpressionTimer = 12
        return hit
    }

    public func moveDrag(to worldPoint: CGPoint) {
        guard draggedBlobId != nil else { return }
        dragVelocity = CGVector(
            dx: (worldPoint.x - dragTarget.x) * 0.55 + dragVelocity.dx * 0.45,
            dy: (worldPoint.y - dragTarget.y) * 0.55 + dragVelocity.dy * 0.45
        )
        lastDragTarget = dragTarget
        dragTarget = worldPoint
    }

    public func endDrag() {
        if let id = draggedBlobId, let blob = blobs.first(where: { $0.id == id }) {
            let maxFling: CGFloat = 4.2
            let vx = max(-maxFling, min(maxFling, dragVelocity.dx * 0.65))
            let vy = max(-maxFling, min(maxFling, dragVelocity.dy * 0.65))
            blob.applyImpulse(CGVector(dx: vx, dy: vy))
            if hypot(vx, vy) > 1.2 {
                blob.jumpExpressionTimer = 24
            }
        }
        draggedBlobId = nil
        dragVelocity = .zero
    }

    /// Playful outward/upward poke at `worldPoint` (great for tap reactions!).
    public func poke(at worldPoint: CGPoint, strength: CGFloat = 2.6, radius: CGFloat = 28.0) {
        for blob in blobs {
            let dx = blob.core.x - worldPoint.x
            let dy = blob.core.y - worldPoint.y
            let d = hypot(dx, dy)
            guard d < radius + blob.radius else { continue }
            let nx = d > 1e-3 ? dx / d : 0
            let ny = d > 1e-3 ? dy / d : 1
            let falloff = max(0.25, 1.0 - d / (radius + blob.radius))
            blob.applyLocalForce(
                CGVector(dx: nx * strength * falloff, dy: (ny * 0.7 + 0.55) * strength * falloff),
                at: worldPoint,
                falloffRadius: blob.radius * 2.2
            )
            blob.jumpExpressionTimer = 18
        }
    }

    // MARK: - 60 Hz Fixed Simulation Step

    public func stepFixedFrame() {
        if isPaused { return }

        stepWorldTilt()
        if isChargingJump {
            jumpCharge = min(1.0, jumpCharge + LocoBlobConstants.jumpChargeRatePerFrame)
        } else {
            jumpCharge = 0
        }

        let g = gravityVector

        // 1. Verlet integration + complete-graph spring relaxation
        for blob in blobs {
            if isChargingJump && blob.contactCount > 0 {
                blob.squashCharge = min(1.0, jumpCharge)
            } else {
                blob.squashCharge *= 0.8
            }
            let blobGravity = (blob.id == draggedBlobId)
                ? CGVector(dx: g.dx * 0.15, dy: g.dy * 0.15)
                : g
            blob.integrateAndRelaxSprings(gravity: blobGravity, damping: LocoBlobConstants.damping)
        }

        // 1b. Active touch/mouse drag spring pull
        if let dragId = draggedBlobId, let blob = blobs.first(where: { $0.id == dragId }) {
            let dx = dragTarget.x - blob.core.x
            let dy = dragTarget.y - blob.core.y
            let pullX = dx * 0.34
            let pullY = dy * 0.34
            for i in 0..<blob.vertexCount {
                blob.cur[i].x += pullX
                blob.cur[i].y += pullY
            }
        }

        // 2. Join attraction & rhythmic hops
        if isJoining {
            joinHopFrames += 1
            if blobs.count > 1 {
                applyJoinAttraction()
            }
        } else {
            joinHopFrames = 0
        }

        // 3. Recompute centroids & reset contacts
        for blob in blobs {
            blob.updateCoreAndResetContacts()
        }

        // 4. Container walls, custom obstacles & blob-to-blob collisions (2 sub-passes)
        for blob in blobs {
            sweepFastVerticesAgainstObstacles(for: blob)
        }
        for _ in 0..<2 {
            for blob in blobs {
                resolveEnvironmentCollisions(for: blob)
            }
            resolveBlobToBlobCollisions()
        }

        // 5. Anti-collapse, anti-inversion & face lag
        for blob in blobs {
            blob.enforceAntiCollapseAndStretch()
            blob.enforceAntiInversion()
            blob.updateFaceLag()
            updateExpression(for: blob)
        }

        // 6. Contour-stitching merges while holding Join
        if isJoining && blobs.count > 1 {
            attemptPendingMerges()
        }
    }

    // MARK: - Tilt State Machine

    private func stepWorldTilt() {
        if let target = targetTiltRadians {
            let clamped = max(-LocoBlobConstants.maxWorldTiltRadians, min(LocoBlobConstants.maxWorldTiltRadians, target))
            tiltAngle += (clamped - tiltAngle) * 0.20
            tiltHoldDelayRemaining = 0
            tiltReturnSpeedMult = 1.0
            return
        }

        if tiltLeftHeld && !tiltRightHeld {
            tiltAngle = max(-LocoBlobConstants.maxWorldTiltRadians, tiltAngle - LocoBlobConstants.tiltRatePerFrame)
            tiltHoldDelayRemaining = LocoBlobConstants.tiltHoldDelayFrames
            tiltReturnSpeedMult = 1.0
        } else if tiltRightHeld && !tiltLeftHeld {
            tiltAngle = min(LocoBlobConstants.maxWorldTiltRadians, tiltAngle + LocoBlobConstants.tiltRatePerFrame)
            tiltHoldDelayRemaining = LocoBlobConstants.tiltHoldDelayFrames
            tiltReturnSpeedMult = 1.0
        } else if tiltHoldDelayRemaining > 0 {
            tiltHoldDelayRemaining -= 1
        } else if abs(tiltAngle) > 1e-5 {
            tiltReturnSpeedMult += LocoBlobConstants.tiltReturnAccelPerFrame
            let step = LocoBlobConstants.tiltReturnBaseRate * tiltReturnSpeedMult
            tiltAngle = tiltAngle > 0 ? max(0, tiltAngle - step) : min(0, tiltAngle + step)
        }
    }

    // MARK: - Collisions

    private func resolveEnvironmentCollisions(for blob: LocoBlob) {
        let defaultKeep = tangentialKeepFor(friction: friction)
        let n = blob.vertexCount

        for i in 0..<n {
            var p = blob.cur[i]
            var prevP = blob.prev[i]

            // Custom obstacles
            for obs in obstacles {
                let keep = tangentialKeepFor(friction: obs.friction ?? friction)
                switch obs.shape {
                case let .capsule(a, b, thickness):
                    let (closest, _) = closestPointOnSeg(p, a, b)
                    let dx = p.x - closest.x
                    let dy = p.y - closest.y
                    let dist = hypot(dx, dy)
                    if dist < thickness {
                        let nx = dist > 1e-4 ? dx / dist : 0
                        let ny = dist > 1e-4 ? dy / dist : 1
                        p.x = closest.x + nx * thickness
                        p.y = closest.y + ny * thickness
                        handleObstacleContact(blob: blob, obs: obs, cur: &p, prev: &prevP, normal: CGVector(dx: nx, dy: ny), keep: keep, hitPoint: closest)
                    }

                case let .circle(center, radius):
                    let dx = p.x - center.x
                    let dy = p.y - center.y
                    let dist = hypot(dx, dy)
                    if dist < radius {
                        let nx = dist > 1e-4 ? dx / dist : 0
                        let ny = dist > 1e-4 ? dy / dist : 1
                        p.x = center.x + nx * radius
                        p.y = center.y + ny * radius
                        handleObstacleContact(blob: blob, obs: obs, cur: &p, prev: &prevP, normal: CGVector(dx: nx, dy: ny), keep: keep, hitPoint: p)
                    }

                case let .rect(r):
                    if r.contains(p) {
                        let dLeft = p.x - r.minX
                        let dRight = r.maxX - p.x
                        let dBottom = p.y - r.minY
                        let dTop = r.maxY - p.y
                        let minD = min(min(dLeft, dRight), min(dBottom, dTop))
                        let normal: CGVector
                        if minD == dTop {
                            p.y = r.maxY
                            normal = CGVector(dx: 0, dy: 1)
                        } else if minD == dBottom {
                            p.y = r.minY
                            normal = CGVector(dx: 0, dy: -1)
                        } else if minD == dLeft {
                            p.x = r.minX
                            normal = CGVector(dx: -1, dy: 0)
                        } else {
                            p.x = r.maxX
                            normal = CGVector(dx: 1, dy: 0)
                        }
                        handleObstacleContact(blob: blob, obs: obs, cur: &p, prev: &prevP, normal: normal, keep: keep, hitPoint: p)
                    }
                }
            }

            // Container enclosure bounds
            if hasFloor && p.y < bounds.minY {
                p.y = bounds.minY
                let nVec = CGVector(dx: 0, dy: 1)
                applySurfaceFriction(cur: &p, prev: &prevP, normal: nVec, tangentialKeep: defaultKeep, restitution: 0.12)
                blob.accumulateContact(normal: nVec)
            }
            if hasCeiling && p.y > bounds.maxY {
                p.y = bounds.maxY
                let nVec = CGVector(dx: 0, dy: -1)
                applySurfaceFriction(cur: &p, prev: &prevP, normal: nVec, tangentialKeep: defaultKeep, restitution: 0.12)
                blob.accumulateContact(normal: nVec)
            }
            if hasWalls {
                if p.x < bounds.minX {
                    p.x = bounds.minX
                    let nVec = CGVector(dx: 1, dy: 0)
                    applySurfaceFriction(cur: &p, prev: &prevP, normal: nVec, tangentialKeep: defaultKeep, restitution: 0.16)
                    blob.accumulateContact(normal: nVec)
                } else if p.x > bounds.maxX {
                    p.x = bounds.maxX
                    let nVec = CGVector(dx: -1, dy: 0)
                    applySurfaceFriction(cur: &p, prev: &prevP, normal: nVec, tangentialKeep: defaultKeep, restitution: 0.16)
                    blob.accumulateContact(normal: nVec)
                }
            }

            blob.cur[i] = p
            blob.prev[i] = prevP
        }
    }

    /// Stops vertices that moved far enough this frame to skip over a thin obstacle.
    ///
    /// Walks each vertex from its start-of-frame position to its current one in steps no larger
    /// than half the obstacle's thickness. The first sample inside the obstacle is always on the
    /// side the vertex entered from, so the normal collision pass then pushes it back out that way.
    private func sweepFastVerticesAgainstObstacles(for blob: LocoBlob) {
        guard !obstacles.isEmpty, blob.frameStartPositions.count == blob.vertexCount else { return }
        for i in 0..<blob.vertexCount {
            let start = blob.frameStartPositions[i]
            for obs in obstacles {
                let end = blob.cur[i]
                let dx = end.x - start.x
                let dy = end.y - start.y
                let len = hypot(dx, dy)
                let step = obs.sweepStep
                guard len > step, !obs.contains(start) else { continue }
                let samples = Int(ceil(len / step))
                for k in 1...samples {
                    let t = CGFloat(k) / CGFloat(samples)
                    let q = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
                    if obs.contains(q) {
                        blob.cur[i] = q
                        break
                    }
                }
            }
        }
    }

    private func handleObstacleContact(
        blob: LocoBlob,
        obs: LocoBlobObstacle,
        cur p: inout CGPoint,
        prev prevP: inout CGPoint,
        normal: CGVector,
        keep: CGFloat,
        hitPoint: CGPoint
    ) {
        if obs.isBouncy {
            let vn = (p.x - prevP.x) * normal.dx + (p.y - prevP.y) * normal.dy
            if vn < -0.55 {
                let launch = min(LocoBlobConstants.maxJumpVelocity * 1.15, max(2.2, -vn * 1.55 * obs.bounceFactor))
                prevP.x = p.x - normal.dx * launch
                prevP.y = p.y - normal.dy * launch
                blob.jumpExpressionTimer = 24
                onBlobBounced?(blob, hitPoint)
            } else {
                applySurfaceFriction(cur: &p, prev: &prevP, normal: normal, tangentialKeep: keep, restitution: 0.25)
            }
            blob.accumulateContact(normal: normal, bounceMultiplier: obs.bounceFactor)
        } else {
            applySurfaceFriction(cur: &p, prev: &prevP, normal: normal, tangentialKeep: keep, restitution: 0.10)
            blob.accumulateContact(normal: normal, bounceMultiplier: 1.0)
        }
    }

    private func resolveBlobToBlobCollisions() {
        let count = blobs.count
        guard count > 1 else { return }
        let pushStiff = LocoBlobConstants.blobCollisionStiffness * (isJoining ? 0.15 : 0.45)

        for i in 0..<count {
            for j in (i + 1)..<count {
                let a = blobs[i]
                let b = blobs[j]
                let dx = a.core.x - b.core.x
                let dy = a.core.y - b.core.y
                let distSq = dx * dx + dy * dy
                let minDist = (a.radius + b.radius) * 0.94
                if distSq >= minDist * minDist { continue }

                let dist = max(0.05, sqrt(distSq))
                let nx = dx / dist
                let ny = dy / dist
                let overlap = (minDist - dist) * pushStiff

                let wA = CGFloat(b.size) / CGFloat(a.size + b.size)
                let wB = 1.0 - wA

                for vi in 0..<a.vertexCount {
                    let vdx = a.cur[vi].x - b.core.x
                    let vdy = a.cur[vi].y - b.core.y
                    let vd = hypot(vdx, vdy)
                    if vd < b.radius * 1.02 {
                        let localPush = (b.radius * 1.02 - vd) * pushStiff
                        let ux = vd > 1e-3 ? vdx / vd : nx
                        let uy = vd > 1e-3 ? vdy / vd : ny
                        a.cur[vi].x += ux * localPush * wA
                        a.cur[vi].y += uy * localPush * wA
                    } else {
                        a.cur[vi].x += nx * overlap * 0.18 * wA
                        a.cur[vi].y += ny * overlap * 0.18 * wA
                    }
                }
                for vj in 0..<b.vertexCount {
                    let vdx = b.cur[vj].x - a.core.x
                    let vdy = b.cur[vj].y - a.core.y
                    let vd = hypot(vdx, vdy)
                    if vd < a.radius * 1.02 {
                        let localPush = (a.radius * 1.02 - vd) * pushStiff
                        let ux = vd > 1e-3 ? vdx / vd : -nx
                        let uy = vd > 1e-3 ? vdy / vd : -ny
                        b.cur[vj].x += ux * localPush * wB
                        b.cur[vj].y += uy * localPush * wB
                    } else {
                        b.cur[vj].x -= nx * overlap * 0.18 * wB
                        b.cur[vj].y -= ny * overlap * 0.18 * wB
                    }
                }
            }
        }
    }

    // MARK: - Join Attraction & Merge

    private func applyJoinAttraction() {
        let up = worldUpVector
        let doRhythmHop = (joinHopFrames % 28 == 1)

        // Pull each blob toward the centroid of blobs it can merge with
        for blob in blobs {
            var sx: CGFloat = 0, sy: CGFloat = 0, wSum: CGFloat = 0
            for other in blobs where canMerge(blob, other) || other.id == blob.id {
                let w = CGFloat(other.size)
                sx += other.core.x * w
                sy += other.core.y * w
                wSum += w
            }
            guard wSum > 0 else { continue }
            let targetX = sx / wSum
            let targetY = sy / wSum
            let dx = targetX - blob.core.x
            let dy = targetY - blob.core.y
            let dist = hypot(dx, dy)
            if dist < 1.0 { continue }

            let pull = min(0.24, 0.06 + dist * 0.004)
            let px = (dx / dist) * pull
            let py = (dy / dist) * pull
            for i in 0..<blob.vertexCount {
                blob.cur[i].x += px
                blob.cur[i].y += py
            }
            if doRhythmHop && blob.contactCount > 0 {
                let hopSpeed: CGFloat = 1.05
                for i in 0..<blob.vertexCount {
                    blob.prev[i].x -= up.dx * hopSpeed + (dx / dist) * 0.45
                    blob.prev[i].y -= up.dy * hopSpeed + (dy / dist) * 0.45
                }
            }
        }
    }

    private func canMerge(_ a: LocoBlob, _ b: LocoBlob) -> Bool {
        guard a.id != b.id else { return false }
        guard a.size + b.size <= LocoBlobConstants.maxTotalSize else { return false }
        return allowCrossAppearanceMerge || a.appearance == b.appearance
    }

    private func attemptPendingMerges() {
        for i in 0..<blobs.count {
            for j in (i + 1)..<blobs.count {
                let a = blobs[i]
                let b = blobs[j]
                guard canMerge(a, b) else { continue }
                let dist = hypot(a.core.x - b.core.x, a.core.y - b.core.y)
                let mergeThreshold = (a.radius + b.radius) * 0.96
                if dist <= mergeThreshold {
                    let merged = LocoBlob.merge(a, b, newId: allocateId())
                    if draggedBlobId == a.id || draggedBlobId == b.id {
                        draggedBlobId = merged.id
                    }
                    blobs.remove(at: j)
                    blobs.remove(at: i)
                    blobs.append(merged)
                    onBlobStructureChanged?()
                    onBlobMerged?(merged)
                    return
                }
            }
        }
    }

    private func updateExpression(for blob: LocoBlob) {
        if isJoining || blob.singTimer > 0 {
            blob.expression = .singing
        } else if blob.squashCharge > 0.15 {
            blob.expression = .squashed
        } else if blob.jumpExpressionTimer > 0 {
            blob.expression = .jumping
        } else {
            blob.expression = .neutral
        }
    }

    public func isPointClear(_ p: CGPoint, clearance: CGFloat) -> Bool {
        if hasWalls && (p.x < bounds.minX + clearance || p.x > bounds.maxX - clearance) { return false }
        if hasFloor && p.y < bounds.minY + clearance { return false }
        if hasCeiling && p.y > bounds.maxY - clearance { return false }
        for obs in obstacles {
            switch obs.shape {
            case let .capsule(a, b, thickness):
                let (cl, _) = closestPointOnSeg(p, a, b)
                if hypot(p.x - cl.x, p.y - cl.y) < thickness + clearance { return false }
            case let .circle(center, radius):
                if hypot(p.x - center.x, p.y - center.y) < radius + clearance { return false }
            case let .rect(r):
                if r.insetBy(dx: -clearance, dy: -clearance).contains(p) { return false }
            }
        }
        return true
    }

    private func tangentialKeepFor(friction f: CGFloat) -> CGFloat {
        if f < 0 { return 0.996 }
        return max(0.70, min(0.99, 1.0 - f * 0.18))
    }

    private func applySurfaceFriction(
        cur: inout CGPoint,
        prev: inout CGPoint,
        normal: CGVector,
        tangentialKeep: CGFloat,
        restitution: CGFloat
    ) {
        let vx = cur.x - prev.x
        let vy = cur.y - prev.y
        let vn = vx * normal.dx + vy * normal.dy
        let tx = -normal.dy
        let ty = normal.dx
        let vt = vx * tx + vy * ty

        let newVn = vn < 0 ? -vn * restitution : vn
        let newVt = vt * tangentialKeep

        let nvx = normal.dx * newVn + tx * newVt
        let nvy = normal.dy * newVn + ty * newVt
        prev.x = cur.x - nvx
        prev.y = cur.y - nvy
    }

    private func allocateId() -> Int {
        defer { nextBlobId += 1 }
        return nextBlobId
    }
}

@inline(__always)
private func closestPointOnSeg(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGFloat) {
    let abx = b.x - a.x
    let aby = b.y - a.y
    let lenSq = abx * abx + aby * aby
    if lenSq < 1e-8 { return (a, 0) }
    let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq))
    return (CGPoint(x: a.x + abx * t, y: a.y + aby * t), t)
}

private extension LocoBlobObstacle {
    /// Whether `p` is inside the solid region (the same test the collision pass uses).
    func contains(_ p: CGPoint) -> Bool {
        switch shape {
        case let .capsule(a, b, thickness):
            let (closest, _) = closestPointOnSeg(p, a, b)
            return hypot(p.x - closest.x, p.y - closest.y) < thickness
        case let .circle(center, radius):
            return hypot(p.x - center.x, p.y - center.y) < radius
        case let .rect(r):
            return r.contains(p)
        }
    }

    /// Largest sweep step that cannot jump across the obstacle's thinnest half.
    var sweepStep: CGFloat {
        let halfThickness: CGFloat
        switch shape {
        case let .capsule(_, _, thickness): halfThickness = thickness
        case let .circle(_, radius): halfThickness = radius
        case let .rect(r): halfThickness = min(r.width, r.height) * 0.5
        }
        return max(0.05, halfThickness * 0.9)
    }
}
