import CoreGraphics
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Platform-independent RGBA color (0...1) used across physics, CoreGraphics, SpriteKit, and SwiftUI.
public struct LocoRGBAColor: Equatable, Hashable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(r255: Int, g255: Int, b255: Int, alpha: CGFloat = 1.0) {
        self.red = CGFloat(r255) / 255.0
        self.green = CGFloat(g255) / 255.0
        self.blue = CGFloat(b255) / 255.0
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }

    #if canImport(UIKit)
    public var platformColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    #elseif canImport(AppKit)
    public var platformColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    #endif

    public static let white = LocoRGBAColor(red: 1, green: 1, blue: 1)
    public static let black = LocoRGBAColor(red: 0, green: 0, blue: 0)
    public static let clear = LocoRGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
}

/// Hair tuft silhouette anchored at the blob's north pole (`P[0]`).
public enum LocoHairStyle: String, CaseIterable, Equatable, Hashable, Sendable {
    case kulche     // Twin plump sprout lobes (yellow)
    case pekerone   // 5-petal fan crest (red)
    case priffy     // Twin sweeping ribbon wings (pink)
    case chavez     // 5-blade spiky grass tuft (green)
    case tupley     // 3-petal clover sprout (blue)
    case budzi      // 5-point spiky crown (black)
    case none       // Smooth bald squishy blob
}

/// Facial feature preset for character styles (or `.none` for a faceless blob).
public enum LocoFaceStyle: String, CaseIterable, Equatable, Hashable, Sendable {
    case kulche
    case pekerone
    case priffy
    case chavez
    case tupley
    case budzi
    case none
}

/// Complete visual styling for any LocoRoco blob — use one of the 6 classic characters or build your own!
public struct LocoBlobAppearance: Equatable, Hashable, Sendable {
    public var name: String
    public var bodyColor: LocoRGBAColor
    public var hairStyle: LocoHairStyle
    public var hairColor: LocoRGBAColor
    public var faceStyle: LocoFaceStyle
    public var scleraStrokeColor: LocoRGBAColor?
    public var irisColor: LocoRGBAColor?
    public var pupilColor: LocoRGBAColor
    public var noseColor: LocoRGBAColor?

    public init(
        name: String = "Custom",
        bodyColor: LocoRGBAColor,
        hairStyle: LocoHairStyle = .kulche,
        hairColor: LocoRGBAColor? = nil,
        faceStyle: LocoFaceStyle = .kulche,
        scleraStrokeColor: LocoRGBAColor? = nil,
        irisColor: LocoRGBAColor? = nil,
        pupilColor: LocoRGBAColor = LocoRGBAColor(r255: 75, g255: 48, b255: 20),
        noseColor: LocoRGBAColor? = nil
    ) {
        self.name = name
        self.bodyColor = bodyColor
        self.hairStyle = hairStyle
        self.hairColor = hairColor ?? bodyColor
        self.faceStyle = faceStyle
        self.scleraStrokeColor = scleraStrokeColor
        self.irisColor = irisColor
        self.pupilColor = pupilColor
        self.noseColor = noseColor
    }

    // MARK: - Classic Character Presets

    /// Yellow — Kulche (classic cheerful smile & twin-lobe tuft).
    public static let kulche = LocoBlobAppearance(
        name: "Kulche",
        bodyColor: LocoRGBAColor(r255: 247, g255: 186, b255: 29),
        hairStyle: .kulche,
        faceStyle: .kulche,
        pupilColor: LocoRGBAColor(r255: 75, g255: 48, b255: 20)
    )

    /// Red — Pekerone (energetic zig-zag mouth & dark brown fan crest).
    public static let pekerone = LocoBlobAppearance(
        name: "Pekerone",
        bodyColor: LocoRGBAColor(r255: 237, g255: 0, b255: 0),
        hairStyle: .pekerone,
        hairColor: LocoRGBAColor(r255: 69, g255: 40, b255: 32),
        faceStyle: .pekerone,
        scleraStrokeColor: LocoRGBAColor(r255: 58, g255: 36, b255: 20),
        pupilColor: LocoRGBAColor(r255: 58, g255: 26, b255: 18)
    )

    /// Pink — Priffy (rosy lips, violet pupils & twin ribbon wings).
    public static let priffy = LocoBlobAppearance(
        name: "Priffy",
        bodyColor: LocoRGBAColor(r255: 247, g255: 119, b255: 186),
        hairStyle: .priffy,
        faceStyle: .priffy,
        pupilColor: LocoRGBAColor(r255: 97, g255: 91, b255: 158)
    )

    /// Green — Chavez (wide smile, teardrop nose, iris ring & crimson grass crest).
    public static let chavez = LocoBlobAppearance(
        name: "Chavez",
        bodyColor: LocoRGBAColor(r255: 98, g255: 146, b255: 44),
        hairStyle: .chavez,
        hairColor: LocoRGBAColor(r255: 130, g255: 20, b255: 6),
        faceStyle: .chavez,
        irisColor: LocoRGBAColor(r255: 112, g255: 108, b255: 86),
        pupilColor: .black,
        noseColor: LocoRGBAColor(r255: 98, g255: 40, b255: 8)
    )

    /// Blue — Tupley (chubby coral lips & 3-petal clover sprout).
    public static let tupley = LocoBlobAppearance(
        name: "Tupley",
        bodyColor: LocoRGBAColor(r255: 2, g255: 116, b255: 193),
        hairStyle: .tupley,
        faceStyle: .tupley,
        pupilColor: LocoRGBAColor(r255: 56, g255: 36, b255: 22)
    )

    /// Black — Budzi (spiky crown, teal pupils, snout & tiny white underbite fangs).
    public static let budzi = LocoBlobAppearance(
        name: "Budzi",
        bodyColor: LocoRGBAColor(r255: 28, g255: 28, b255: 32),
        hairStyle: .budzi,
        faceStyle: .budzi,
        pupilColor: LocoRGBAColor(r255: 13, g255: 91, b255: 76),
        noseColor: LocoRGBAColor(r255: 158, g255: 102, b255: 22)
    )

    /// All 6 classic LocoRoco characters.
    public static let classicCast: [LocoBlobAppearance] = [
        .kulche, .pekerone, .priffy, .chavez, .tupley, .budzi
    ]

    /// Convenience factory for a custom-colored blob with optional face & hair.
    public static func custom(
        color: LocoRGBAColor,
        hair: LocoHairStyle = .kulche,
        face: LocoFaceStyle = .kulche
    ) -> LocoBlobAppearance {
        LocoBlobAppearance(
            name: "Custom",
            bodyColor: color,
            hairStyle: hair,
            hairColor: color,
            faceStyle: face
        )
    }
}

/// Live facial expression state driven by physics or caller code.
public enum LocoBlobExpression: String, CaseIterable, Equatable, Hashable, Sendable {
    case neutral
    case jumping
    case singing
    case scared
    case excited
    case squashed
}
