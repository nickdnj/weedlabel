import Testing
import Foundation
@testable import weedlabel

@Suite("StrainNameOverrideStore")
@MainActor
struct StrainNameOverrideStoreTests {

    @Test func setAndResolve() {
        let store = InMemoryStrainNameOverrideStore()
        store.setCorrectedName("Blue Candy Rain", forExtractedName: "Blueberry Cariar Rain")
        #expect(store.resolve(extractedName: "Blueberry Cariar Rain") == "Blue Candy Rain")
    }

    @Test func lookupIsCaseAndWhitespaceInsensitive() {
        let store = InMemoryStrainNameOverrideStore()
        store.setCorrectedName("Blue Candy Rain", forExtractedName: "Blueberry Cariar Rain")
        #expect(store.resolve(extractedName: "  blueberry cariar rain ") == "Blue Candy Rain")
    }

    @Test func resolveReturnsInputWhenNoOverride() {
        let store = InMemoryStrainNameOverrideStore()
        #expect(store.resolve(extractedName: "Gelato") == "Gelato")
    }

    @Test func reEditsChainAndCompose() {
        // a → b, then b → c. Resolving a should follow through to c.
        let store = InMemoryStrainNameOverrideStore()
        store.setCorrectedName("Blue Candy", forExtractedName: "Blueberry Cariar")
        store.setCorrectedName("Blue Candy Rain", forExtractedName: "Blue Candy")
        #expect(store.resolve(extractedName: "Blueberry Cariar") == "Blue Candy Rain")
    }

    @Test func resolveHandlesCyclesWithoutHanging() {
        // a → b and b → a; resolve must terminate (cycle guard).
        let store = InMemoryStrainNameOverrideStore()
        store.setCorrectedName("B", forExtractedName: "A")
        store.setCorrectedName("A", forExtractedName: "B")
        let result = store.resolve(extractedName: "A")
        #expect(result == "A" || result == "B") // terminates, doesn't spin
    }

    @Test func noOpCorrectionDropsOverride() {
        // Correcting back to the same name removes the mapping.
        let store = InMemoryStrainNameOverrideStore()
        store.setCorrectedName("Gelato", forExtractedName: "gelato")
        #expect(store.allOverrides().isEmpty)
    }

    @Test func emptyInputsIgnored() {
        let store = InMemoryStrainNameOverrideStore()
        store.setCorrectedName("   ", forExtractedName: "Something")
        store.setCorrectedName("Something", forExtractedName: "   ")
        #expect(store.allOverrides().isEmpty)
    }

    @Test func removeAllClearsEverything() {
        let store = InMemoryStrainNameOverrideStore()
        store.setCorrectedName("Blue Candy Rain", forExtractedName: "Blueberry Cariar Rain")
        store.removeAll()
        #expect(store.allOverrides().isEmpty)
    }

    @Test func fileStorePersistsAcrossInstances() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("name-overrides-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store1 = FileStrainNameOverrideStore(fileURL: tmp)
        store1.setCorrectedName("Blue Candy Rain", forExtractedName: "Blueberry Cariar Rain")

        let store2 = FileStrainNameOverrideStore(fileURL: tmp)
        #expect(store2.resolve(extractedName: "Blueberry Cariar Rain") == "Blue Candy Rain")
    }
}
