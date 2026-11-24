import CoreGraphics
import Foundation

/// Per-blob transient visual state (blinking & hair sway) kept separate from pure physics.
public struct LocoBlobVisualState: Sendable {
    public var blinkTimer: Int
    public var blinkPhase: Int = 0
    public var swayAngle: CGFloat = 0

    public init(blinkTimer: Int = Int.random(in: 90...220)) {
        self.blinkTimer = blinkTimer
    }

    public mutating func step(localVelX: CGFloat) {
        let targetSway = max(-0.24, min(0.24, -localVelX * 0.12))
        swayAngle += (targetSway - swayAngle) * 0.22

        if blinkPhase > 0 {
            blinkPhase -= 1
        } else {
            blinkTimer -= 1
            if blinkTimer <= 0 {
                blinkPhase = 8
                blinkTimer = Int.random(in: 120...280)
            }
        }
    }
}

/// Pure CoreGraphics vector renderer for `LocoBlob`.
///
/// Works identically in SwiftUI `Canvas`, `CALayer`, `UIImage` / `NSImage` rendering, and offscreen bitmaps,
/// with crisp Retina anti-aliasing and true transparent backgrounds.
///
/// Expects a Y-up coordinate space (`+X` right, `+Y` up) matching LocoRoco world units × `scale`.
/// To render inside a standard Y-down UIKit / SwiftUI `Canvas`, apply:
/// ```swift
/// ctx.translateBy(x: 0, y: canvasSize.height)
/// ctx.scaleBy(x: 1, y: -1)
/// ```
public enum LocoBlobRenderer {
    private static let mouthBrown = LocoRGBAColor(r255: 112, g255: 48, b255: 22).cgColor
    private static let smileBrown = LocoRGBAColor(r255: 82, g255: 46, b255: 18).cgColor

    public static func draw(
        blob: LocoBlob,
        in ctx: CGContext,
        scale s: CGFloat = LocoBlobConstants.defaultPointsPerWorldUnit,
        visualState: LocoBlobVisualState = LocoBlobVisualState(blinkTimer: 180),
        showDebugMesh: Bool = false
    ) {
        let appearance = blob.appearance

        ctx.saveGState()

        // 1. Flat solid-color cubic B-spline body
        let bodyPath = blob.makeBodyCGPath(scale: s, subdivisionsPerSegment: 4)
        ctx.addPath(bodyPath)
        ctx.setFillColor(appearance.bodyColor.cgColor)
        ctx.fillPath()

        // 2. Anchor character rig at north-pole vertex `P[0]` rotated by `faceRotationRadians`
        let p0 = blob.cur[0]
        let rot = blob.faceRotationRadians
        let cosR = cos(-rot), sinR = sin(-rot)
        let localVel = blob.faceLocalVelocity
        let localVx = localVel.dx
        let localVy = localVel.dy

        ctx.saveGState()
        ctx.translateBy(x: p0.x * s, y: p0.y * s)
        ctx.rotate(by: rot)

        // 2a. Hair tuft fused into top edge
        if appearance.hairStyle != .none {
            ctx.saveGState()
            ctx.rotate(by: visualState.swayAngle)
            let stretchY = max(0.86, min(1.22, 1.0 + localVy * 0.06))
            ctx.scaleBy(x: 1.0 / sqrt(stretchY), y: stretchY)
            let hairPath = buildHairPath(style: appearance.hairStyle, scale: s)
            ctx.addPath(hairPath)
            ctx.setFillColor(appearance.hairColor.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 2b. Facial features with 0.25-lerped inertial lag
        if appearance.faceStyle != .none {
            let localLagX = (blob.smoothedFaceOffset.x * cosR - blob.smoothedFaceOffset.y * sinR) * 0.40
            let localLagY = (blob.smoothedFaceOffset.x * sinR + blob.smoothedFaceOffset.y * cosR) * 0.40
            ctx.saveGState()
            ctx.translateBy(x: localLagX * s, y: localLagY * s)
            drawFace(
                blob: blob,
                appearance: appearance,
                in: ctx,
                scale: s,
                localVelX: localVx,
                localVelY: localVy,
                blinkPhase: visualState.blinkPhase
            )
            ctx.restoreGState()
        }

        ctx.restoreGState()

        // 3. Optional debug physics mesh
        if showDebugMesh {
            drawDebugMesh(blob: blob, in: ctx, scale: s)
        }

        ctx.restoreGState()
    }

    // MARK: - Character Hair Silhouettes

    public static func buildHairPath(style: LocoHairStyle, scale s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        switch style {
        case .none:
            return p

        case .kulche:
            p.move(to: CGPoint(x: 0.05 * s, y: -1.10 * s))
            p.addCurve(to: CGPoint(x: -1.10 * s, y: 2.15 * s), control1: CGPoint(x: 0.15 * s, y: 0.45 * s), control2: CGPoint(x: 0.05 * s, y: 1.75 * s))
            p.addCurve(to: CGPoint(x: -3.73 * s, y: 2.25 * s), control1: CGPoint(x: -2.05 * s, y: 1.45 * s), control2: CGPoint(x: -3.73 * s, y: 1.35 * s))
            p.addCurve(to: CGPoint(x: 0.60 * s, y: 2.25 * s), control1: CGPoint(x: -3.73 * s, y: 3.65 * s), control2: CGPoint(x: -0.75 * s, y: 4.15 * s))
            p.addCurve(to: CGPoint(x: 4.21 * s, y: 2.70 * s), control1: CGPoint(x: 1.40 * s, y: 3.60 * s), control2: CGPoint(x: 4.15 * s, y: 4.10 * s))
            p.addCurve(to: CGPoint(x: 1.15 * s, y: 0.65 * s), control1: CGPoint(x: 4.25 * s, y: 1.40 * s), control2: CGPoint(x: 2.15 * s, y: 1.60 * s))
            p.addCurve(to: CGPoint(x: 0.72 * s, y: -1.10 * s), control1: CGPoint(x: 0.85 * s, y: 0.15 * s), control2: CGPoint(x: 0.75 * s, y: -0.45 * s))
            p.closeSubpath()

        case .pekerone:
            let angles: [CGFloat] = [-0.88, -0.44, 0.0, 0.44, 0.88]
            for a in angles {
                let len: CGFloat = (abs(a) < 0.1 ? 3.8 : (abs(a) < 0.6 ? 3.55 : 3.0)) * s
                let w: CGFloat = 0.58 * s
                let ca = cos(a), sa = sin(a)
                p.move(to: CGPoint(x: 0, y: -0.5 * s))
                p.addLine(to: CGPoint(x: sa * len - ca * w, y: ca * len + sa * w))
                p.addLine(to: CGPoint(x: sa * len + ca * w, y: ca * len - sa * w))
                p.closeSubpath()
            }

        case .priffy:
            p.move(to: CGPoint(x: -0.65 * s, y: -0.9 * s))
            p.addCurve(to: CGPoint(x: -3.95 * s, y: 1.25 * s), control1: CGPoint(x: -0.85 * s, y: 0.95 * s), control2: CGPoint(x: -2.55 * s, y: 2.05 * s))
            p.addLine(to: CGPoint(x: -4.25 * s, y: 2.55 * s))
            p.addCurve(to: CGPoint(x: 0.0, y: 1.55 * s), control1: CGPoint(x: -3.05 * s, y: 3.85 * s), control2: CGPoint(x: -0.95 * s, y: 3.05 * s))
            p.addCurve(to: CGPoint(x: 4.25 * s, y: 2.55 * s), control1: CGPoint(x: 0.95 * s, y: 3.05 * s), control2: CGPoint(x: 3.05 * s, y: 3.85 * s))
            p.addLine(to: CGPoint(x: 3.95 * s, y: 1.25 * s))
            p.addCurve(to: CGPoint(x: 0.65 * s, y: -0.9 * s), control1: CGPoint(x: 2.55 * s, y: 2.05 * s), control2: CGPoint(x: 0.85 * s, y: 0.95 * s))
            p.closeSubpath()

        case .chavez:
            let blades: [(CGFloat, CGFloat, CGFloat)] = [
                (-3.8, 3.1, -1.1), (-2.1, 4.4, -0.6), (0.2, 4.9, 0.0), (2.4, 4.4, 0.6), (3.9, 3.0, 1.1)
            ]
            for (tx, ty, bx) in blades {
                p.move(to: CGPoint(x: (bx - 0.65) * s, y: -0.7 * s))
                p.addQuadCurve(to: CGPoint(x: tx * s, y: ty * s), control: CGPoint(x: (bx * 0.8) * s, y: (ty * 0.65) * s))
                p.addQuadCurve(to: CGPoint(x: (bx + 0.65) * s, y: -0.7 * s), control: CGPoint(x: (bx + tx) * 0.45 * s, y: (ty * 0.45) * s))
                p.closeSubpath()
            }

        case .tupley:
            let petals: [(CGFloat, CGFloat, CGFloat)] = [(-0.82, 3.55, 1.15), (0.0, 4.15, 1.22), (0.82, 3.55, 1.15)]
            for (ang, len, wid) in petals {
                let ca = cos(ang), sa = sin(ang)
                let tipX = sa * len * s
                let tipY = ca * len * s
                p.move(to: CGPoint(x: 0, y: -0.8 * s))
                p.addCurve(
                    to: CGPoint(x: tipX, y: tipY),
                    control1: CGPoint(x: (sa * len * 0.35 - ca * wid) * s, y: (ca * len * 0.35 + sa * wid) * s),
                    control2: CGPoint(x: (sa * len * 0.95 - ca * wid * 0.8) * s, y: (ca * len * 0.95 + sa * wid * 0.8) * s)
                )
                p.addCurve(
                    to: CGPoint(x: 0, y: -0.8 * s),
                    control1: CGPoint(x: (sa * len * 0.95 + ca * wid * 0.8) * s, y: (ca * len * 0.95 - sa * wid * 0.8) * s),
                    control2: CGPoint(x: (sa * len * 0.35 + ca * wid) * s, y: (ca * len * 0.35 - sa * wid) * s)
                )
                p.closeSubpath()
            }

        case .budzi:
            p.move(to: CGPoint(x: -2.7 * s, y: -0.8 * s))
            p.addLine(to: CGPoint(x: -3.8 * s, y: 2.55 * s))
            p.addLine(to: CGPoint(x: -1.7 * s, y: 1.35 * s))
            p.addLine(to: CGPoint(x: -1.85 * s, y: 3.65 * s))
            p.addLine(to: CGPoint(x: -0.3 * s, y: 1.75 * s))
            p.addLine(to: CGPoint(x: 0.55 * s, y: 3.95 * s))
            p.addLine(to: CGPoint(x: 1.5 * s, y: 1.75 * s))
            p.addLine(to: CGPoint(x: 3.6 * s, y: 2.85 * s))
            p.addLine(to: CGPoint(x: 2.6 * s, y: -0.8 * s))
            p.closeSubpath()
        }
        return p
    }

    // MARK: - Eyes, Eyelids, Nose & Mouths

    private static func drawFace(
        blob: LocoBlob,
        appearance: LocoBlobAppearance,
        in ctx: CGContext,
        scale s: CGFloat,
        localVelX: CGFloat,
        localVelY: CGFloat,
        blinkPhase: Int
    ) {
        let eyeX: CGFloat = 1.50 * s
        let eyeY: CGFloat = -3.00 * s
        let expr = blob.activeExpression

        let scleraR: CGFloat
        let pupilR: CGFloat
        switch appearance.faceStyle {
        case .pekerone: scleraR = 0.88 * s; pupilR = 0.34 * s
        case .tupley:   scleraR = 0.68 * s; pupilR = 0.30 * s
        case .priffy:   scleraR = 0.76 * s; pupilR = 0.46 * s
        case .chavez:   scleraR = 0.78 * s; pupilR = 0.30 * s
        case .budzi:    scleraR = 0.78 * s; pupilR = 0.36 * s
        case .kulche, .none: scleraR = 0.76 * s; pupilR = 0.485 * s
        }

        let eyeScale: CGFloat = (expr == .scared) ? 1.18 : (expr == .excited ? 1.12 : 1.0)
        let scaledScleraR = scleraR * eyeScale

        // Gaze offset
        let jitterX: CGFloat = (expr == .scared) ? CGFloat(((blob.ageFrames % 4) - 2)) * 0.06 * s : 0
        let lookX = max(-0.24, min(0.24, localVelX * 0.16)) * s + jitterX
        let lookY = max(-0.20, min(0.20, localVelY * 0.14)) * s

        // Blink amount
        let blinkAmount: CGFloat
        if expr == .squashed {
            blinkAmount = 0.72
        } else if expr == .scared || expr == .excited {
            blinkAmount = 0.0
        } else {
            blinkAmount = blinkPhase > 0 ? sin((CGFloat(blinkPhase) / 8.0) * .pi) : 0.0
        }

        for sign in [-1.0, 1.0] as [CGFloat] {
            let ex = sign * eyeX
            let scleraRect = CGRect(x: ex - scaledScleraR, y: eyeY - scaledScleraR, width: scaledScleraR * 2, height: scaledScleraR * 2)
            ctx.setFillColor(LocoRGBAColor.white.cgColor)
            ctx.fillEllipse(in: scleraRect)
            if let stroke = appearance.scleraStrokeColor {
                ctx.setStrokeColor(stroke.cgColor)
                ctx.setLineWidth(1.1)
                ctx.strokeEllipse(in: scleraRect)
            }

            let px = ex + lookX
            let py = eyeY + lookY
            if let iris = appearance.irisColor {
                let irisR = 0.40 * s
                ctx.setFillColor(iris.cgColor)
                ctx.fillEllipse(in: CGRect(x: px - irisR, y: py - irisR, width: irisR * 2, height: irisR * 2))
            }

            ctx.setFillColor(appearance.pupilColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: px - pupilR, y: py - pupilR, width: pupilR * 2, height: pupilR * 2))

            if blinkAmount > 0.05 {
                let lidR: CGFloat = 0.94 * s * eyeScale
                let h = lidR * 2.0 * blinkAmount
                ctx.setFillColor(appearance.bodyColor.cgColor)
                ctx.fill(CGRect(x: ex - lidR, y: eyeY + lidR - h, width: lidR * 2, height: h))
            }
        }

        // Nose (Chavez / Budzi)
        if let noseColor = appearance.noseColor {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: -4.35 * s)
            ctx.setFillColor(noseColor.cgColor)
            if appearance.faceStyle == .budzi {
                ctx.fillEllipse(in: CGRect(x: -0.95 * s, y: -0.60 * s, width: 1.90 * s, height: 1.25 * s))
            } else {
                let nose = CGMutablePath()
                nose.move(to: CGPoint(x: 0, y: 0.72 * s))
                nose.addCurve(to: CGPoint(x: 0, y: -0.58 * s), control1: CGPoint(x: 0.80 * s, y: -0.05 * s), control2: CGPoint(x: 0.60 * s, y: -0.58 * s))
                nose.addCurve(to: CGPoint(x: 0, y: 0.72 * s), control1: CGPoint(x: -0.60 * s, y: -0.58 * s), control2: CGPoint(x: -0.80 * s, y: -0.05 * s))
                nose.closeSubpath()
                ctx.addPath(nose)
                ctx.fillPath()
            }
            ctx.restoreGState()
        }

        // Mouth
        drawMouth(blob: blob, style: appearance.faceStyle, expr: expr, in: ctx, scale: s)
    }

    private static func drawMouth(
        blob: LocoBlob,
        style: LocoFaceStyle,
        expr: LocoBlobExpression,
        in ctx: CGContext,
        scale s: CGFloat
    ) {
        let mouthY: CGFloat = -5.75 * s
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if expr == .scared {
            let pts: [(CGFloat, CGFloat)] = [(-2.0, -0.55), (-1.2, 0.10), (-0.4, -0.35), (0.4, 0.10), (1.2, -0.35), (2.0, -0.55)]
            ctx.beginPath()
            ctx.move(to: CGPoint(x: pts[0].0 * s, y: mouthY + pts[0].1 * s))
            for pt in pts.dropFirst() { ctx.addLine(to: CGPoint(x: pt.0 * s, y: mouthY + pt.1 * s)) }
            ctx.setStrokeColor(mouthBrown)
            ctx.setLineWidth(max(1.8, 0.28 * s))
            ctx.strokePath()
        } else if expr == .singing {
            let pulse = 1.0 + sin(CGFloat(blob.ageFrames) * 0.42) * 0.24
            let mw = 1.65 * s * pulse
            let mh = 2.20 * s * (1.12 / pulse)
            ctx.setFillColor(mouthBrown)
            ctx.fillEllipse(in: CGRect(x: -mw * 0.5, y: mouthY - mh * 0.5, width: mw, height: mh))
        } else if expr == .excited {
            let mp = CGMutablePath()
            mp.move(to: CGPoint(x: -2.25 * s, y: mouthY + 0.55 * s))
            mp.addQuadCurve(to: CGPoint(x: 2.25 * s, y: mouthY + 0.55 * s), control: CGPoint(x: 0, y: mouthY + 0.15 * s))
            mp.addCurve(to: CGPoint(x: -2.25 * s, y: mouthY + 0.55 * s), control1: CGPoint(x: 1.4 * s, y: mouthY - 2.15 * s), control2: CGPoint(x: -1.4 * s, y: mouthY - 2.15 * s))
            mp.closeSubpath()
            ctx.addPath(mp)
            ctx.setFillColor(mouthBrown)
            ctx.fillPath()
        } else if blob.jumpExpressionTimer > 10 {
            let mw = 1.50 * s, mh = 2.25 * s
            ctx.setFillColor(mouthBrown)
            ctx.fillEllipse(in: CGRect(x: -mw * 0.5, y: mouthY - mh * 0.5, width: mw, height: mh))
        } else if blob.jumpExpressionTimer > 0 {
            let mp = CGMutablePath()
            mp.move(to: CGPoint(x: -1.95 * s, y: mouthY - 0.1 * s))
            mp.addCurve(to: CGPoint(x: 1.95 * s, y: mouthY - 0.1 * s), control1: CGPoint(x: -1.0 * s, y: mouthY + 1.55 * s), control2: CGPoint(x: 1.0 * s, y: mouthY + 1.55 * s))
            mp.addCurve(to: CGPoint(x: -1.95 * s, y: mouthY - 0.1 * s), control1: CGPoint(x: 0.8 * s, y: mouthY + 0.35 * s), control2: CGPoint(x: -0.8 * s, y: mouthY + 0.35 * s))
            mp.closeSubpath()
            ctx.addPath(mp)
            ctx.setFillColor(mouthBrown)
            ctx.fillPath()
        } else {
            switch style {
            case .kulche, .none:
                ctx.beginPath()
                ctx.move(to: CGPoint(x: -2.20 * s, y: mouthY + 0.45 * s))
                ctx.addQuadCurve(to: CGPoint(x: 2.20 * s, y: mouthY + 0.45 * s), control: CGPoint(x: 0, y: mouthY - 1.55 * s))
                ctx.setStrokeColor(smileBrown)
                ctx.setLineWidth(max(1.6, 0.25 * s))
                ctx.strokePath()

            case .pekerone:
                let pts: [(CGFloat, CGFloat)] = [(-3.1, -0.15), (-2.1, 0.22), (-1.1, -0.25), (0.0, 0.28), (1.1, -0.22), (2.1, 0.30), (3.1, -0.10)]
                ctx.beginPath()
                ctx.move(to: CGPoint(x: pts[0].0 * s, y: mouthY + pts[0].1 * s))
                for pt in pts.dropFirst() { ctx.addLine(to: CGPoint(x: pt.0 * s, y: mouthY + pt.1 * s)) }
                ctx.setStrokeColor(LocoRGBAColor(r255: 46, g255: 20, b255: 14).cgColor)
                ctx.setLineWidth(max(1.8, 0.28 * s))
                ctx.strokePath()

            case .priffy:
                let mp = CGMutablePath()
                mp.move(to: CGPoint(x: -2.25 * s, y: mouthY + 0.40 * s))
                mp.addCurve(to: CGPoint(x: 2.25 * s, y: mouthY + 0.40 * s), control1: CGPoint(x: -0.8 * s, y: mouthY - 0.55 * s), control2: CGPoint(x: 0.8 * s, y: mouthY - 0.55 * s))
                mp.addCurve(to: CGPoint(x: -2.25 * s, y: mouthY + 0.40 * s), control1: CGPoint(x: 1.2 * s, y: mouthY - 1.55 * s), control2: CGPoint(x: -1.2 * s, y: mouthY - 1.55 * s))
                mp.closeSubpath()
                ctx.addPath(mp)
                ctx.setFillColor(LocoRGBAColor(r255: 235, g255: 54, b255: 92).cgColor)
                ctx.fillPath()

                ctx.beginPath()
                ctx.move(to: CGPoint(x: -1.95 * s, y: mouthY + 0.30 * s))
                ctx.addQuadCurve(to: CGPoint(x: 1.95 * s, y: mouthY + 0.30 * s), control: CGPoint(x: 0, y: mouthY - 0.85 * s))
                ctx.setStrokeColor(LocoRGBAColor(r255: 138, g255: 24, b255: 46).cgColor)
                ctx.setLineWidth(max(1.2, 0.18 * s))
                ctx.strokePath()

            case .chavez:
                ctx.beginPath()
                ctx.move(to: CGPoint(x: -3.20 * s, y: mouthY + 0.45 * s))
                ctx.addQuadCurve(to: CGPoint(x: 3.20 * s, y: mouthY + 0.45 * s), control: CGPoint(x: 0, y: mouthY - 1.55 * s))
                ctx.setStrokeColor(smileBrown)
                ctx.setLineWidth(max(1.6, 0.25 * s))
                ctx.strokePath()

            case .tupley:
                let mp = CGMutablePath()
                mp.move(to: CGPoint(x: -3.25 * s, y: mouthY + 0.55 * s))
                mp.addCurve(to: CGPoint(x: 3.25 * s, y: mouthY + 0.55 * s), control1: CGPoint(x: -1.2 * s, y: mouthY - 0.45 * s), control2: CGPoint(x: 1.2 * s, y: mouthY - 0.45 * s))
                mp.addCurve(to: CGPoint(x: -3.25 * s, y: mouthY + 0.55 * s), control1: CGPoint(x: 1.8 * s, y: mouthY - 2.15 * s), control2: CGPoint(x: -1.8 * s, y: mouthY - 2.15 * s))
                mp.closeSubpath()
                ctx.addPath(mp)
                ctx.setFillColor(LocoRGBAColor(r255: 238, g255: 118, b255: 124).cgColor)
                ctx.fillPath()

                ctx.beginPath()
                ctx.move(to: CGPoint(x: -2.85 * s, y: mouthY + 0.40 * s))
                ctx.addQuadCurve(to: CGPoint(x: 2.85 * s, y: mouthY + 0.40 * s), control: CGPoint(x: 0, y: mouthY - 1.05 * s))
                ctx.setStrokeColor(LocoRGBAColor(r255: 118, g255: 36, b255: 40).cgColor)
                ctx.setLineWidth(max(1.3, 0.20 * s))
                ctx.strokePath()

            case .budzi:
                let bar = CGPath(roundedRect: CGRect(x: -2.85 * s, y: mouthY - 0.50 * s, width: 5.70 * s, height: 0.95 * s), cornerWidth: 0.45 * s, cornerHeight: 0.45 * s, transform: nil)
                ctx.addPath(bar)
                ctx.setFillColor(LocoRGBAColor(r255: 162, g255: 106, b255: 24).cgColor)
                ctx.fillPath()

                let fangs = CGMutablePath()
                for fx in [-2.05, 2.05] as [CGFloat] {
                    fangs.move(to: CGPoint(x: (fx - 0.35) * s, y: mouthY + 0.05 * s))
                    fangs.addLine(to: CGPoint(x: fx * s, y: mouthY + 0.72 * s))
                    fangs.addLine(to: CGPoint(x: (fx + 0.35) * s, y: mouthY + 0.05 * s))
                    fangs.closeSubpath()
                }
                ctx.addPath(fangs)
                ctx.setFillColor(LocoRGBAColor.white.cgColor)
                ctx.fillPath()
            }
        }
    }

    private static func drawDebugMesh(blob: LocoBlob, in ctx: CGContext, scale s: CGFloat) {
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.38))
        ctx.setLineWidth(0.85)
        ctx.beginPath()
        for sp in blob.springs {
            let a = blob.cur[sp.idxA]
            let b = blob.cur[sp.idxB]
            ctx.move(to: CGPoint(x: a.x * s, y: a.y * s))
            ctx.addLine(to: CGPoint(x: b.x * s, y: b.y * s))
        }
        ctx.strokePath()

        let minR = LocoBlobConstants.minEdgeClearanceRatio * blob.radius * s
        ctx.setStrokeColor(CGColor(red: 0, green: 1, blue: 1, alpha: 0.8))
        ctx.setLineWidth(1.2)
        ctx.strokeEllipse(in: CGRect(x: blob.core.x * s - minR, y: blob.core.y * s - minR, width: minR * 2, height: minR * 2))

        for i in 0..<blob.vertexCount {
            let p = blob.cur[i]
            let r: CGFloat = (i == 0) ? 4.0 : 2.6
            let rect = CGRect(x: p.x * s - r, y: p.y * s - r, width: r * 2, height: r * 2)
            ctx.setFillColor(i == 0 ? CGColor(red: 0, green: 1, blue: 1, alpha: 1) : LocoRGBAColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(LocoRGBAColor.black.cgColor)
            ctx.setLineWidth(1.0)
            ctx.strokeEllipse(in: rect)
        }
    }
}
