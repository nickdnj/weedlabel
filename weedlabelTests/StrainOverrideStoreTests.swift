import Testing
import Foundation
@testable import weedlabel

@Suite("StrainOverrideStore")
@MainActor
struct StrainOverrideStoreTests {

    // MARK: - In-memory store basics

    @Test func setAndReadOverride() {
        let store = InMemoryStrainOverrideStore()
        store.setLean(.sativa, forStrainName: "Lollipopz")
        #expect(store.lean(forStrainName: "Lollipopz") == .sativa)
    }

    @Test func lookupIsCaseAndWhitespaceInsensitive() {
        let store = InMemoryStrainOverrideStore()
        store.setLean(.indica, forStrainName: "Blue Candy Rain")
        #expect(store.lean(forStrainName: "  blue candy rain ") == .indica)
    }

    @Test func removeOverride() {
        let store = InMemoryStrainOverrideStore()
        store.setLean(.hybrid, forStrainName: "Gelato")
        store.removeOverride(forStrainName: "Gelato")
        #expect(store.lean(forStrainName: "Gelato") == nil)
    }

    @Test func emptyNameIgnored() {
        let store = InMemoryStrainOverrideStore()
        store.setLean(.sativa, forStrainName: "   ")
        #expect(store.allOverrides().isEmpty)
    }

    // MARK: - File store round-trip persistence

    @Test func fileStorePersistsAcrossInstances() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("overrides-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store1 = FileStrainOverrideStore(fileURL: tmp)
        store1.setLean(.indica, forStrainName: "Northern Lights")

        // New instance reading the same file should see the saved override.
        let store2 = FileStrainOverrideStore(fileURL: tmp)
        #expect(store2.lean(forStrainName: "Northern Lights") == .indica)
    }

    // MARK: - Insight precedence with override

    @Test func userOverrideWinsOverLineage() {
        // "OG Kush" infers indica from lineage, but a saved sativa override
        // should win.
        let insight = StrainKnowledgeBase.insight(
            strainName: "OG Kush",
            ocrText: "OG Kush Flower",
            override: .sativa
        )
        #expect(insight?.lean == .sativa)
        #expect(insight?.source == .userOverride)
    }

    @Test func userOverrideWinsOverPrintedMarker() {
        // Label marks "(I)" but the user corrected to hybrid — user wins.
        let insight = StrainKnowledgeBase.insight(
            strainName: "Mystery",
            ocrText: "Mystery (I) Flower",
            override: .hybrid
        )
        #expect(insight?.lean == .hybrid)
        #expect(insight?.source == .userOverride)
    }

    @Test func noOverrideFallsThroughToMarker() {
        let insight = StrainKnowledgeBase.insight(
            strainName: "Mystery",
            ocrText: "Mystery (I) Flower",
            override: nil
        )
        #expect(insight?.lean == .indica)
        #expect(insight?.source == .printedMarker)
    }

    // MARK: - Hybrid-leaning variants

    @Test func hybridLeaningVariantsPersist() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("overrides-lean-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store1 = FileStrainOverrideStore(fileURL: tmp)
        store1.setLean(.hybridSativa, forStrainName: "Day Hybrid")
        store1.setLean(.hybridIndica, forStrainName: "Night Hybrid")

        let store2 = FileStrainOverrideStore(fileURL: tmp)
        #expect(store2.lean(forStrainName: "Day Hybrid") == .hybridSativa)
        #expect(store2.lean(forStrainName: "Night Hybrid") == .hybridIndica)
    }

    @Test func allFiveLeansHaveDistinctNonEmptyCopy() {
        var displays = Set<String>()
        for lean in StrainLean.allCases {
            #expect(!lean.displayName.isEmpty)
            #expect(!lean.shortLabel.isEmpty)
            #expect(!lean.effectLanguage.isEmpty)
            #expect(!lean.timeOfDay.isEmpty)
            displays.insert(lean.displayName)
        }
        #expect(StrainLean.allCases.count == 5)
        #expect(displays.count == 5, "each lean should have a distinct display name")
    }

    @Test func hybridLeaningOverrideWinsInInsight() {
        let insight = StrainKnowledgeBase.insight(
            strainName: "OG Kush",                 // lineage would say indica
            ocrText: "OG Kush (I) Flower",          // marker says indica
            override: .hybridSativa                 // user says hybrid-sativa
        )
        #expect(insight?.lean == .hybridSativa)
        #expect(insight?.source == .userOverride)
    }
}
