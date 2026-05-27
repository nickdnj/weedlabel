import SwiftUI

// LogBookView — the Log Book ("your HighNotes"): the list of saved scans, each
// openable for detail + personal note/rating. Presented as a sheet from the
// home screen, with its own NavigationStack (push to detail) so it doesn't
// fight the scan flow's hidden nav bar.

@Observable
@MainActor
final class LogBookModel {
    private let store: LogStoring
    private(set) var entries: [LogEntry] = []

    init(store: LogStoring = FileLogStore()) {
        self.store = store
        reload()
    }

    func reload() { entries = store.entries() }

    func update(_ entry: LogEntry) {
        store.update(entry)
        reload()
    }

    func delete(at offsets: IndexSet) {
        for id in offsets.map({ entries[$0].id }) { store.delete(id: id) }
        reload()
    }
}

struct LogBookView: View {
    @State private var model = LogBookModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(model.entries) { entry in
                            NavigationLink {
                                LogEntryDetailView(entry: entry, model: model)
                            } label: {
                                LogRow(entry: entry)
                            }
                        }
                        .onDelete(perform: model.delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Log Book")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { model.reload() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Brand.gradient)
            Text("No high notes yet")
                .font(.title3.weight(.semibold))
            Text("Scan a label and tap “Save to Log Book” to start your journal.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack { Color(.systemBackground); Brand.backgroundWash(0.14) }.ignoresSafeArea()
        )
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.label.strainName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(entry.dateScanned, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Label(entry.label.productType.displayName, systemImage: entry.label.productType.iconName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if let thca = entry.label.thca {
                    Text("· THCA \(LogFormat.pct(thca))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.rating > 0 {
                    StarRow(rating: entry.rating)
                }
            }
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Read-only star display.
struct StarRow: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(i <= rating ? Brand.green : Color.secondary.opacity(0.35))
            }
        }
    }
}

enum LogFormat {
    static func pct(_ d: Double) -> String {
        (d == d.rounded() ? String(format: "%.0f", d) : String(format: "%.2f", d)) + "%"
    }
}

#Preview {
    LogBookView()
}
