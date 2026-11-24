import CoreGraphics
import Foundation

/// Solid geometry that `LocoBlobWorld` resolves soft-body collisions against.
/// All coordinates are in LocoRoco world units (`+X` right, `+Y` up).
public struct LocoBlobObstacle: Identifiable, Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        /// Line segment with rounded endcaps (ramps, shelves, trampolines).
        case capsule(a: CGPoint, b: CGPoint, thickness: CGFloat)
        /// Circular bumper or button.
        case circle(center: CGPoint, radius: CGFloat)
        /// Axis-aligned rectangle (e.g., UI cards, buttons, blocks).
        case rect(CGRect)
    }

    public let id: String
    public var shape: Shape
    public var isBouncy: Bool
    public var bounceFactor: CGFloat
    public var friction: CGFloat?

    public init(
        id: String = UUID().uuidString,
        shape: Shape,
        isBouncy: Bool = false,
        bounceFactor: CGFloat = 1.0,
        friction: CGFloat? = nil
    ) {
        self.id = id
        self.shape = shape
        self.isBouncy = isBouncy
        self.bounceFactor = bounceFactor
        self.friction = friction
    }

    public static func capsule(
        id: String = UUID().uuidString,
        from a: CGPoint,
        to b: CGPoint,
        thickness: CGFloat = 2.0,
        isBouncy: Bool = false,
        bounceFactor: CGFloat = 1.0
    ) -> LocoBlobObstacle {
        LocoBlobObstacle(
            id: id,
            shape: .capsule(a: a, b: b, thickness: thickness),
            isBouncy: isBouncy,
            bounceFactor: bounceFactor
        )
    }

    public static func circle(
        id: String = UUID().uuidString,
        center: CGPoint,
        radius: CGFloat,
        isBouncy: Bool = false,
        bounceFactor: CGFloat = 1.0
    ) -> LocoBlobObstacle {
        LocoBlobObstacle(
            id: id,
            shape: .circle(center: center, radius: radius),
            isBouncy: isBouncy,
            bounceFactor: bounceFactor
        )
    }

    public static func rect(
        id: String = UUID().uuidString,
        _ rect: CGRect,
        isBouncy: Bool = false,
        bounceFactor: CGFloat = 1.0
    ) -> LocoBlobObstacle {
        LocoBlobObstacle(
            id: id,
            shape: .rect(rect),
            isBouncy: isBouncy,
            bounceFactor: bounceFactor
        )
    }
}
