import CoreGraphics
import Foundation

/// A single distance constraint in the complete-graph ($K_N$) soft-body solver.
public struct LocoBlobSpring: Sendable {
    public var halfKTimesL: CGFloat
    public var halfK: CGFloat
    public let restLength: CGFloat
    public let idxA: Int
    public let idxB: Int
}

/// Reusable soft-body blob powered by Verlet integration and a complete-graph spring-mass ring.
///
/// Operates in standard Y-up world units (`+X` right, `+Y` up).
/// Render directly via `LocoBlobRenderer` (CoreGraphics / SwiftUI `Canvas`), `LocoBlobNode` (SpriteKit),
/// or `LocoBlobView` (drop-in interactive SwiftUI component).
public final class LocoBlob: Identifiable {
    public let id: Int

    /// Visual style (one of the 6 classic characters or any custom color/hair/face).
    public var appearance: LocoBlobAppearance

    /// Blob size (1...20). Controls area, radius, and perimeter vertex count (8 / 16 / 32).
    public private(set) var size: Int
    /// Number of perimeter point masses `N` (8, 16, or 32).
    public private(set) var vertexCount: Int

    /// Double-buffered perimeter positions (in world units), clockwise from north-pole vertex 0 `(0, +R)`.
    public var cur: [CGPoint]
    public var prev: [CGPoint]

    /// Perimeter positions at the start of the current frame, before integration.
    /// Used by `LocoBlobWorld` to sweep fast vertices against thin obstacles.
    internal var frameStartPositions: [CGPoint] = []

    /// Complete-graph springs (`M = N * (N - 1) / 2`).
    public private(set) var springs: [LocoBlobSpring] = []

    /// Current and previous centroid.
    public var core: CGPoint
    public var prevCore: CGPoint

    /// Dynamic stiffness multiplier (default `1.0`). Lower = squishier, higher = firmer.
    public var stiffnessMultiplier: CGFloat = 1.0 {
        didSet {
            if abs(stiffnessMultiplier - oldValue) > 1e-4 {
                rebuildSpringStiffness()
            }
        }
    }

    /// Age in 60 Hz simulation frames (split requires `>= 17`).
    public var ageFrames: Int = 0

    /// Per-frame surface contact normal accumulator (used for reliable directional jumping).
    public var contactNormalSum: CGVector = .zero
    public var contactCount: Int = 0
    public var surfaceBounceMultiplier: CGFloat = 1.0

    /// Smoothed lagging face offset (`0.25` exponential lerp per frame).
    public var smoothedFaceOffset: CGPoint = .zero
    /// Visual squash & expression timers.
    public var jumpExpressionTimer: Int = 0
    public var singTimer: Int = 0
    public var expression: LocoBlobExpression = .neutral
    /// Optional caller-driven expression override (set to `nil` to return to automatic physics expressions).
    public var expressionOverride: LocoBlobExpression? = nil
    public var squashCharge: CGFloat = 0.0

    /// World-space rest radius `R = 4.0 * radiusScale * sqrt(size / π)`.
    public var radius: CGFloat {
        LocoBlobConstants.radius(forSize: size)
    }

    /// World-space area (proportional to `size`).
    public var area: CGFloat {
        CGFloat(size)
    }

    /// Axis-aligned bounding box in world units.
    public var bounds: CGRect {
        guard let first = cur.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in cur {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public init(
        id: Int,
        center: CGPoint,
        size: Int = 1,
        appearance: LocoBlobAppearance = .kulche,
        initialVelocity: CGVector = .zero,
        stiffnessMultiplier: CGFloat = 1.0
    ) {
        self.id = id
        self.appearance = appearance
        self.size = max(1, min(LocoBlobConstants.maxTotalSize, size))
        self.vertexCount = LocoBlobConstants.vertexCount(forSize: self.size)
        self.stiffnessMultiplier = stiffnessMultiplier
        self.core = center
        self.prevCore = CGPoint(x: center.x - initialVelocity.dx, y: center.y - initialVelocity.dy)

        let r = LocoBlobConstants.radius(forSize: self.size)
        var pts: [CGPoint] = []
        pts.reserveCapacity(self.vertexCount)
        for i in 0..<self.vertexCount {
            let theta = (2.0 * .pi * CGFloat(i)) / CGFloat(self.vertexCount)
            pts.append(CGPoint(x: center.x + r * sin(theta), y: center.y + r * cos(theta)))
        }
        self.cur = pts
        self.prev = pts.map { CGPoint(x: $0.x - initialVelocity.dx, y: $0.y - initialVelocity.dy) }
        buildCompleteGraphSprings()
    }

    // MARK: - Complete-Graph Spring Builder

    private func buildCompleteGraphSprings() {
        let n = vertexCount
        let r = radius
        var restPts: [CGPoint] = []
        restPts.reserveCapacity(n)
        for i in 0..<n {
            let theta = (2.0 * .pi * CGFloat(i)) / CGFloat(n)
            restPts.append(CGPoint(x: r * sin(theta), y: r * cos(theta)))
        }

        springs.removeAll(keepingCapacity: true)
        springs.reserveCapacity(n * (n - 1) / 2)

        let kBase = LocoBlobConstants.baseStiffness
        let nFloat = CGFloat(n)

        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = restPts[i].x - restPts[j].x
                let dy = restPts[i].y - restPts[j].y
                let restLen = max(hypot(dx, dy), LocoBlobConstants.springMinRestLength)
                let rawK = stiffnessMultiplier * (LocoBlobConstants.springNumerator * kBase / restLen) / nFloat
                let k = min(LocoBlobConstants.springMaxStiffness, max(LocoBlobConstants.springMinStiffness, rawK))
                let halfK = 0.5 * k
                springs.append(LocoBlobSpring(
                    halfKTimesL: halfK * restLen,
                    halfK: halfK,
                    restLength: restLen,
                    idxA: i,
                    idxB: j
                ))
            }
        }
    }

    private func rebuildSpringStiffness() {
        let kBase = LocoBlobConstants.baseStiffness
        let nFloat = CGFloat(vertexCount)
        for idx in springs.indices {
            let L = springs[idx].restLength
            let rawK = stiffnessMultiplier * (LocoBlobConstants.springNumerator * kBase / L) / nFloat
            let k = min(LocoBlobConstants.springMaxStiffness, max(LocoBlobConstants.springMinStiffness, rawK))
            let halfK = 0.5 * k
            springs[idx].halfK = halfK
            springs[idx].halfKTimesL = halfK * L
        }
    }

    // MARK: - Growth, Shrink & Direct Forces

    /// Grow blob by `delta` (clamped to 20), smoothly preserving its deformed silhouette & velocity.
    /// A `delta` of zero or less does nothing; use `shrink(by:)` to make a blob smaller.
    public func grow(by delta: Int = 1) {
        guard delta > 0 else { return }
        let newSize = min(LocoBlobConstants.maxTotalSize, size + delta)
        guard newSize != size else { return }
        let oldN = vertexCount
        let newN = LocoBlobConstants.vertexCount(forSize: newSize)
        let avgVel = averageVelocity()

        size = newSize
        vertexCount = newN

        if newN != oldN {
            resampleContour(from: oldN, to: newN)
        } else {
            for i in 0..<vertexCount {
                let dx = cur[i].x - core.x
                let dy = cur[i].y - core.y
                cur[i].x += dx * 0.08 + avgVel.dx * 0.05
                cur[i].y += dy * 0.08 + avgVel.dy * 0.05
            }
        }
        buildCompleteGraphSprings()
    }

    /// Shrink blob by `delta`. Returns `true` if the blob shrank, or `false` (leaving it unchanged)
    /// if `delta` is zero or less, or if it would shrink below size 1.
    @discardableResult
    public func shrink(by delta: Int = 1) -> Bool {
        guard delta > 0 else { return false }
        let newSize = size - delta
        guard newSize >= 1 else { return false }
        let oldN = vertexCount
        let newN = LocoBlobConstants.vertexCount(forSize: newSize)
        size = newSize
        vertexCount = newN

        if newN != oldN {
            resampleContour(from: oldN, to: newN)
        }
        buildCompleteGraphSprings()
        return true
    }

    private func resampleContour(from oldN: Int, to newN: Int) {
        var newCur: [CGPoint] = []
        var newPrev: [CGPoint] = []
        newCur.reserveCapacity(newN)
        newPrev.reserveCapacity(newN)
        for i in 0..<newN {
            let f = CGFloat(i) * CGFloat(oldN) / CGFloat(newN)
            let i0 = Int(floor(f)) % oldN
            let i1 = (i0 + 1) % oldN
            let t = f - floor(f)
            newCur.append(blobLerp(cur[i0], cur[i1], t))
            newPrev.append(blobLerp(prev[i0], prev[i1], t))
        }
        cur = newCur
        prev = newPrev
    }

    /// Instantaneous velocity impulse applied evenly to all perimeter vertices (world units / frame).
    public func applyImpulse(_ impulse: CGVector) {
        for i in 0..<vertexCount {
            cur[i].x += impulse.dx
            cur[i].y += impulse.dy
        }
    }

    /// Localized squishy poke/pull force around a world point (great for touch/mouse interaction).
    public func applyLocalForce(_ force: CGVector, at point: CGPoint, falloffRadius: CGFloat? = nil) {
        let rad = max(1.0, falloffRadius ?? (radius * 1.45))
        for i in 0..<vertexCount {
            let d = hypot(cur[i].x - point.x, cur[i].y - point.y)
            guard d < rad else { continue }
            let weight = 1.0 - (d / rad)
            cur[i].x += force.dx * weight
            cur[i].y += force.dy * weight
        }
    }

    /// Hit-test whether a world-space point is inside (or within padding of) this blob.
    public func contains(point: CGPoint, padding: CGFloat = 0) -> Bool {
        let paddedBounds = bounds.insetBy(dx: -padding, dy: -padding)
        guard paddedBounds.contains(point) else { return false }
        if hypot(point.x - core.x, point.y - core.y) <= radius * 0.92 + padding {
            return true
        }
        // Ray-cast against perimeter polygon
        var inside = false
        var j = vertexCount - 1
        for i in 0..<vertexCount {
            let pi = cur[i]
            let pj = cur[j]
            if ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / max(1e-6, abs(pj.y - pi.y)) * (pj.y >= pi.y ? 1 : -1) + pi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Step 1: Verlet Integration & Complete-Graph Springs

    public func integrateAndRelaxSprings(gravity: CGVector, damping: CGFloat = LocoBlobConstants.damping) {
        ageFrames += 1
        if jumpExpressionTimer > 0 { jumpExpressionTimer -= 1 }
        if singTimer > 0 { singTimer -= 1 }

        var gx = gravity.dx
        var gy = gravity.dy
        if squashCharge > 0.01 && contactCount > 0 {
            gx *= (1.0 + squashCharge * 1.4)
            gy *= (1.0 + squashCharge * 1.4)
        }

        frameStartPositions = cur

        let n = vertexCount
        for i in 0..<n {
            let pCur = cur[i]
            let pPrev = prev[i]
            let nx = pCur.x + damping * (pCur.x - pPrev.x) + gx
            let ny = pCur.y + damping * (pCur.y - pPrev.y) + gy
            prev[i] = pCur
            cur[i] = CGPoint(x: nx, y: ny)
        }

        for s in springs {
            let a = cur[s.idxA]
            let b = cur[s.idxB]
            let dx = a.x - b.x
            let dy = a.y - b.y
            let distSq = dx * dx + dy * dy
            if distSq < 1e-10 { continue }
            let invDist = 1.0 / sqrt(distSq)
            let scale = s.halfKTimesL * invDist - s.halfK
            let cx = dx * scale
            let cy = dy * scale
            cur[s.idxA] = CGPoint(x: a.x + cx, y: a.y + cy)
            cur[s.idxB] = CGPoint(x: b.x - cx, y: b.y - cy)
        }
    }

    // MARK: - Step 2: Recompute Centroid & Reset Contacts

    public func updateCoreAndResetContacts() {
        prevCore = core
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for p in cur {
            sx += p.x
            sy += p.y
        }
        let invN = 1.0 / CGFloat(vertexCount)
        core = CGPoint(x: sx * invN, y: sy * invN)

        contactNormalSum = .zero
        contactCount = 0
        surfaceBounceMultiplier = 1.0
    }

    public func accumulateContact(normal: CGVector, bounceMultiplier: CGFloat = 1.0) {
        contactNormalSum.dx += normal.dx
        contactNormalSum.dy += normal.dy
        contactCount += 1
        surfaceBounceMultiplier = max(surfaceBounceMultiplier, bounceMultiplier)
    }

    // MARK: - Step 3: Anti-Collapse & Max-Stretch Guard

    public func enforceAntiCollapseAndStretch() {
        let n = vertexCount
        let r = radius
        let minEdgeDist = LocoBlobConstants.minEdgeClearanceRatio * r
        let maxVertDist = LocoBlobConstants.maxVertexStretchRatio * r

        var cx: CGFloat = 0
        var cy: CGFloat = 0
        for p in cur { cx += p.x; cy += p.y }
        let invN = 1.0 / CGFloat(n)
        cx *= invN
        cy *= invN

        for i in 0..<n {
            let j = (i + 1) % n
            let pi = cur[i]
            let pj = cur[j]
            let ex = pj.x - pi.x
            let ey = pj.y - pi.y
            let eLen = max(hypot(ex, ey), 0.01)
            let invLen = 1.0 / eLen
            let ux = ex * invLen
            let uy = ey * invLen

            let toCx = cx - pi.x
            let toCy = cy - pi.y
            let proj = toCx * ux + toCy * uy

            let w0: CGFloat
            let w1: CGFloat
            let qMinusCx: CGFloat
            let qMinusCy: CGFloat
            let dist: CGFloat

            if proj <= 0 {
                w0 = 1.0; w1 = 0.0
                qMinusCx = -toCx; qMinusCy = -toCy
                dist = hypot(toCx, toCy)
            } else if proj >= eLen {
                w0 = 0.0; w1 = 1.0
                let dx = pj.x - cx
                let dy = pj.y - cy
                qMinusCx = dx; qMinusCy = dy
                dist = hypot(dx, dy)
            } else {
                let t = proj / eLen
                w0 = 1.0 - t; w1 = t
                qMinusCx = ux * proj - toCx
                qMinusCy = uy * proj - toCy
                dist = hypot(qMinusCx, qMinusCy)
            }

            if dist > 1e-4 && dist < minEdgeDist {
                let factor = (minEdgeDist / dist) - 1.0
                if w0 > 0 {
                    let dx = qMinusCx * w0 * factor
                    let dy = qMinusCy * w0 * factor
                    cur[i].x += dx;  cur[i].y += dy
                    prev[i].x += dx; prev[i].y += dy
                }
                if w1 > 0 {
                    let dx = qMinusCx * w1 * factor
                    let dy = qMinusCy * w1 * factor
                    cur[j].x += dx;  cur[j].y += dy
                    prev[j].x += dx; prev[j].y += dy
                }
            }
        }

        for i in 0..<n {
            let dx = cur[i].x - core.x
            let dy = cur[i].y - core.y
            let dist = hypot(dx, dy)
            if dist > maxVertDist {
                let s = maxVertDist / dist
                let corrX = dx * s - dx
                let corrY = dy * s - dy
                cur[i].x += corrX;  cur[i].y += corrY
                prev[i].x += corrX; prev[i].y += corrY
            }
        }
    }

    // MARK: - Step 4: Mirror-Unfolding Anti-Inversion Guard

    public func enforceAntiInversion() {
        let n = vertexCount
        let half = n / 2
        guard half >= 2 else { return }

        let axisX = cur[half].x - cur[0].x
        let axisY = cur[half].y - cur[0].y

        for i in 1..<half {
            let j = n - i
            let spanX = cur[i].x - cur[j].x
            let spanY = cur[i].y - cur[j].y
            let cross = axisX * spanY - axisY * spanX
            if cross < 0 {
                cur.swapAt(i, j)
                prev.swapAt(i, j)
            }
        }
    }

    // MARK: - Jumping

    @discardableResult
    public func applyJump(worldUp: CGVector, powerFraction: CGFloat = 1.0, requireContact: Bool = true) -> Bool {
        if requireContact && contactCount == 0 { return false }
        var nx: CGFloat
        var ny: CGFloat
        if contactCount > 0 {
            nx = contactNormalSum.dx / CGFloat(contactCount)
            ny = contactNormalSum.dy / CGFloat(contactCount)
            let len = hypot(nx, ny)
            if len < 1e-4 {
                nx = worldUp.dx
                ny = worldUp.dy
            } else {
                nx /= len
                ny /= len
            }
        } else {
            nx = worldUp.dx
            ny = worldUp.dy
        }

        let alignment = max(0.35, nx * worldUp.dx + ny * worldUp.dy)
        let rawPower = min(
            LocoBlobConstants.jumpPower,
            LocoBlobConstants.jumpPower * alignment * powerFraction * surfaceBounceMultiplier
        )
        let impulseMag = rawPower * LocoBlobConstants.jumpScale
        let jx = nx * impulseMag
        let jy = ny * impulseMag

        for i in 0..<vertexCount {
            cur[i].x += jx
            cur[i].y += jy
        }
        jumpExpressionTimer = 26
        squashCharge = 0
        return true
    }

    // MARK: - Splitting

    public func canSplit() -> Bool {
        size > 1 && ageFrames >= LocoBlobConstants.splitCooldownFrames
    }

    public func split(nextId: () -> Int, isPointClear: (CGPoint, CGFloat) -> Bool = { _, _ in true }) -> [LocoBlob]? {
        guard canSplit() else { return nil }
        let vel = averageVelocity()
        let childRadius = LocoBlobConstants.radius(forSize: 1)
        var children: [LocoBlob] = []
        children.reserveCapacity(size)

        var usedVertex = Array(repeating: false, count: vertexCount)
        var radEven = LocoBlobConstants.splitSpawnRadii[0]
        var radOdd = LocoBlobConstants.splitSpawnRadii[1]
        var vIdx = 0
        var attempts = 0

        while children.count < size && attempts < size * 8 {
            attempts += 1
            let idx = vIdx % vertexCount
            let factor = (idx % 2 == 0) ? radEven : radOdd
            if !usedVertex[idx] {
                let rayX = cur[idx].x - core.x
                let rayY = cur[idx].y - core.y
                let candidate = CGPoint(x: core.x + rayX * factor, y: core.y + rayY * factor)
                if isPointClear(candidate, childRadius * 0.65) || attempts > size * 4 {
                    usedVertex[idx] = true
                    let rLen = max(1.0, hypot(rayX, rayY))
                    let burst = CGVector(
                        dx: vel.dx + (rayX / rLen) * 0.45,
                        dy: vel.dy + (rayY / rLen) * 0.45 + 0.35
                    )
                    let child = LocoBlob(
                        id: nextId(),
                        center: candidate,
                        size: 1,
                        appearance: appearance,
                        initialVelocity: burst,
                        stiffnessMultiplier: stiffnessMultiplier
                    )
                    child.jumpExpressionTimer = 18
                    children.append(child)
                }
            }
            vIdx += 1
            if vIdx % vertexCount == 0 {
                usedVertex = Array(repeating: false, count: vertexCount)
                radEven = max(0.1, radEven - 0.2)
                radOdd = max(0.15, radOdd - 0.2)
            }
        }
        return children.isEmpty ? nil : children
    }

    // MARK: - Contour-Stitching Merge / Join

    public static func merge(_ a: LocoBlob, _ b: LocoBlob, newId: Int) -> LocoBlob {
        let (big, small) = a.size >= b.size ? (a, b) : (b, a)
        let totalSize = min(LocoBlobConstants.maxTotalSize, big.size + small.size)
        let nNew = LocoBlobConstants.vertexCount(forSize: totalSize)

        let areaRatio = big.area / (big.area + small.area)
        let countBig = max(4, min(nNew - 4, Int(CGFloat(nNew) * areaRatio)))
        let countSmall = nNew - countBig

        var poleBig = 0
        var poleSmall = 0
        var maxDistSq: CGFloat = -1
        for i in 0..<big.vertexCount {
            for j in 0..<small.vertexCount {
                let dx = big.cur[i].x - small.cur[j].x
                let dy = big.cur[i].y - small.cur[j].y
                let dSq = dx * dx + dy * dy
                if dSq > maxDistSq {
                    maxDistSq = dSq
                    poleBig = i
                    poleSmall = j
                }
            }
        }

        let stepsBig = max(1, (countBig * big.vertexCount) / nNew)
        let arcBig = expandOuterArc(ring: big.cur, startIndex: poleBig, steps: stepsBig, awayFrom: small.cur[poleSmall])

        let stepsSmall = max(1, (countSmall * small.vertexCount) / nNew)
        let arcSmall = expandOuterArc(ring: small.cur, startIndex: poleSmall, steps: stepsSmall, awayFrom: big.cur[poleBig])

        let velBig = big.averageVelocity()
        let velSmall = small.averageVelocity()
        let mergedVel = CGVector(
            dx: velBig.dx * areaRatio + velSmall.dx * (1.0 - areaRatio),
            dy: velBig.dy * areaRatio + velSmall.dy * (1.0 - areaRatio)
        )

        var stitched = resampleArc(arcBig, count: countBig) + resampleArc(arcSmall, count: countSmall)

        var cx: CGFloat = 0, cy: CGFloat = 0
        for p in stitched { cx += p.x; cy += p.y }
        cx /= CGFloat(nNew); cy /= CGFloat(nNew)

        var topIdx = 0
        var bestY = -CGFloat.greatestFiniteMagnitude
        for (i, p) in stitched.enumerated() {
            if p.y > bestY {
                bestY = p.y
                topIdx = i
            }
        }
        if topIdx != 0 {
            stitched = Array(stitched[topIdx...]) + Array(stitched[..<topIdx])
        }

        let merged = LocoBlob(
            id: newId,
            center: CGPoint(x: cx, y: cy),
            size: totalSize,
            appearance: big.appearance,
            initialVelocity: mergedVel,
            stiffnessMultiplier: big.stiffnessMultiplier
        )
        merged.cur = stitched
        merged.prev = stitched.map { CGPoint(x: $0.x - mergedVel.dx, y: $0.y - mergedVel.dy) }
        merged.core = CGPoint(x: cx, y: cy)
        merged.prevCore = CGPoint(x: cx - mergedVel.dx, y: cy - mergedVel.dy)
        merged.jumpExpressionTimer = 22
        return merged
    }

    private static func expandOuterArc(ring: [CGPoint], startIndex: Int, steps: Int, awayFrom target: CGPoint) -> [CGPoint] {
        let n = ring.count
        var ccw = startIndex
        var cw = startIndex
        let clampedSteps = min(steps, n - 1)
        for _ in 0..<clampedSteps {
            let nextCCW = (ccw - 1 + n) % n
            let nextCW = (cw + 1) % n
            if blobDistSq(ring[nextCCW], target) >= blobDistSq(ring[nextCW], target) {
                ccw = nextCCW
            } else {
                cw = nextCW
            }
        }
        var result: [CGPoint] = []
        var idx = ccw
        result.append(ring[idx])
        while idx != cw && result.count < n {
            idx = (idx + 1) % n
            result.append(ring[idx])
        }
        return result
    }

    private static func resampleArc(_ arc: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 0, !arc.isEmpty else { return [] }
        if arc.count == 1 { return Array(repeating: arc[0], count: count) }
        var out: [CGPoint] = []
        out.reserveCapacity(count)
        let last = CGFloat(arc.count - 1)
        for i in 0..<count {
            let t = count == 1 ? 0 : (CGFloat(i) / CGFloat(count - 1)) * last
            let i0 = min(arc.count - 1, Int(floor(t)))
            let i1 = min(arc.count - 1, i0 + 1)
            let frac = t - floor(t)
            out.append(CGPoint(
                x: arc[i0].x + (arc[i1].x - arc[i0].x) * frac,
                y: arc[i0].y + (arc[i1].y - arc[i0].y) * frac
            ))
        }
        return out
    }

    // MARK: - Smooth Spline & Face Helpers

    /// Returns smooth spline control points (`16` for sizes 1...13, `32` for sizes 14...20).
    public func renderControlPoints() -> [CGPoint] {
        let targetCount = max(vertexCount, 16)
        if targetCount == vertexCount { return cur }
        let radii = cur.map { hypot($0.x - core.x, $0.y - core.y) }
        var out: [CGPoint] = []
        out.reserveCapacity(targetCount)
        for k in 0..<targetCount {
            let f = CGFloat(k) * CGFloat(vertexCount) / CGFloat(targetCount)
            let i0 = Int(floor(f)) % vertexCount
            let i1 = (i0 + 1) % vertexCount
            let t = f - floor(f)
            let p = blobLerp(cur[i0], cur[i1], t)
            let dx = p.x - core.x
            let dy = p.y - core.y
            let d = max(1e-4, hypot(dx, dy))
            let targetR = radii[i0] + (radii[i1] - radii[i0]) * t
            out.append(CGPoint(x: core.x + (dx / d) * targetR, y: core.y + (dy / d) * targetR))
        }
        return out
    }

    /// Evaluates the closed periodic uniform cubic B-spline contour.
    public func evaluateClosedBSpline(subdivisionsPerSegment: Int = 4) -> [CGPoint] {
        let ctrl = renderControlPoints()
        let m = ctrl.count
        var result: [CGPoint] = []
        result.reserveCapacity(m * subdivisionsPerSegment)

        for i in 0..<m {
            let p0 = ctrl[(i - 1 + m) % m]
            let p1 = ctrl[i]
            let p2 = ctrl[(i + 1) % m]
            let p3 = ctrl[(i + 2) % m]
            for s in 0..<subdivisionsPerSegment {
                let u = CGFloat(s) / CGFloat(subdivisionsPerSegment)
                let u2 = u * u
                let u3 = u2 * u
                let b0 = (-u3 + 3 * u2 - 3 * u + 1) / 6.0
                let b1 = (3 * u3 - 6 * u2 + 4) / 6.0
                let b2 = (-3 * u3 + 3 * u2 + 3 * u + 1) / 6.0
                let b3 = u3 / 6.0
                result.append(CGPoint(
                    x: b0 * p0.x + b1 * p1.x + b2 * p2.x + b3 * p3.x,
                    y: b0 * p0.y + b1 * p1.y + b2 * p2.y + b3 * p3.y
                ))
            }
        }
        return result
    }

    /// Builds a closed `CGPath` of the blob body scaled by `scale` points per world unit.
    public func makeBodyCGPath(scale: CGFloat = LocoBlobConstants.defaultPointsPerWorldUnit, subdivisionsPerSegment: Int = 4) -> CGPath {
        let curve = evaluateClosedBSpline(subdivisionsPerSegment: subdivisionsPerSegment)
        let path = CGMutablePath()
        if let first = curve.first {
            path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
            for i in 1..<curve.count {
                path.addLine(to: CGPoint(x: curve[i].x * scale, y: curve[i].y * scale))
            }
            path.closeSubpath()
        }
        return path
    }

    /// Face rotation angle derived from north-pole vertex `P[0] - core`.
    public var faceRotationRadians: CGFloat {
        let dx = cur[0].x - core.x
        let dy = cur[0].y - core.y
        return atan2(-dx, dy)
    }

    /// Average velocity rotated into the face rig's local frame (`+Y` = towards the north pole).
    internal var faceLocalVelocity: CGVector {
        let vel = averageVelocity()
        let rot = faceRotationRadians
        let c = cos(-rot), s = sin(-rot)
        return CGVector(dx: vel.dx * c - vel.dy * s, dy: vel.dx * s + vel.dy * c)
    }

    /// Updates lagging face offset (`0.25` exponential lerp).
    public func updateFaceLag() {
        let vel = averageVelocity()
        let targetX = max(-radius * 0.22, min(radius * 0.22, -vel.dx * 1.1))
        let targetY = max(-radius * 0.22, min(radius * 0.22, -vel.dy * 1.1))
        smoothedFaceOffset.x += (targetX - smoothedFaceOffset.x) * LocoBlobConstants.faceLagLerp
        smoothedFaceOffset.y += (targetY - smoothedFaceOffset.y) * LocoBlobConstants.faceLagLerp
    }

    /// Effective expression (respecting `expressionOverride` when set).
    public var activeExpression: LocoBlobExpression {
        expressionOverride ?? expression
    }

    public func averageVelocity() -> CGVector {
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        for i in 0..<vertexCount {
            vx += cur[i].x - prev[i].x
            vy += cur[i].y - prev[i].y
        }
        let invN = 1.0 / CGFloat(vertexCount)
        return CGVector(dx: vx * invN, dy: vy * invN)
    }
}

@inline(__always)
private func blobLerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

@inline(__always)
private func blobDistSq(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return dx * dx + dy * dy
}
