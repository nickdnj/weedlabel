#if BETA
import SwiftUI

// BetaConsentView — BETA BUILDS ONLY (compiled out of the App Store build).
//
// A one-time DISCLOSURE, not a gate. Sharing is already on (opt-out); this just
// tells the tester, once, what gets shared and how to turn it off. Shown the
// first time the app reaches a result with sharing enabled.

struct BetaConsentView: View {
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 38, height: 5)
                .padding(.top, 8)

            Image(systemName: "flask.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Brand.gradient)

            Text("You're on the beta")
                .font(.title3.weight(.bold))

            Text("To help sharpen the AI, this beta build can share a scan with the developer. It's **on by default** for testers — you can turn it off anytime in **About → Share scans**.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                bullet("Only when you tap “Share scan” after a result")
                bullet("What's sent: the label text, the AI's read, any corrections you made, your note, and the label photo")
                bullet("It goes through your own Mail (or share sheet) — you see it before it sends")
                bullet("Never in the App Store version. This is a beta-only tool.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Button(action: onDismiss) {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 8)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.gradient)
                .font(.subheadline)
            Text(.init(text))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
#endif
