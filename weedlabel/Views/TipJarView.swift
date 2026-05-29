import SwiftUI

// TipJarView — the warm, never-pushy tip sheet reachable from About. Tipping is
// the only monetization HighNotes will ever have, and the copy keeps it that
// way: a thank-you, not a paywall. Three tiers (loaded from StoreKit), a humble
// pitch, and a genuinely happy thank-you state after a tip. Styled on `Brand`
// to match AboutView.

struct TipJarView: View {
    @State private var jar = TipJar()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.backgroundWash().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        if jar.didJustTip {
                            thankYou
                        } else {
                            switch jar.loadState {
                            case .loading:
                                loading
                            case .failed(let message):
                                failed(message)
                            case .loaded:
                                tiers
                            }
                            footer
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Tip jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await jar.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Brand.gradient)
            Text("Tip jar")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.gradient)
            Text("HighNotes is free, forever. If it earned a spot on your phone, you can drop a little something in the jar — totally optional. 🌿")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            if jar.hasTippedBefore {
                Text("You've chipped in before — thank you. 💚")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Tiers

    private var tiers: some View {
        VStack(spacing: 12) {
            ForEach(jar.tiers) { tier in
                tierButton(tier)
            }
        }
    }

    private func tierButton(_ tier: TipTier) -> some View {
        let isPurchasing = jar.purchasingProductID == tier.id
        let isOtherPurchasing = jar.purchasingProductID != nil && !isPurchasing

        return Button {
            Task { await jar.tip(tier) }
        } label: {
            HStack(spacing: 14) {
                Text(tier.emoji)
                    .font(.title2)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(tier.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isPurchasing {
                    ProgressView()
                } else {
                    Text(tier.displayPrice)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Brand.gradient, in: Capsule())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(jar.purchasingProductID != nil)
        .opacity(isOtherPurchasing ? 0.5 : 1)
        .accessibilityLabel("Tip \(tier.displayPrice): \(tier.name)")
    }

    // MARK: - States

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading tip options…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await jar.load() }
            }
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
        }
        .padding(.vertical, 30)
    }

    private var thankYou: some View {
        VStack(spacing: 16) {
            Text("🌿💚")
                .font(.system(size: 56))
            Text("Thank you!")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.gradient)
            Text("This genuinely makes someone's day. HighNotes stays free for everyone — you just made it easier to keep going.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button("You're welcome 😊") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .padding(.top, 20)
    }

    private var footer: some View {
        Text("Tips are a thank-you, not a paywall — every feature is free whether you tip or not. No subscriptions, no accounts, no catch.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

#Preview {
    TipJarView()
}
