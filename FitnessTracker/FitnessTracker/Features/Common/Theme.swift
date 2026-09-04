import SwiftUI

public enum GymTheme {
    public static let bg = Color(red: 0.0, green: 0.0, blue: 0.0)
    public static let bgElevated = Color(red: 0.055, green: 0.055, blue: 0.063) // #0e0e10
    public static let surface = Color(red: 0.11, green: 0.11, blue: 0.12) // #1c1c1e
    public static let surface2 = Color(red: 0.17, green: 0.17, blue: 0.18) // #2c2c2e
    public static let surface3 = Color(red: 0.23, green: 0.23, blue: 0.24) // #3a3a3c
    
    public static let label = Color.white
    public static let label2 = Color(white: 0.70)
    public static let label3 = Color(white: 0.45)
    public static let label4 = Color(white: 0.25)
    
    // openGym Official Accents (lib/format.js: ACCENTS = { lime, sky, orange, violet, pink, red, teal, gold })
    public static let lime = Color(red: 0.19, green: 0.82, blue: 0.35) // #30d158
    public static let sky = Color(red: 0.04, green: 0.52, blue: 1.0) // #0a84ff
    public static let orange = Color(red: 1.0, green: 0.62, blue: 0.04) // #ff9f0a
    public static let violet = Color(red: 0.75, green: 0.35, blue: 0.95) // #bf5af2
    public static let pink = Color(red: 1.0, green: 0.22, blue: 0.37) // #ff375f
    public static let red = Color(red: 1.0, green: 0.27, blue: 0.23) // #ff453a
    public static let teal = Color(red: 0.25, green: 0.78, blue: 0.88) // #40c8e0
    public static let gold = Color(red: 1.0, green: 0.84, blue: 0.04) // #ffd60a
    
    // Legacy aliases
    public static let green = lime
    public static let blue = sky
    public static let purple = violet
    public static let yellow = gold

    public static let allAccents: [(key: String, color: Color)] = [
        ("lime", lime),
        ("sky", sky),
        ("orange", orange),
        ("violet", violet),
        ("pink", pink),
        ("red", red),
        ("teal", teal),
        ("gold", gold)
    ]

    public static func accent(for key: String?) -> Color {
        switch key {
        case "sky", "blue": return sky
        case "orange": return orange
        case "violet", "purple": return violet
        case "pink": return pink
        case "red": return red
        case "teal": return teal
        case "gold", "yellow": return gold
        case "lime", "green": return lime
        default: return lime
        }
    }
}

/// A small fade+slide `ViewModifier` — the Swift side of openGym's
/// `@keyframes viewfade { from{opacity:0;transform:translateY(4px)} to{opacity:1;transform:none} }`,
/// which fades and nudges every route change in by 4px instead of a hard cut.
private struct ViewFadeModifier: ViewModifier {
    let isIdentity: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isIdentity ? 1 : 0)
            .offset(y: isIdentity ? 0 : 4)
    }
}

public extension AnyTransition {
    static var viewFade: AnyTransition {
        .modifier(
            active: ViewFadeModifier(isIdentity: false),
            identity: ViewFadeModifier(isIdentity: true)
        )
    }
}
