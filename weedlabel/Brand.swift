import SwiftUI

/// Central brand definition for **HighNotes — your AI budtender**.
///
/// Name, tagline, palette, and the signature gradient live here so a rebrand is
/// a one-file change and every screen stays consistent. Direction: "bold &
/// playful" — vivid green→violet gradient, rounded heavy type, emoji-forward
/// copy. Nods to the existing PostScanView pastel hero, just turned up.
enum Brand {
    static let name = "HighNotes"
    static let tagline = "Your AI budtender"

    // MARK: - Palette

    /// Vivid green — the "fresh / on-device / go" signal.
    static let green = Color(red: 0.13, green: 0.78, blue: 0.40)
    /// Teal midpoint that bridges green → violet without going muddy.
    static let teal = Color(red: 0.09, green: 0.72, blue: 0.63)
    /// Vivid violet — the "smart / AI" signal; echoes the lavender AccentColor.
    static let violet = Color(red: 0.56, green: 0.36, blue: 0.96)

    // MARK: - Gradients

    /// Signature diagonal gradient used on the wordmark, hero type, and CTAs.
    static let gradient = LinearGradient(
        colors: [green, teal, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Softer wash of the same gradient for full-screen backgrounds.
    static func backgroundWash(_ opacity: Double = 0.12) -> LinearGradient {
        LinearGradient(
            colors: [green.opacity(opacity), violet.opacity(opacity)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
