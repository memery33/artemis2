import SwiftUI

/// Cream, gold, and ink from the hybrid stills.
enum HybridColor {
    static let cream = Color(red: 0.969, green: 0.953, blue: 0.918)
    static let gold = Color(red: 0.902, green: 0.769, blue: 0.541)
    static let dim = Color(red: 0.788, green: 0.761, blue: 0.706)
    static let ink = Color(red: 0.078, green: 0.071, blue: 0.063)
    static let ground = Color(red: 0.027, green: 0.024, blue: 0.020)
}

/// Fraunces for display, Inter for text. Sizes are the default Dynamic Type size;
/// `relativeTo` scales them with the system setting.
enum HybridFont {
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle, italic: Bool = false) -> Font {
        let font = Font.custom("Fraunces", size: size, relativeTo: style)
        return italic ? font.italic() : font
    }

    static func text(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        Font.custom("Inter", size: size, relativeTo: style)
    }
}
