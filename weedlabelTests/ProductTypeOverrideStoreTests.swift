import Testing
import Foundation
@testable import weedlabel

@Suite("ProductTypeOverrideStore")
@MainActor
struct ProductTypeOverrideStoreTests {

    // MARK: - In-memory store basics

    @Test func setAndReadOverride() {
        let store = InMemoryProductTypeOverrideStore()
        store.setProductType(.flower, forStrainName: "Blue Candy Rain")
        #expect(store.productType(forStrainName: "Blue Candy Rain") == .flower)
    }

    @Test func lookupIsCaseAndWhitespaceInsensitive() {
        let store = InMemoryProductTypeOverrideStore()
        store.setProductType(.preRoll, forStrainName: "Gelato")
        #expect(store.productType(forStrainName: "  gelato ") == .preRoll)
    }

    @Test func correctionOverwritesPrevious() {
        let store = InMemoryProductTypeOverrideStore()
        store.setProductType(.edible, forStrainName: "Mystery")
        store.setProductType(.flower, forStrainName: "Mystery") // user fixes it
        #expect(store.productType(forStrainName: "Mystery") == .flower)
    }

    @Test func removeOverride() {
        let store = InMemoryProductTypeOverrideStore()
        store.setProductType(.vape, forStrainName: "Sour Diesel")
        store.removeOverride(forStrainName: "Sour Diesel")
        #expect(store.productType(forStrainName: "Sour Diesel") == nil)
    }

    @Test func removeAllClearsEverything() {
        let store = InMemoryProductTypeOverrideStore()
        store.setProductType(.flower, forStrainName: "A")
        store.setProductType(.edible, forStrainName: "B")
        store.removeAll()
        #expect(store.allOverrides().isEmpty)
    }

    @Test func emptyNameIgnored() {
        let store = InMemoryProductTypeOverrideStore()
        store.setProductType(.flower, forStrainName: "   ")
        #expect(store.allOverrides().isEmpty)
    }

    // MARK: - File store round-trip persistence (the point of this feature)

    @Test func fileStorePersistsAcrossInstances() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptype-overrides-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store1 = FileProductTypeOverrideStore(fileURL: tmp)
        store1.setProductType(.flower, forStrainName: "Blueberry Cariar") // was mis-read as edible

        // A fresh instance reading the same file should see the saved fix.
        let store2 = FileProductTypeOverrideStore(fileURL: tmp)
        #expect(store2.productType(forStrainName: "Blueberry Cariar") == .flower)
    }

    @Test func fileStoreRemoveAllPersists() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptype-clear-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store1 = FileProductTypeOverrideStore(fileURL: tmp)
        store1.setProductType(.concentrate, forStrainName: "Live Rosin")
        store1.removeAll()

        let store2 = FileProductTypeOverrideStore(fileURL: tmp)
        #expect(store2.productType(forStrainName: "Live Rosin") == nil)
    }

    // MARK: - ProductType storage representation

    @Test func storageKeyRoundTripsForAllCases() {
        for type in ProductType.allCases {
            #expect(ProductType(storageKey: type.storageKey) == type)
        }
    }

    @Test func unknownStorageKeyIsNil() {
        #expect(ProductType(storageKey: "banana") == nil)
    }

    @Test func allCasesHaveDistinctNonEmptyDisplayNames() {
        var names = Set<String>()
        for type in ProductType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(!type.iconName.isEmpty)
            names.insert(type.displayName)
        }
        #expect(names.count == ProductType.allCases.count)
    }
}
