import CoreGraphics
import Foundation

/// Soft-body physics tuning constants for `LocoBlob` and `LocoBlobWorld`.
public enum LocoBlobConstants {
    /// Fixed 60 Hz simulation timestep.
    public static let fixedDeltaTime: TimeInterval = 1.0 / 60.0

    /// Default pool and growth caps.
    public static let maxBlobCount: Int = 30
    public static let maxTotalSize: Int = 20

    // MARK: - Core Soft-Body Constants
    public static let damping: CGFloat = 0.975
    public static let gravityScale: CGFloat = 5.0
    public static let gravityBase: CGFloat = -0.0196
    /// Effective gravity magnitude in world units / frame² (`0.098`).
    public static let gravityMagnitude: CGFloat = abs(gravityBase) * gravityScale

    public static let baseStiffness: CGFloat = 0.43
    public static let radiusScale: CGFloat = 2.2938
    public static let restCircleBase: CGFloat = 4.0

    public static let jumpPower: CGFloat = 1.6289
    public static let jumpScale: CGFloat = 2.7278
    /// Maximum jump impulse in world units / frame (~`4.4433`).
    public static let maxJumpVelocity: CGFloat = jumpPower * jumpScale

    public static let blobCollisionStiffness: CGFloat = 0.6031
    public static let standardFriction: CGFloat = 0.6005
    public static let iceFriction: CGFloat = -0.055

    // MARK: - Complete-Graph Spring Formula
    public static let springNumerator: CGFloat = 16.0
    public static let springMinRestLength: CGFloat = 0.1
    public static let springMinStiffness: CGFloat = 1e-5
    public static let springMaxStiffness: CGFloat = 0.75

    // MARK: - Anti-Collapse / Anti-Inversion
    public static let minEdgeClearanceRatio: CGFloat = 0.6
    public static let maxVertexStretchRatio: CGFloat = 2.5

    // MARK: - Split / Join / Face Lag
    public static let splitCooldownFrames: Int = 17
    public static let splitSpawnRadii: [CGFloat] = [0.6, 0.8]
    public static let faceLagLerp: CGFloat = 0.25

    // MARK: - World Tilt & Jump Charge
    public static let maxWorldTiltRadians: CGFloat = 0.5235988  // ±30.0°
    public static let tiltRatePerFrame: CGFloat = 0.017453292   // 1.0°/frame
    public static let tiltHoldDelayFrames: Int = 60             // 1.0s hold on release
    public static let tiltReturnBaseRate: CGFloat = 0.001745329 // 0.1°/frame
    public static let tiltReturnAccelPerFrame: CGFloat = 0.1
    public static let jumpChargeRatePerFrame: CGFloat = 0.1     // full charge in 10 frames

    /// Default display scale: UI points per world unit.
    public static let defaultPointsPerWorldUnit: CGFloat = 5.2

    /// Quadratic jump strength curve: `(4 * c^2 + 3) / 7`.
    public static func jumpStrength(forCharge charge: CGFloat) -> CGFloat {
        let c = max(0, min(1, charge))
        return (4.0 * c * c + 3.0) / 7.0
    }

    /// Perimeter vertex count table (`8`, `16`, or `32`) for sizes `1...20`.
    public static func vertexCount(forSize size: Int) -> Int {
        let clamped = max(1, min(20, size))
        if clamped == 1 { return 8 }
        if clamped <= 13 { return 16 }
        return 32
    }

    /// Area-preserving rest radius: `R = 4.0 * radiusScale * sqrt(size / π)`.
    public static func radius(forSize size: Int) -> CGFloat {
        let area = CGFloat(max(1, size))
        return restCircleBase * radiusScale * sqrt(area / .pi)
    }
}
