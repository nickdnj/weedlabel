import SwiftUI

// OnboardingView — first-run welcome / elevator pitch for HighNotes.
// Direction: "bold & playful" (vivid gradient, heavy rounded type, emoji).
// One screen, one job: say what this is, promise privacy, get out of the way.
// The only thing persisted is a "seen it" flag — no accounts, no tracking.

/// Root gate. Shows the welcome screen on first launch, then hands off to the
/// existing scan flow (`ContentView`). Kept separate from `ContentView` so the
/// onboarding work stays in its own file.
struct RootView: View {
    @AppStorage("highnotes.hasSeenWelcome.v1") private var hasSeenWelcome = false

    #if DEBUG
    // Launch with `-ShowTipJar` to jump straight to the tip jar sheet — fast
    // visual iteration without tapping through onboarding → About. Mirrors the
    // `-AutoRunCanary` hook in ContentView.
    @State private var showTipJarDebug = CommandLine.arguments.contains("-ShowTipJar")
    #endif

    var body: some View {
        ZStack {
            if hasSeenWelcome {
                ContentView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) { hasSeenWelcome = true }
                }
                .transition(.opacity)
            }
        }
        #if DEBUG
        .sheet(isPresented: $showTipJarDebug) { TipJarView() }
        #endif
    }
}

struct OnboardingView: View {
    /// Called when the user taps the primary CTA.
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Brand.backgroundWash()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    wordmark
                        .padding(.bottom, 18)

                    pitch
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)

                    VStack(spacing: 12) {
                        promise(emoji: "💚", title: "100% on your phone",
                                detail: "Every scan and summary runs on-device. Nothing gets uploaded.")
                        promise(emoji: "👀", title: "Nobody's tracking you",
                                detail: "No accounts, no analytics, no ad junk. Ever.")
                        promise(emoji: "🌐", title: "Links go to the web",
                                detail: "Tap a link and you'll leave the app — that's the only thing that goes outside.")
                        promise(emoji: "🧠", title: "Smart, still learning",
                                detail: "Apple Intelligence reads each label on-device. It's not perfect yet — if it gets something wrong, fix it in a tap. It only gets better from here.")
                    }
                    .padding(.horizontal, 20)

                    sharingNote
                        .padding(.horizontal, 28)
                        .padding(.top, 26)

                    // Reserve room so content clears the floating CTA.
                    Spacer(minLength: 96)
                }
                .frame(maxWidth: .infinity)
            }

            VStack {
                Spacer()
                cta
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Pieces

    private var wordmark: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Brand.gradient)

            Text(Brand.name)
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.gradient)

            Text(Brand.tagline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var pitch: some View {
        Text("Snap a dispensary label and your budtender reads it back in plain English — strain, THC, the terps, the whole vibe. No jargon, no homework.")
            .font(.title3.weight(.regular))
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func promise(emoji: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(emoji)
                .font(.title2)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Brand.violet.opacity(0.10), lineWidth: 1)
        )
    }

    private var sharingNote: some View {
        Text("Built by one person who figured this out and wanted to share it. No catch — enjoy. 🌿")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cta: some View {
        Button(action: onContinue) {
            Text("✌️  I'm in")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
                .shadow(color: Brand.violet.opacity(0.28), radius: 14, x: 0, y: 8)
        }
        .accessibilityLabel("Get started")
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
