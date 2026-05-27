import Testing
import Foundation
@testable import weedlabel

@Suite("ProductLinks")
struct ProductLinksTests {

    static func label(qrCodes: [String], cultivator: String = "Test Co") -> CannabisLabel {
        CannabisLabel(
            strainName: "X", cultivator: cultivator,
            licenseNumber: nil, metrcTag: nil, netWeight: nil,
            harvestDate: nil, expirationDate: nil,
            productType: .flower,
            thca: nil, delta9thc: nil, cbd: nil, cbg: nil,
            totalCannabinoids: nil, totalThc: nil, totalCbd: nil,
            myrcene: nil, limonene: nil, linalool: nil,
            betaCaryophyllene: nil, pinene: nil, humulene: nil,
            totalTerpenes: nil,
            qrCodes: qrCodes
        )
    }

    // MARK: - URL normalization

    @Test func normalizesUppercaseScheme() {
        // Real device payload had uppercase HTTPS.
        let url = ProductLinks.normalizedURL("HTTPS://1A4.COM/13U2HFO28YBVINXS6L3OXZ")
        #expect(url != nil)
        #expect(url?.scheme == "https")
        // Path case is preserved.
        #expect(url?.absoluteString.contains("13U2HFO28YBVINXS6L3OXZ") == true)
    }

    @Test func acceptsLowercaseHttp() {
        #expect(ProductLinks.normalizedURL("http://example.com/coa") != nil)
    }

    @Test func rejectsNonURLPayload() {
        // Metrc tags are not URLs.
        #expect(ProductLinks.normalizedURL("1A4110300003C8D000041730") == nil)
        #expect(ProductLinks.normalizedURL("just some text") == nil)
    }

    @Test func trimsWhitespace() {
        #expect(ProductLinks.normalizedURL("  https://example.com  ") != nil)
    }

    // MARK: - Cultivator search

    @Test func buildsEncodedSearchURL() {
        let url = ProductLinks.searchURL(forCultivator: "Fresh Grow LLC")
        #expect(url != nil)
        let s = url!.absoluteString
        #expect(s.hasPrefix("https://duckduckgo.com/?q="))
        // Spaces encoded.
        #expect(!s.contains(" "))
        #expect(s.contains("cannabis"))
    }

    // MARK: - Aggregate links

    @Test func surfacesLabelURLAndSearch() {
        let lbl = Self.label(
            qrCodes: ["1A4110300003C8D000041730", "HTTPS://1A4.COM/ABC123"],
            cultivator: "Kynd"
        )
        let links = ProductLinks.links(for: lbl)
        // One label link (the URL QR; the Metrc tag is skipped) + one search.
        #expect(links.contains { $0.kind == .labelLink })
        #expect(links.contains { $0.kind == .search })
        #expect(links.filter { $0.kind == .labelLink }.count == 1)
    }

    @Test func noLabelLinkWhenNoURLPayload() {
        let lbl = Self.label(qrCodes: ["1A4110300003C8D000041730"], cultivator: "Kynd")
        let links = ProductLinks.links(for: lbl)
        #expect(!links.contains { $0.kind == .labelLink })
        // Search link still offered.
        #expect(links.contains { $0.kind == .search })
    }

    @Test func dedupesIdenticalURLPayloads() {
        let lbl = Self.label(
            qrCodes: ["https://example.com/coa", "https://example.com/coa"],
            cultivator: "Kynd"
        )
        let links = ProductLinks.links(for: lbl)
        #expect(links.filter { $0.kind == .labelLink }.count == 1)
    }

    @Test func noSearchWhenCultivatorEmpty() {
        let lbl = Self.label(qrCodes: [], cultivator: "")
        let links = ProductLinks.links(for: lbl)
        #expect(links.isEmpty)
    }
}
