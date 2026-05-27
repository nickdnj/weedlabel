import SwiftUI

// PostScanView — applies the approved /design-shotgun direction (Variant C —
// "Conversational AI"): purple-mint gradient hero card, soft pastel pill chips,
// off-white background, AI-summary-as-hero hierarchy.
// The persistent disclaimer uses the exact wording from NJAC §17:30-16.3(c)(5).

struct PostScanView: View {
    let label: CannabisLabel
    let summary: SummaryOutcome?
    /// Non-nil when the sanity checker flagged something suspect about the
    /// parsed label (e.g. Total THC formula mismatch). Rendered as a warning
    /// banner — doesn't block the AI summary, just tells the user to verify
    /// against the printed label before trusting the numbers.
    let sanityWarning: String?
    /// Deterministic sativa/indica/hybrid read from the name + label marker.
    /// Rendered as a trustworthy "Profile" card distinct from the AI summary.
    let strainInsight: StrainInsight?
    /// Save a user correction for this strain's classification.
    var onSetStrainClass: (StrainLean) -> Void = { _ in }
    /// Remove a saved correction, reverting to marker/lineage inference.
    var onClearStrainClass: () -> Void = {}
    /// Apply a user correction to the inferred product type.
    var onSetProductType: (ProductType) -> Void = { _ in }
    /// Apply a user correction to the strain name (worst-case OCR misreads).
    var onSetStrainName: (String) -> Void = { _ in }
    /// Persist the current scan to the Log Book, then reset.
    var onSave: () -> Void = {}
    let onReset: () -> Void

    @State private var sourceDataExpanded: Bool = false
    @State private var editingStrainClass: Bool = false
    @State private var editingProductType: Bool = false
    @State private var editingName: Bool = false
    @State private var nameDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                productHeader

                if let sanityWarning {
                    verifyBanner(reason: sanityWarning)
                }

                if label.isHighPotency {
                    highPotencyWarning
                }

                if let strainInsight {
                    profileCard(strainInsight)
                } else {
                    setStrainClassPrompt
                }

                if editingStrainClass {
                    strainClassPicker
                }

                if editingProductType {
                    productTypePicker
                }

                heroCard

                if !chipPairs.isEmpty {
                    chips
                }

                learnMoreSection

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
                Brand.backgroundWash(0.14)
            }
            .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
    }

    private var productHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label.strainName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Button {
                        nameDraft = label.strainName
                        editingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Edit strain name")
                }
                Text(label.cultivator)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            productTypePill
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Edit strain name", isPresented: $editingName) {
            TextField("Strain name", text: $nameDraft)
            Button("Save") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { onSetStrainName(trimmed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fix a name the scanner misread. Your correction sticks for future scans of this product.")
        }
    }

    /// The inferred product type, tappable to correct — the FM sometimes
    /// mis-reads it (e.g. flower as edible). Mirrors the strain-type correction.
    private var productTypePill: some View {
        Button {
            withAnimation { editingProductType.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: label.productType.iconName)
                    .font(.caption2)
                Text(label.productType.displayName)
                    .font(.caption.weight(.medium))
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Product type: \(label.productType.displayName). Tap to correct.")
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
            Brand.gradient,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Brand.violet.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var summaryText: String {
        if let summary {
            return summary.text
        }
        // No AI run (older device, AI off, or summary failed) — show a
        // deterministic line built from the strain character + any chemistry,
        // so the hero card stays compelling rather than blank.
        return SummaryService.buildFallback(label, strainInsight: strainInsight)
    }

    private var chipPairs: [(String, ChipPalette)] {
        var pairs: [(String, ChipPalette)] = []
        if let v = label.myrcene { pairs.append(("myrcene \(format(v))%", .lavender)) }
        if let v = label.thca { pairs.append(("THCA \(format(v))%", .mint)) }
        if let v = label.linalool { pairs.append(("linalool \(format(v))%", .peach)) }
        if let v = label.betaCaryophyllene { pairs.append(("β-caryophyllene \(format(v))%", .sky)) }
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

    @ViewBuilder
    private var learnMoreSection: some View {
        let links = ProductLinks.links(for: label)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("LEARN MORE")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                ForEach(links) { link in
                    Link(destination: link.url) {
                        HStack(spacing: 10) {
                            Image(systemName: link.kind == .labelLink ? "qrcode" : "magnifyingglass")
                                .font(.callout)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(link.title)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(link.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }
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

    private func profileCard(_ insight: StrainInsight) -> some View {
        HStack(spacing: 12) {
            Image(systemName: profileIcon(insight.lean))
                .font(.title3)
                .foregroundStyle(profileTint(insight.lean))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(insight.lean.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("· \(insight.lean.timeOfDay)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(insight.lean.effectLanguage.capitalizingFirstLetter())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(insight.sourceNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                withAnimation { editingStrainClass.toggle() }
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Correct strain type")
        }
        .padding(14)
        .background(profileTint(insight.lean).opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(profileTint(insight.lean).opacity(0.25), lineWidth: 1)
        )
    }

    /// Shown when we have no classification at all — invites the user to tag it.
    private var setStrainClassPrompt: some View {
        Button {
            withAnimation { editingStrainClass = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Strain type unknown")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Tap to set sativa, indica, or hybrid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// The strain-type picker shown while editing. Vertical list so all five
    /// options (including the two hybrid-leaning variants) read clearly. Saves
    /// on selection and collapses.
    private var strainClassPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SET STRAIN TYPE")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            ForEach(StrainLean.allCases, id: \.self) { lean in
                Button {
                    onSetStrainClass(lean)
                    withAnimation { editingStrainClass = false }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: profileIcon(lean))
                            .font(.callout)
                            .foregroundStyle(profileTint(lean))
                            .frame(width: 24)
                        Text(lean.shortLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if strainInsight?.lean == lean {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(profileTint(lean))
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(profileTint(lean).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(profileTint(lean).opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            if strainInsight?.isUserOverride == true {
                Button(role: .destructive) {
                    onClearStrainClass()
                    withAnimation { editingStrainClass = false }
                } label: {
                    Label("Remove my correction", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Product-type picker shown while correcting. Selecting hands off to the
    /// model, which re-runs the productType-aware sanity check.
    private var productTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT KIND OF PRODUCT IS THIS?")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            ForEach(ProductType.allCases, id: \.self) { type in
                Button {
                    onSetProductType(type)
                    withAnimation { editingProductType = false }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: type.iconName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(type.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if label.productType == type {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func profileIcon(_ lean: StrainLean) -> String {
        switch lean {
        case .sativa: return "sun.max.fill"
        case .indica: return "moon.fill"
        case .hybrid: return "circle.lefthalf.filled"
        case .hybridSativa: return "sun.horizon.fill"
        case .hybridIndica: return "moon.haze.fill"
        }
    }

    private func profileTint(_ lean: StrainLean) -> Color {
        switch lean {
        case .sativa: return Color(red: 0.90, green: 0.62, blue: 0.10)       // warm amber — daytime
        case .indica: return Color(red: 0.42, green: 0.38, blue: 0.78)       // indigo — evening
        case .hybrid: return Color(red: 0.20, green: 0.60, blue: 0.50)       // teal — balanced
        case .hybridSativa: return Color(red: 0.55, green: 0.62, blue: 0.25) // amber-teal — day-leaning
        case .hybridIndica: return Color(red: 0.34, green: 0.48, blue: 0.66) // indigo-teal — evening-leaning
        }
    }

    private func verifyBanner(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Verify against the printed label")
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
            }
            .foregroundStyle(Color(red: 0.76, green: 0.45, blue: 0.05))
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.30), lineWidth: 1)
        )
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
        HStack(spacing: 10) {
            Button(action: onReset) {
                Text("Discard")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                    )
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: 120)

            Button(action: onSave) {
                HStack {
                    Image(systemName: "books.vertical.fill")
                    Text("Save to Log Book")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .shadow(color: Brand.violet.opacity(0.22), radius: 8, x: 0, y: 4)
            }
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

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
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
