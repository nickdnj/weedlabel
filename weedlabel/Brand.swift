import SwiftUI

/// Central brand definition for **Pocketbud — your AI budtender**.
///
/// Name, tagline, palette, and the signature gradient live here so a rebrand is
/// a one-file change and every screen stays consistent. Direction (see
/// `DESIGN.md`, the source of truth): **Bold Playful, green-primary /
/// amber-accent**. Green is the brand; amber is the one warm spark (the THC
/// number, the shutter, the lit-joint ember). Dark green-ink surfaces carry the
/// privacy-as-night mood. Supersedes the earlier green→teal→violet gradient.
///
/// Legacy token names (`green`, `teal`, `violet`, `gradient`, `backgroundWash`)
/// are kept so existing views compile; they now point at the green/amber system
/// (`violet` → amber accent). New views should prefer the named tokens below.
enum Brand {
    static let name = "Pocketbud"
    static let tagline = "Your AI budtender"
    /// The full positioning line — privacy is the pitch.
    static let pitch = "Your AI budtender. Lives in your pocket, never leaves it."

    // MARK: - Palette (DESIGN.md)

    /// Primary brand green — the "fresh / on-device / go" signal.
    static let green = Color(red: 0.184, green: 0.659, blue: 0.400)   // #2FA866
    /// Brighter green for the leaf / highlights.
    static let greenBright = Color(red: 0.247, green: 0.745, blue: 0.490) // #3FBE7D
    /// Deep green for gradient ends and pressed states.
    static let greenDeep = Color(red: 0.110, green: 0.431, blue: 0.271)   // #1C6E45
    /// Muted sage for low-emphasis surfaces.
    static let sage = Color(red: 0.420, green: 0.561, blue: 0.443)        // #6B8F71

    /// The one warm accent — THC number, shutter, active tab, "bud" wordmark.
    static let amber = Color(red: 1.000, green: 0.690, blue: 0.125)       // #FFB020
    /// Hotter amber for the lit-joint ember / emphasis.
    static let ember = Color(red: 1.000, green: 0.541, blue: 0.118)       // #FF8A1E

    // MARK: - Surfaces

    /// Default dark app surface (green-ink).
    static let ink = Color(red: 0.047, green: 0.071, blue: 0.055)         // #0C120E
    /// Deepest surface.
    static let ink2 = Color(red: 0.039, green: 0.059, blue: 0.047)        // #0A0F0C
    /// Card / raised surface on dark.
    static let card = Color(red: 0.071, green: 0.094, blue: 0.078)        // #121814
    /// Hairline / divider on dark.
    static let line = Color(red: 0.137, green: 0.165, blue: 0.145)        // #232A25
    /// Warm cream — light mode background, icon shirt, text on dark.
    static let cream = Color(red: 0.969, green: 0.953, blue: 0.922)       // #F7F3EC
    /// Ink charcoal — light-mode text.
    static let inkText = Color(red: 0.102, green: 0.102, blue: 0.122)     // #1A1A1F

    // MARK: - Legacy aliases (kept so existing views compile)

    /// Was a teal bridge; now an alias for deep green.
    static let teal = greenDeep
    /// Was the violet "AI" accent; now the amber accent.
    static let violet = amber

    // MARK: - Gradients

    /// Signature green sweep used on the wordmark, hero type, and CTAs.
    static let gradient = LinearGradient(
        colors: [greenBright, green, greenDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Softer green wash for full-screen backgrounds.
    static func backgroundWash(_ opacity: Double = 0.12) -> LinearGradient {
        LinearGradient(
            colors: [green.opacity(opacity), greenDeep.opacity(opacity)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
