import Testing
import Foundation
@testable import weedlabel

@Suite("LogStore")
@MainActor
struct LogStoreTests {

    static func sampleLabel(_ strain: String = "Blue Candy Rain") -> CannabisLabel {
        CannabisLabel(
            strainName: strain,
            cultivator: "Fresh Grow LLC",
            licenseNumber: "C000186",
            metrcTag: "1A4110300003C8D000041730",
            netWeight: "28g",
            harvestDate: "2025-12-10",
            expirationDate: "2026-07-25",
            productType: .flower,
            thca: 29.73, delta9thc: 1.45, cbd: nil, cbg: 0.49,
            totalCannabinoids: 32.25, totalThc: 27.52, totalCbd: nil,
            myrcene: 0.84, limonene: 1.83, linalool: 0.84, betaCaryophyllene: 0.44,
            pinene: 0.13, humulene: 0.13, totalTerpenes: 5.03,
            qrCodes: ["1A4110300003C8D000041730"]
        )
    }

    static func sampleEntry(_ strain: String = "Blue Candy Rain", date: Date = Date()) -> LogEntry {
        LogEntry(
            dateScanned: date,
            label: sampleLabel(strain),
            summaryText: "An indica-leaning flower with sweet berry aroma.",
            summaryDidFallback: false,
            strainLean: .indica,
            strainSourceNote: "inferred from name"
        )
    }

    // MARK: - In-memory basics

    @Test func addAndListNewestFirst() {
        let store = InMemoryLogStore()
        let older = Self.sampleEntry("Older", date: Date(timeIntervalSince1970: 1_000))
        let newer = Self.sampleEntry("Newer", date: Date(timeIntervalSince1970: 2_000))
        store.add(older)
        store.add(newer)
        let entries = store.entries()
        #expect(entries.count == 2)
        #expect(entries.first?.label.strainName == "Newer") // newest first
    }

    @Test func updatePersistsNoteAndRating() {
        let store = InMemoryLogStore()
        var entry = Self.sampleEntry()
        store.add(entry)
        entry.note = "great for evenings"
        entry.rating = 4
        store.update(entry)
        let saved = store.entries().first
        #expect(saved?.note == "great for evenings")
        #expect(saved?.rating == 4)
    }

    @Test func updateUnknownEntryIsIgnored() {
        let store = InMemoryLogStore()
        store.update(Self.sampleEntry()) // never added
        #expect(store.entries().isEmpty)
    }

    @Test func deleteRemovesEntry() {
        let store = InMemoryLogStore()
        let entry = Self.sampleEntry()
        store.add(entry)
        store.delete(id: entry.id)
        #expect(store.entries().isEmpty)
    }

    @Test func removeAllClearsEverything() {
        let store = InMemoryLogStore()
        store.add(Self.sampleEntry("A"))
        store.add(Self.sampleEntry("B"))
        store.removeAll()
        #expect(store.entries().isEmpty)
    }

    // MARK: - JSON round-trip + file persistence

    @Test func logEntryJSONRoundTrips() throws {
        let entry = Self.sampleEntry()
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)
        #expect(decoded == entry) // requires CannabisLabel: Equatable + Codable
    }

    @Test func fileStorePersistsAcrossInstances() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("logbook-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store1 = FileLogStore(fileURL: tmp)
        let entry = Self.sampleEntry()
        store1.add(entry)

        let store2 = FileLogStore(fileURL: tmp)
        #expect(store2.entries().count == 1)
        #expect(store2.entries().first?.label.strainName == "Blue Candy Rain")
    }
}
