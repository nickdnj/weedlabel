import SwiftUI

// AboutView — reachable from the home screen. Restates what HighNotes is and the
// privacy promise (UXD §3.1 wants the promise reinforced beyond first run), and
// lets the user replay the intro. The "share it, enjoy" ethos lives here, and so
// does the tip jar — the one, never-pushy way to support the app (see TipJar).

struct AboutView: View {
    /// Reset the first-run flag so RootView shows the welcome again.
    @AppStorage("highnotes.hasSeenWelcome.v1") private var hasSeenWelcome = false
    @Environment(\.dismiss) private var dismiss

    /// Wipe locally-saved corrections (strain lean + product type).
    var onClearData: () -> Void = {}
    @State private var showClearDataConfirm = false
    @State private var showTipJar = false

    #if BETA
    /// Opt-out switch for beta scan sharing (default ON). Beta builds only —
    /// compiled out of the App Store build.
    @AppStorage(BetaFeedback.shareEnabledKey) private var betaShareEnabled = true
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.backgroundWash().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        VStack(spacing: 12) {
                            promise(emoji: "💚", title: "100% on your phone",
                                    detail: "Scanning and the AI summary run on-device. Nothing gets uploaded.")
                            promise(emoji: "👀", title: "Nobody's tracking you",
                                    detail: "No accounts, no analytics, no ad junk.")
                            promise(emoji: "🌐", title: "Links go to the web",
                                    detail: "Tapping a link is the only thing that leaves the app.")
                            promise(emoji: "🧠", title: "Smart, still learning",
                                    detail: "Apple Intelligence reads labels on-device. When it slips up, correct it in a tap — it only gets better.")
                        }

                        tipJarButton

                        #if BETA
                        betaShareSection
                        #endif

                        replayButton

                        clearDataButton

                        Text("Built by one person who figured this out and wanted to share it. No catch — enjoy. 🌿")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showTipJar) { TipJarView() }
        }
    }

    #if BETA
    private var betaShareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $betaShareEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "flask.fill").foregroundStyle(Brand.gradient)
                    Text("Share scans (beta)").font(.headline.weight(.bold))
                }
            }
            Text("Beta only — never in the App Store build. When on, you'll be asked after a scan if you want to share it (label text, the AI's read, your corrections, note, and photo) to help improve the app. Always your explicit tap; nothing is sent automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
    #endif

    private var tipJarButton: some View {
        Button {
            showTipJar = true
        } label: {
            HStack {
                Image(systemName: "heart.fill")
                Text("Tip jar")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            PocketbudMark(size: 52)
            Text(Brand.name)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.gradient)
            Text(Brand.tagline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Point your camera at a dispensary label and get a plain-English read on what you're about to enjoy — strain, THC, terps, the whole vibe.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func promise(emoji: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(emoji).font(.title2).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.weight(.bold))
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
    }

    private var replayButton: some View {
        Button {
            hasSeenWelcome = false // RootView observes this and re-shows the intro
            dismiss()
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Replay the intro")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
    }

    private var clearDataButton: some View {
        Button(role: .destructive) {
            showClearDataConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Clear local data")
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
            .foregroundStyle(.red)
        }
        .confirmationDialog("Clear local data?", isPresented: $showClearDataConfirm, titleVisibility: .visible) {
            Button("Clear saved corrections", role: .destructive) { onClearData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the strain, product-type, and name corrections saved on this device. Your Log Book entries are kept. This can't be undone.")
        }
    }
}

#Preview {
    AboutView()
}
