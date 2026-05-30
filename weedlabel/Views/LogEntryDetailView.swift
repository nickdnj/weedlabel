import SwiftUI
import UIKit

// LogEntryDetailView — a saved scan with the user's own note + star rating, plus
// tap-to-correct pickers (strain name, product type, strain type) that mirror the
// result screen. Edits mutate `entry` and persist immediately via
// LogBookModel.update. Dark green Pocketbud theme.

struct LogEntryDetailView: View {
    @State private var entry: LogEntry
    @State private var showingOriginal = false
    @State private var zoomItem: ZoomItem?
    @State private var editingProductType = false
    @State private var editingStrainClass = false
    @State private var editingName = false
    @State private var typingName = false
    @State private var nameDraft = ""
    let model: LogBookModel

    /// Identifiable wrapper so the zoom viewer can be presented via `.fullScreenCover(item:)`.
    private struct ZoomItem: Identifiable { let id = UUID(); let image: UIImage }

    init(entry: LogEntry, model: LogBookModel) {
        _entry = State(initialValue: entry)
        self.model = model
    }

    /// Plausible names read straight from the saved label OCR, for the
    /// pick-to-correct list. Empty for older entries with no stored OCR — the
    /// "type a name" path always works as a fallback.
    private var nameCandidates: [String] {
        let current = entry.label.strainName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return StrainNameFixer.candidateNames(ocrText: entry.ocrText ?? "", cultivator: entry.label.cultivator)
            .filter { $0.lowercased() != current }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let image = displayedImage { imageBlock(image) }
                header
                if editingProductType { productTypePicker }
                if editingStrainClass { strainClassPicker }
                ratingEditor
                noteEditor
                summaryCard
                if !chips.isEmpty { chipsView }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(Brand.ink.ignoresSafeArea())
        .navigationTitle(entry.label.strainName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Persist every edit (note, rating, and the new corrections). LogEntry is
        // Equatable, so this fires only on an actual change.
        .onChange(of: entry) { _, updated in model.update(updated) }
        .fullScreenCover(item: $zoomItem) { item in
            ZoomableImageView(image: item.image)
        }
        // Pick the strain name straight from the label OCR, or type one. Mirrors
        // the result screen; here the correction is saved to this log entry.
        .confirmationDialog("Pick the strain name from the label", isPresented: $editingName, titleVisibility: .visible) {
            ForEach(nameCandidates, id: \.self) { name in
                Button(name) { entry.label.strainName = name }
            }
            Button("Type a different name…") {
                nameDraft = entry.label.strainName
                typingName = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Edit strain name", isPresented: $typingName) {
            TextField("Strain name", text: $nameDraft)
            Button("Save") {
                let t = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { entry.label.strainName = t }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fix a name the scanner misread on this entry.")
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func imageBlock(_ image: UIImage) -> some View {
        VStack(spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12))
                )
                // Tap to inspect the label up close (pan/zoom).
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(8)
                }
                .contentShape(Rectangle())
                .onTapGesture { zoomItem = ZoomItem(image: image) }
            if entry.originalImageFilename != nil {
                Button { showingOriginal.toggle() } label: {
                    Label(showingOriginal ? "View label" : "View full photo",
                          systemImage: showingOriginal ? "crop" : "photo")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.amber)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.label.strainName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Brand.cream)
                Button {
                    nameDraft = entry.label.strainName
                    editingName = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(Brand.greenBright)
                }
                .accessibilityLabel("Edit strain name")
            }
            Text(entry.label.cultivator)
                .font(.subheadline)
                .foregroundStyle(Brand.cream.opacity(0.6))

            // Tap-to-correct pills: product type + strain type.
            HStack(spacing: 8) {
                correctionPill(icon: entry.label.productType.iconName,
                               title: entry.label.productType.displayName) {
                    withAnimation { editingProductType.toggle(); editingStrainClass = false }
                }
                correctionPill(icon: leanIcon(entry.strainLean),
                               title: entry.strainLean?.shortLabel ?? "Set strain type") {
                    withAnimation { editingStrainClass.toggle(); editingProductType = false }
                }
            }
            .padding(.top, 2)

            Text(entry.dateScanned, format: .dateTime.month().day().year())
                .font(.caption)
                .foregroundStyle(Brand.cream.opacity(0.5))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func correctionPill(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Brand.green.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(Brand.green.opacity(0.35), lineWidth: 1))
            .foregroundStyle(Brand.greenBright)
        }
        .buttonStyle(.plain)
    }

    private var productTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("WHAT KIND OF PRODUCT IS THIS?")
            ForEach(ProductType.allCases, id: \.self) { type in
                Button {
                    entry.label.productType = type
                    withAnimation { editingProductType = false }
                } label: {
                    pickerRow(icon: type.iconName, title: type.displayName,
                              selected: entry.label.productType == type)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var strainClassPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SET STRAIN TYPE")
            ForEach(StrainLean.allCases, id: \.self) { lean in
                Button {
                    entry.strainLean = lean
                    entry.strainSourceNote = "Set by you"
                    withAnimation { editingStrainClass = false }
                } label: {
                    pickerRow(icon: leanIcon(lean), title: lean.shortLabel,
                              selected: entry.strainLean == lean)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func pickerRow(icon: String, title: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(Brand.greenBright)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Brand.cream)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.amber)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Brand.green.opacity(selected ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func leanIcon(_ lean: StrainLean?) -> String {
        switch lean {
        case .sativa: return "sun.max.fill"
        case .indica: return "moon.fill"
        case .hybrid: return "circle.lefthalf.filled"
        case .hybridSativa: return "sun.horizon.fill"
        case .hybridIndica: return "moon.haze.fill"
        case nil: return "questionmark.circle"
        }
    }

    private var ratingEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("YOUR RATING")
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        entry.rating = (entry.rating == i) ? 0 : i // tap again to clear
                    } label: {
                        star(i)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                }
            }
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("YOUR NOTES")
            TextField("How was it? Aroma, effects, the vibe…", text: $entry.note, axis: .vertical)
                .lineLimit(3...8)
                .foregroundStyle(Brand.cream)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Brand.card)
                )
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.amber)
                Text(entry.summaryDidFallback ? "Field summary" : "Pocketbud says")
                    .font(.caption.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(Brand.cream.opacity(0.85))
            }
            Text(entry.summaryText)
                .font(.callout)
                .foregroundStyle(Brand.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Brand.card)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Brand.line, lineWidth: 1))
        )
    }

    private var chipsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("CHEMISTRY & TERPENES")
            FlowLayout(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Brand.green.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(Brand.greenBright.opacity(0.3), lineWidth: 1))
                        .foregroundStyle(Brand.greenBright)
                }
            }
        }
    }

    private func star(_ i: Int) -> some View {
        Image(systemName: i <= entry.rating ? "star.fill" : "star")
            .font(.title2)
            .foregroundStyle(i <= entry.rating ? Brand.amber : Brand.cream.opacity(0.3))
    }

    /// Image shown at the top: the isolated label by default, the full original
    /// when the user toggles (only available if a separate original was kept).
    private var displayedImage: UIImage? {
        if showingOriginal, let orig = entry.originalImageFilename {
            return LogImageStore.loadFull(orig)
        }
        return entry.imageFilename.flatMap(LogImageStore.loadFull)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Brand.cream.opacity(0.5))
    }

    /// Cannabinoid + terpene chips from the saved label.
    private var chips: [String] {
        let l = entry.label
        var out: [String] = []
        if let v = l.thca { out.append("THCA \(LogFormat.pct(v))") }
        if let v = l.totalThc { out.append("Total THC \(LogFormat.pct(v))") }
        if let v = l.delta9thc { out.append("Δ9-THC \(LogFormat.pct(v))") }
        if let v = l.cbg { out.append("CBG \(LogFormat.pct(v))") }
        if let v = l.cbd { out.append("CBD \(LogFormat.pct(v))") }
        if let v = l.totalTerpenes { out.append("Terpenes \(LogFormat.pct(v))") }
        if let v = l.myrcene { out.append("myrcene \(LogFormat.pct(v))") }
        if let v = l.limonene { out.append("limonene \(LogFormat.pct(v))") }
        if let v = l.linalool { out.append("linalool \(LogFormat.pct(v))") }
        if let v = l.betaCaryophyllene { out.append("β-caryophyllene \(LogFormat.pct(v))") }
        if let v = l.pinene { out.append("pinene \(LogFormat.pct(v))") }
        if let v = l.humulene { out.append("humulene \(LogFormat.pct(v))") }
        return out
    }
}

/// Minimal flow layout — wraps chips onto multiple lines, content-sized.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
