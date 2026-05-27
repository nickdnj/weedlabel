import Foundation

// ProductLinks — derives "learn more" links from the scanned label. Two
// sources, both reliable:
//   1. URL-bearing QR/barcode payloads (often a COA or producer info page).
//      These are literally on the label, so they're authoritative.
//   2. A web search for the cultivator name — works for any brand, no
//      maintenance, no guessing at domains.
//
// Opening a link hands off to Safari — the app itself makes no network calls,
// so this doesn't compromise the on-device processing claim.

struct ProductLink: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case labelLink, search }
    let id = UUID()
    let title: String
    let subtitle: String
    let url: URL
    let kind: Kind

    static func == (lhs: ProductLink, rhs: ProductLink) -> Bool {
        lhs.title == rhs.title && lhs.url == rhs.url && lhs.kind == rhs.kind
    }
}

enum ProductLinks {
    static func links(for label: CannabisLabel) -> [ProductLink] {
        var out: [ProductLink] = []

        // 1. URL payloads found in the QR/barcode set.
        for qr in label.qrCodes {
            guard let url = normalizedURL(qr) else { continue }
            // Avoid duplicate URLs.
            if out.contains(where: { $0.url == url }) { continue }
            out.append(ProductLink(
                title: "Label link",
                subtitle: url.host ?? url.absoluteString,
                url: url,
                kind: .labelLink
            ))
        }

        // 2. Web search for the cultivator.
        let cultivator = label.cultivator.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cultivator.isEmpty, let search = searchURL(forCultivator: cultivator) {
            out.append(ProductLink(
                title: "Search \(cultivator)",
                subtitle: "Find the producer online",
                url: search,
                kind: .search
            ))
        }

        return out
    }

    /// Parse a QR payload into an http(s) URL. Tolerates uppercase schemes
    /// (observed "HTTPS://1A4.COM/..." on real labels) by lowercasing only the
    /// scheme — path case is preserved since paths can be case-sensitive.
    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        guard let schemeRange = trimmed.range(of: "://") else { return nil }
        let scheme = trimmed[trimmed.startIndex..<schemeRange.lowerBound].lowercased()
        let rest = trimmed[schemeRange.lowerBound...]
        return URL(string: scheme + rest)
    }

    /// Build a web-search URL for the cultivator name. Appends "cannabis NJ"
    /// to bias results toward the dispensary product rather than unrelated
    /// businesses sharing the name.
    static func searchURL(forCultivator cultivator: String) -> URL? {
        let query = "\(cultivator) cannabis NJ"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://duckduckgo.com/?q=\(encoded)")
    }
}
