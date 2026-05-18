import SwiftUI

// PostScanView — applies the approved /design-shotgun direction (Variant C —
// "Conversational AI"): purple-mint gradient hero card, soft pastel pill chips,
// off-white background, AI-summary-as-hero hierarchy.
// The persistent disclaimer uses the exact wording from NJAC §17:30-16.3(c)(5).

struct PostScanView: View {
    let label: CannabisLabel
    let summary: SummaryOutcome?
    let onReset: () -> Void

    @State private var sourceDataExpanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                productHeader

                if label.isHighPotency {
                    highPotencyWarning
                }

                heroCard

                if !chipPairs.isEmpty {
                    chips
                }

                disclaimer

                sourceDataDisclosure
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(
            ZStack {
                Color(.systemBackground)
                LinearGradient(
                    colors: [
                        Color(red: 0.72, green: 0.71, blue: 1.0).opacity(0.16),
                        Color(red: 0.69, green: 0.90, blue: 0.82).opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
    }

    private var productHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.strainName)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            Text(label.cultivator)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                Text("AI Summary")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.primary.opacity(0.6))
                if let summary, summary.didFallback {
                    Spacer()
                    Text("Field summary")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                        .foregroundStyle(.secondary)
                } else {
                    Spacer()
                }
            }

            Text(summaryText)
                .font(.title3.weight(.regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.72, green: 0.71, blue: 1.0),
                    Color(red: 0.69, green: 0.90, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Color(red: 0.42, green: 0.38, blue: 1.0).opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var summaryText: String {
        if let summary {
            return summary.text
        }
        // No AI run (older device, AI off, or summary failed) — show a deterministic
        // field-only line so the hero card is never empty.
        return SummaryService.buildFallback(label)
    }

    private var chipPairs: [(String, ChipPalette)] {
        var pairs: [(String, ChipPalette)] = []
        if let v = label.terpenes.myrcene { pairs.append(("myrcene \(format(v))%", .lavender)) }
        if let v = label.cannabinoids.thca { pairs.append(("THCA \(format(v))%", .mint)) }
        if let v = label.terpenes.linalool { pairs.append(("linalool \(format(v))%", .peach)) }
        if let v = label.terpenes.betaCaryophyllene { pairs.append(("β-caryophyllene \(format(v))%", .sky)) }
        return pairs
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BASED ON")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            FlowingChips(items: chipPairs)
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Summary — informational only. Verify against the printed label. This statement has not been evaluated by the Food and Drug Administration. This product is not intended to diagnose, treat, cure, or prevent any disease.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }

    private var highPotencyWarning: some View {
        Label {
            Text("This is a high potency product and may increase your risk for psychosis.")
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sourceDataDisclosure: some View {
        DisclosureGroup(isExpanded: $sourceDataExpanded) {
            ParsedFieldsList(label: label)
                .padding(.top, 12)
        } label: {
            Text("Source data")
                .font(.callout.weight(.medium))
        }
        .padding(14)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var saveButton: some View {
        Button(action: onReset) {
            Text("Save & scan another")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.71, blue: 1.0),
                            Color(red: 0.69, green: 0.90, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(.primary)
                .shadow(color: Color(red: 0.42, green: 0.38, blue: 1.0).opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }

    private func format(_ d: Double) -> String {
        String(format: "%.2f", d)
    }
}

// MARK: - Chip palette + flowing layout

enum ChipPalette {
    case lavender, mint, peach, sky

    var fill: Color {
        switch self {
        case .lavender: return Color(red: 0.93, green: 0.92, blue: 1.0)
        case .mint:     return Color(red: 0.84, green: 0.95, blue: 0.89)
        case .peach:    return Color(red: 0.99, green: 0.91, blue: 0.85)
        case .sky:      return Color(red: 0.84, green: 0.93, blue: 0.98)
        }
    }
    var text: Color {
        switch self {
        case .lavender: return Color(red: 0.26, green: 0.22, blue: 0.79)
        case .mint:     return Color(red: 0.02, green: 0.47, blue: 0.34)
        case .peach:    return Color(red: 0.76, green: 0.26, blue: 0.05)
        case .sky:      return Color(red: 0.01, green: 0.41, blue: 0.63)
        }
    }
}

struct FlowingChips: View {
    let items: [(String, ChipPalette)]

    var body: some View {
        // Simple wrapping flex layout
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(0..<items.count, id: \.self) { i in
                let (label, palette) = items[i]
                Text(label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.fill, in: Capsule())
                    .foregroundStyle(palette.text)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            }
        }
    }
}
