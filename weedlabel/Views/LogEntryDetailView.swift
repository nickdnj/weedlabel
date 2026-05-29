import SwiftUI
import UIKit

// LogEntryDetailView — a saved scan with the user's own note + star rating
// ("your HighNotes"). Edits persist immediately via LogBookModel.update. Styled
// to match the result screen (gradient summary hero, pastel chem chips).

struct LogEntryDetailView: View {
    @State private var entry: LogEntry
    let model: LogBookModel

    init(entry: LogEntry, model: LogBookModel) {
        _entry = State(initialValue: entry)
        self.model = model
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let image = labelImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.15))
                        )
                }
                header
                ratingEditor
                noteEditor
                summaryCard
                if !chips.isEmpty { chipsView }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(
            ZStack { Color(.systemBackground); Brand.backgroundWash(0.14) }.ignoresSafeArea()
        )
        .navigationTitle(entry.label.strainName)
        .navigationBarTitleDisplayMode(.inline)
        // Persist note/rating edits. LogEntry is Equatable, so this fires only on
        // actual change.
        .onChange(of: entry) { _, updated in model.update(updated) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.label.strainName)
                .font(.title2.weight(.bold))
            Text(entry.label.cultivator)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(entry.label.productType.displayName, systemImage: entry.label.productType.iconName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Text(entry.dateScanned, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                Text(entry.summaryDidFallback ? "FIELD SUMMARY" : "AI SUMMARY")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(.white.opacity(0.9))
            Text(entry.summaryText)
                .font(.callout)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Brand.violet.opacity(0.18), radius: 14, x: 0, y: 6)
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
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func star(_ i: Int) -> some View {
        Image(systemName: i <= entry.rating ? "star.fill" : "star")
            .font(.title2)
            .foregroundStyle(i <= entry.rating ? Brand.green : Color.secondary.opacity(0.35))
    }

    /// The saved scan image, if this entry has one.
    private var labelImage: UIImage? {
        entry.imageFilename.flatMap(LogImageStore.loadFull)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
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
