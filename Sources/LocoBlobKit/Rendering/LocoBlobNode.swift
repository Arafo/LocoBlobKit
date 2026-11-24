#if canImport(SpriteKit)
import CoreGraphics
import SpriteKit

/// Ready-to-use SpriteKit `SKNode` renderer for any `LocoBlob`.
/// Drop this into any SpriteKit scene (`SKScene`) and call `sync(with:)` each frame.
public final class LocoBlobNode: SKNode {
    public let blobId: Int
    public var pointsPerWorldUnit: CGFloat

    private let bodyShape = SKShapeNode()
    private let rigContainer = SKNode()
    private let hairNode = SKShapeNode()
    private let faceLagGroup = SKNode()

    private let leftSclera = SKShapeNode()
    private let rightSclera = SKShapeNode()
    private let leftIris = SKShapeNode()
    private let rightIris = SKShapeNode()
    private let leftPupil = SKShapeNode()
    private let rightPupil = SKShapeNode()
    private let leftEyelid = SKShapeNode()
    private let rightEyelid = SKShapeNode()
    private let noseShape = SKShapeNode()
    private let mouthShape = SKShapeNode()
    private let mouthAccentShape = SKShapeNode()

    private let debugContainer = SKNode()
    private let debugSpringsShape = SKShapeNode()
    private let debugPointsShape = SKShapeNode()
    private let debugNorthPole = SKShapeNode()
    private let debugCoreCircle = SKShapeNode()

    private var visualState = LocoBlobVisualState()
    private var lastAppearance: LocoBlobAppearance

    private static let mouthBrown = LocoRGBAColor(r255: 112, g255: 48, b255: 22).platformColor
    private static let smileBrown = LocoRGBAColor(r255: 82, g255: 46, b255: 18).platformColor

    public init(blob: LocoBlob, pointsPerWorldUnit: CGFloat = LocoBlobConstants.defaultPointsPerWorldUnit) {
        self.blobId = blob.id
        self.pointsPerWorldUnit = pointsPerWorldUnit
        self.lastAppearance = blob.appearance
        super.init()

        bodyShape.strokeColor = .clear
        bodyShape.lineWidth = 0
        bodyShape.zPosition = 1
        addChild(bodyShape)

        rigContainer.zPosition = 2
        addChild(rigContainer)

        hairNode.strokeColor = .clear
        hairNode.lineWidth = 0
        hairNode.zPosition = 1
        rigContainer.addChild(hairNode)

        faceLagGroup.zPosition = 2
        rigContainer.addChild(faceLagGroup)

        for sclera in [leftSclera, rightSclera] {
            sclera.fillColor = .white
            sclera.strokeColor = .clear
            sclera.lineWidth = 0
            sclera.zPosition = 1
            faceLagGroup.addChild(sclera)
        }
        for iris in [leftIris, rightIris] {
            iris.strokeColor = .clear
            iris.zPosition = 2
            faceLagGroup.addChild(iris)
        }
        for pupil in [leftPupil, rightPupil] {
            pupil.strokeColor = .clear
            pupil.zPosition = 3
            faceLagGroup.addChild(pupil)
        }
        for lid in [leftEyelid, rightEyelid] {
            lid.strokeColor = .clear
            lid.zPosition = 4
            faceLagGroup.addChild(lid)
        }

        noseShape.strokeColor = .clear
        noseShape.zPosition = 3
        faceLagGroup.addChild(noseShape)

        mouthShape.lineCap = .round
        mouthShape.lineJoin = .round
        mouthShape.zPosition = 3
        faceLagGroup.addChild(mouthShape)

        mouthAccentShape.lineCap = .round
        mouthAccentShape.lineJoin = .round
        mouthAccentShape.zPosition = 4
        faceLagGroup.addChild(mouthAccentShape)

        debugContainer.zPosition = 10
        debugContainer.isHidden = true
        addChild(debugContainer)

        debugSpringsShape.lineWidth = 0.85
        debugSpringsShape.strokeColor = SKColor.white.withAlphaComponent(0.36)
        debugContainer.addChild(debugSpringsShape)

        debugCoreCircle.lineWidth = 1.3
        debugCoreCircle.fillColor = .clear
        debugCoreCircle.strokeColor = SKColor.cyan.withAlphaComponent(0.8)
        debugContainer.addChild(debugCoreCircle)

        debugPointsShape.lineWidth = 1.1
        debugPointsShape.strokeColor = .black
        debugPointsShape.fillColor = .white
        debugContainer.addChild(debugPointsShape)

        debugNorthPole.lineWidth = 1.4
        debugNorthPole.strokeColor = .black
        debugNorthPole.fillColor = .cyan
        debugContainer.addChild(debugNorthPole)

        applyAppearance(blob.appearance)
        sync(with: blob, showDebug: false)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func applyAppearance(_ appearance: LocoBlobAppearance) {
        lastAppearance = appearance
        let body = appearance.bodyColor.platformColor
        bodyShape.fillColor = body
        leftEyelid.fillColor = body
        rightEyelid.fillColor = body

        hairNode.isHidden = (appearance.hairStyle == .none)
        hairNode.fillColor = appearance.hairColor.platformColor

        faceLagGroup.isHidden = (appearance.faceStyle == .none)
        if let stroke = appearance.scleraStrokeColor {
            leftSclera.strokeColor = stroke.platformColor
            rightSclera.strokeColor = stroke.platformColor
            leftSclera.lineWidth = 1.1
            rightSclera.lineWidth = 1.1
        } else {
            leftSclera.strokeColor = .clear
            rightSclera.strokeColor = .clear
            leftSclera.lineWidth = 0
            rightSclera.lineWidth = 0
        }

        if let iris = appearance.irisColor {
            leftIris.isHidden = false
            rightIris.isHidden = false
            leftIris.fillColor = iris.platformColor
            rightIris.fillColor = iris.platformColor
        } else {
            leftIris.isHidden = true
            rightIris.isHidden = true
        }

        leftPupil.fillColor = appearance.pupilColor.platformColor
        rightPupil.fillColor = appearance.pupilColor.platformColor

        if let nose = appearance.noseColor {
            noseShape.isHidden = false
            noseShape.fillColor = nose.platformColor
        } else {
            noseShape.isHidden = true
        }

        rebuildStaticFeaturePaths(appearance: appearance)
    }

    public func sync(with blob: LocoBlob, showDebug: Bool = false) {
        if blob.appearance != lastAppearance {
            applyAppearance(blob.appearance)
        }

        let s = pointsPerWorldUnit
        bodyShape.path = blob.makeBodyCGPath(scale: s, subdivisionsPerSegment: 4)

        let p0 = blob.cur[0]
        let rot = blob.faceRotationRadians
        rigContainer.position = CGPoint(x: p0.x * s, y: p0.y * s)
        rigContainer.zRotation = rot

        let cosR = cos(-rot), sinR = sin(-rot)
        let localVel = blob.faceLocalVelocity
        let localVx = localVel.dx
        let localVy = localVel.dy

        visualState.step(localVelX: localVx)

        hairNode.position = .zero
        hairNode.zRotation = visualState.swayAngle
        let stretchY = max(0.86, min(1.22, 1.0 + localVy * 0.06))
        hairNode.xScale = 1.0 / sqrt(stretchY)
        hairNode.yScale = stretchY

        let localLagX = (blob.smoothedFaceOffset.x * cosR - blob.smoothedFaceOffset.y * sinR) * 0.40
        let localLagY = (blob.smoothedFaceOffset.x * sinR + blob.smoothedFaceOffset.y * cosR) * 0.40
        faceLagGroup.position = CGPoint(x: localLagX * s, y: localLagY * s)

        if blob.appearance.faceStyle != .none {
            updateDynamicFace(blob: blob, localVelX: localVx, localVelY: localVy)
        }

        debugContainer.isHidden = !showDebug
        if showDebug {
            updateDebugOverlay(blob: blob, scale: s)
        }
    }

    private func rebuildStaticFeaturePaths(appearance: LocoBlobAppearance) {
        let s = pointsPerWorldUnit
        let eyeX: CGFloat = 1.50 * s
        let eyeY: CGFloat = -3.00 * s

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

        let scleraPath = CGPath(ellipseIn: CGRect(x: -scleraR, y: -scleraR, width: scleraR * 2, height: scleraR * 2), transform: nil)
        leftSclera.path = scleraPath
        rightSclera.path = scleraPath
        leftSclera.position = CGPoint(x: -eyeX, y: eyeY)
        rightSclera.position = CGPoint(x: eyeX, y: eyeY)

        let irisR = 0.40 * s
        let irisPath = CGPath(ellipseIn: CGRect(x: -irisR, y: -irisR, width: irisR * 2, height: irisR * 2), transform: nil)
        leftIris.path = irisPath
        rightIris.path = irisPath

        let pupilPath = CGPath(ellipseIn: CGRect(x: -pupilR, y: -pupilR, width: pupilR * 2, height: pupilR * 2), transform: nil)
        leftPupil.path = pupilPath
        rightPupil.path = pupilPath

        let nose = CGMutablePath()
        if appearance.faceStyle == .budzi {
            nose.addEllipse(in: CGRect(x: -0.95 * s, y: -0.60 * s, width: 1.90 * s, height: 1.25 * s))
        } else {
            nose.move(to: CGPoint(x: 0, y: 0.72 * s))
            nose.addCurve(to: CGPoint(x: 0, y: -0.58 * s), control1: CGPoint(x: 0.80 * s, y: -0.05 * s), control2: CGPoint(x: 0.60 * s, y: -0.58 * s))
            nose.addCurve(to: CGPoint(x: 0, y: 0.72 * s), control1: CGPoint(x: -0.60 * s, y: -0.58 * s), control2: CGPoint(x: -0.80 * s, y: -0.05 * s))
            nose.closeSubpath()
        }
        noseShape.path = nose
        noseShape.position = CGPoint(x: 0, y: -4.35 * s)

        hairNode.path = LocoBlobRenderer.buildHairPath(style: appearance.hairStyle, scale: s)
    }

    private func updateDynamicFace(blob: LocoBlob, localVelX: CGFloat, localVelY: CGFloat) {
        let s = pointsPerWorldUnit
        let eyeX: CGFloat = 1.50 * s
        let eyeY: CGFloat = -3.00 * s
        let expr = blob.activeExpression

        let blinkAmount: CGFloat
        if expr == .squashed {
            blinkAmount = 0.72
        } else if expr == .scared || expr == .excited {
            blinkAmount = 0.0
        } else {
            blinkAmount = visualState.blinkPhase > 0 ? sin((CGFloat(visualState.blinkPhase) / 8.0) * .pi) : 0.0
        }

        let eyelidVisible = blinkAmount > 0.05
        leftEyelid.isHidden = !eyelidVisible
        rightEyelid.isHidden = !eyelidVisible
        if eyelidVisible {
            let lidR: CGFloat = 0.94 * s
            let h = lidR * 2.0 * blinkAmount
            let lidPath = CGPath(rect: CGRect(x: -lidR, y: lidR - h, width: lidR * 2, height: h), transform: nil)
            leftEyelid.path = lidPath
            rightEyelid.path = lidPath
            leftEyelid.position = CGPoint(x: -eyeX, y: eyeY)
            rightEyelid.position = CGPoint(x: eyeX, y: eyeY)
        }

        let eyeScale: CGFloat = (expr == .scared) ? 1.18 : (expr == .excited ? 1.12 : 1.0)
        leftSclera.setScale(eyeScale)
        rightSclera.setScale(eyeScale)

        let jitterX: CGFloat = (expr == .scared) ? CGFloat(((blob.ageFrames % 4) - 2)) * 0.06 * s : 0
        let lookX = max(-0.24, min(0.24, localVelX * 0.16)) * s + jitterX
        let lookY = max(-0.20, min(0.20, localVelY * 0.14)) * s
        leftPupil.position = CGPoint(x: -eyeX + lookX, y: eyeY + lookY)
        rightPupil.position = CGPoint(x: eyeX + lookX, y: eyeY + lookY)
        leftIris.position = leftPupil.position
        rightIris.position = rightPupil.position

        let mouthY: CGFloat = -5.75 * s
        let mp = CGMutablePath()
        let ap = CGMutablePath()
        mouthAccentShape.isHidden = true

        if expr == .scared {
            let pts: [(CGFloat, CGFloat)] = [(-2.0, -0.55), (-1.2, 0.10), (-0.4, -0.35), (0.4, 0.10), (1.2, -0.35), (2.0, -0.55)]
            mp.move(to: CGPoint(x: pts[0].0 * s, y: mouthY + pts[0].1 * s))
            for pt in pts.dropFirst() { mp.addLine(to: CGPoint(x: pt.0 * s, y: mouthY + pt.1 * s)) }
            mouthShape.fillColor = .clear
            mouthShape.strokeColor = Self.mouthBrown
            mouthShape.lineWidth = max(1.8, 0.28 * s)
        } else if expr == .singing {
            let pulse = 1.0 + sin(CGFloat(blob.ageFrames) * 0.42) * 0.24
            let mw = 1.65 * s * pulse, mh = 2.20 * s * (1.12 / pulse)
            mp.addEllipse(in: CGRect(x: -mw * 0.5, y: mouthY - mh * 0.5, width: mw, height: mh))
            mouthShape.fillColor = Self.mouthBrown
            mouthShape.strokeColor = .clear
            mouthShape.lineWidth = 0
        } else if expr == .excited {
            mp.move(to: CGPoint(x: -2.25 * s, y: mouthY + 0.55 * s))
            mp.addQuadCurve(to: CGPoint(x: 2.25 * s, y: mouthY + 0.55 * s), control: CGPoint(x: 0, y: mouthY + 0.15 * s))
            mp.addCurve(to: CGPoint(x: -2.25 * s, y: mouthY + 0.55 * s), control1: CGPoint(x: 1.4 * s, y: mouthY - 2.15 * s), control2: CGPoint(x: -1.4 * s, y: mouthY - 2.15 * s))
            mp.closeSubpath()
            mouthShape.fillColor = Self.mouthBrown
            mouthShape.strokeColor = .clear
            mouthShape.lineWidth = 0
        } else if blob.jumpExpressionTimer > 10 {
            let mw = 1.50 * s, mh = 2.25 * s
            mp.addEllipse(in: CGRect(x: -mw * 0.5, y: mouthY - mh * 0.5, width: mw, height: mh))
            mouthShape.fillColor = Self.mouthBrown
            mouthShape.strokeColor = .clear
            mouthShape.lineWidth = 0
        } else if blob.jumpExpressionTimer > 0 {
            mp.move(to: CGPoint(x: -1.95 * s, y: mouthY - 0.1 * s))
            mp.addCurve(to: CGPoint(x: 1.95 * s, y: mouthY - 0.1 * s), control1: CGPoint(x: -1.0 * s, y: mouthY + 1.55 * s), control2: CGPoint(x: 1.0 * s, y: mouthY + 1.55 * s))
            mp.addCurve(to: CGPoint(x: -1.95 * s, y: mouthY - 0.1 * s), control1: CGPoint(x: 0.8 * s, y: mouthY + 0.35 * s), control2: CGPoint(x: -0.8 * s, y: mouthY + 0.35 * s))
            mp.closeSubpath()
            mouthShape.fillColor = Self.mouthBrown
            mouthShape.strokeColor = .clear
            mouthShape.lineWidth = 0
        } else {
            switch blob.appearance.faceStyle {
            case .kulche, .none:
                mp.move(to: CGPoint(x: -2.20 * s, y: mouthY + 0.45 * s))
                mp.addQuadCurve(to: CGPoint(x: 2.20 * s, y: mouthY + 0.45 * s), control: CGPoint(x: 0, y: mouthY - 1.55 * s))
                mouthShape.fillColor = .clear
                mouthShape.strokeColor = Self.smileBrown
                mouthShape.lineWidth = max(1.6, 0.25 * s)

            case .pekerone:
                let pts: [(CGFloat, CGFloat)] = [(-3.1, -0.15), (-2.1, 0.22), (-1.1, -0.25), (0.0, 0.28), (1.1, -0.22), (2.1, 0.30), (3.1, -0.10)]
                mp.move(to: CGPoint(x: pts[0].0 * s, y: mouthY + pts[0].1 * s))
                for pt in pts.dropFirst() { mp.addLine(to: CGPoint(x: pt.0 * s, y: mouthY + pt.1 * s)) }
                mouthShape.fillColor = .clear
                mouthShape.strokeColor = LocoRGBAColor(r255: 46, g255: 20, b255: 14).platformColor
                mouthShape.lineWidth = max(1.8, 0.28 * s)

            case .priffy:
                mp.move(to: CGPoint(x: -2.25 * s, y: mouthY + 0.40 * s))
                mp.addCurve(to: CGPoint(x: 2.25 * s, y: mouthY + 0.40 * s), control1: CGPoint(x: -0.8 * s, y: mouthY - 0.55 * s), control2: CGPoint(x: 0.8 * s, y: mouthY - 0.55 * s))
                mp.addCurve(to: CGPoint(x: -2.25 * s, y: mouthY + 0.40 * s), control1: CGPoint(x: 1.2 * s, y: mouthY - 1.55 * s), control2: CGPoint(x: -1.2 * s, y: mouthY - 1.55 * s))
                mp.closeSubpath()
                mouthShape.fillColor = LocoRGBAColor(r255: 235, g255: 54, b255: 92).platformColor
                mouthShape.strokeColor = .clear
                mouthShape.lineWidth = 0

                ap.move(to: CGPoint(x: -1.95 * s, y: mouthY + 0.30 * s))
                ap.addQuadCurve(to: CGPoint(x: 1.95 * s, y: mouthY + 0.30 * s), control: CGPoint(x: 0, y: mouthY - 0.85 * s))
                mouthAccentShape.isHidden = false
                mouthAccentShape.path = ap
                mouthAccentShape.fillColor = .clear
                mouthAccentShape.strokeColor = LocoRGBAColor(r255: 138, g255: 24, b255: 46).platformColor
                mouthAccentShape.lineWidth = max(1.2, 0.18 * s)

            case .chavez:
                mp.move(to: CGPoint(x: -3.20 * s, y: mouthY + 0.45 * s))
                mp.addQuadCurve(to: CGPoint(x: 3.20 * s, y: mouthY + 0.45 * s), control: CGPoint(x: 0, y: mouthY - 1.55 * s))
                mouthShape.fillColor = .clear
                mouthShape.strokeColor = Self.smileBrown
                mouthShape.lineWidth = max(1.6, 0.25 * s)

            case .tupley:
                mp.move(to: CGPoint(x: -3.25 * s, y: mouthY + 0.55 * s))
                mp.addCurve(to: CGPoint(x: 3.25 * s, y: mouthY + 0.55 * s), control1: CGPoint(x: -1.2 * s, y: mouthY - 0.45 * s), control2: CGPoint(x: 1.2 * s, y: mouthY - 0.45 * s))
                mp.addCurve(to: CGPoint(x: -3.25 * s, y: mouthY + 0.55 * s), control1: CGPoint(x: 1.8 * s, y: mouthY - 2.15 * s), control2: CGPoint(x: -1.8 * s, y: mouthY - 2.15 * s))
                mp.closeSubpath()
                mouthShape.fillColor = LocoRGBAColor(r255: 238, g255: 118, b255: 124).platformColor
                mouthShape.strokeColor = .clear
                mouthShape.lineWidth = 0

                ap.move(to: CGPoint(x: -2.85 * s, y: mouthY + 0.40 * s))
                ap.addQuadCurve(to: CGPoint(x: 2.85 * s, y: mouthY + 0.40 * s), control: CGPoint(x: 0, y: mouthY - 1.05 * s))
                mouthAccentShape.isHidden = false
                mouthAccentShape.path = ap
                mouthAccentShape.fillColor = .clear
                mouthAccentShape.strokeColor = LocoRGBAColor(r255: 118, g255: 36, b255: 40).platformColor
                mouthAccentShape.lineWidth = max(1.3, 0.20 * s)

            case .budzi:
                let bar = CGRect(x: -2.85 * s, y: mouthY - 0.50 * s, width: 5.70 * s, height: 0.95 * s)
                mp.addRoundedRect(in: bar, cornerWidth: 0.45 * s, cornerHeight: 0.45 * s)
                mouthShape.fillColor = LocoRGBAColor(r255: 162, g255: 106, b255: 24).platformColor
                mouthShape.strokeColor = .clear
                mouthShape.lineWidth = 0

                for fx in [-2.05, 2.05] as [CGFloat] {
                    ap.move(to: CGPoint(x: (fx - 0.35) * s, y: mouthY + 0.05 * s))
                    ap.addLine(to: CGPoint(x: fx * s, y: mouthY + 0.72 * s))
                    ap.addLine(to: CGPoint(x: (fx + 0.35) * s, y: mouthY + 0.05 * s))
                    ap.closeSubpath()
                }
                mouthAccentShape.isHidden = false
                mouthAccentShape.path = ap
                mouthAccentShape.fillColor = .white
                mouthAccentShape.strokeColor = .clear
                mouthAccentShape.lineWidth = 0
            }
        }
        mouthShape.path = mp
    }

    private func updateDebugOverlay(blob: LocoBlob, scale s: CGFloat) {
        let springPath = CGMutablePath()
        for sp in blob.springs {
            let a = blob.cur[sp.idxA]
            let b = blob.cur[sp.idxB]
            springPath.move(to: CGPoint(x: a.x * s, y: a.y * s))
            springPath.addLine(to: CGPoint(x: b.x * s, y: b.y * s))
        }
        debugSpringsShape.path = springPath

        let ptsPath = CGMutablePath()
        let dotR: CGFloat = 2.6
        for i in 1..<blob.vertexCount {
            let p = blob.cur[i]
            ptsPath.addEllipse(in: CGRect(x: p.x * s - dotR, y: p.y * s - dotR, width: dotR * 2, height: dotR * 2))
        }
        debugPointsShape.path = ptsPath

        let p0 = blob.cur[0]
        let p0R: CGFloat = 4.0
        debugNorthPole.path = CGPath(ellipseIn: CGRect(x: p0.x * s - p0R, y: p0.y * s - p0R, width: p0R * 2, height: p0R * 2), transform: nil)

        let minR = LocoBlobConstants.minEdgeClearanceRatio * blob.radius * s
        debugCoreCircle.path = CGPath(ellipseIn: CGRect(x: blob.core.x * s - minR, y: blob.core.y * s - minR, width: minR * 2, height: minR * 2), transform: nil)
    }
}
#endif
