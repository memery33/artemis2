import SwiftUI

/// Cream, gold, and ink from the hybrid stills.
enum HybridColor {
    static let creamComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) = (red: 0.969, green: 0.953, blue: 0.918)
    static let goldComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) = (red: 0.902, green: 0.769, blue: 0.541)
    static let dimComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) = (red: 0.788, green: 0.761, blue: 0.706)
    static let cream = Color(red: Double(creamComponents.red), green: Double(creamComponents.green), blue: Double(creamComponents.blue))
    static let gold = Color(red: Double(goldComponents.red), green: Double(goldComponents.green), blue: Double(goldComponents.blue))
    static let dim = Color(red: Double(dimComponents.red), green: Double(dimComponents.green), blue: Double(dimComponents.blue))
    static let ink = Color(red: 0.078, green: 0.071, blue: 0.063)
    static let ground = Color(red: 0.027, green: 0.024, blue: 0.020)
}

/// Secondary type has to clear 4.5:1 on the sheet. The veil is the black laid over the material.
/// White under that veil is the brightest panel the audit can see.
enum PanelContrast {
    static let veil: CGFloat = 0.58
    /// Gold on the veil alone is about 3.2:1. This extra black brings it to about 5.1:1.
    static let rulerScrim: CGFloat = 0.28
    static let minimum: CGFloat = 4.5

    static func ratio(
        foreground: (red: CGFloat, green: CGFloat, blue: CGFloat),
        background: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) -> CGFloat {
        let lighter = max(luminance(foreground), luminance(background))
        let darker = min(luminance(foreground), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Black `veil` over white, the worst case for type sitting on the sheet.
    static func whiteUnderVeil(_ veil: CGFloat = veil) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let channel = 1 - min(1, max(0, veil))
        return (channel, channel, channel)
    }

    static func blackOver(
        _ background: (red: CGFloat, green: CGFloat, blue: CGFloat),
        opacity: CGFloat
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let keep = 1 - min(1, max(0, opacity))
        return (background.red * keep, background.green * keep, background.blue * keep)
    }

    private static func luminance(_ color: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> CGFloat {
        func channel(_ value: CGFloat) -> CGFloat {
            let clamped = min(1, max(0, value))
            if clamped <= 0.04045 { return clamped / 12.92 }
            return pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }
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
