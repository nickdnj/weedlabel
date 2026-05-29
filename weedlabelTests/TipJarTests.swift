import Testing
import Foundation
@testable import weedlabel

// Covers the pure, deterministic parts of the tip jar. The StoreKit purchase
// flow itself isn't unit-testable without a StoreKitTest session on a host
// app/simulator — that's exercised live via TipJar.storekit in the run scheme.

@Suite("TipJar")
@MainActor
struct TipJarTests {

    @Test func threeTiersSmallestToLargest() {
        // The IDs are the contract shared by TipJar, TipJar.storekit, and
        // (eventually) App Store Connect. Order is load-bearing: the view sorts
        // products by price, and the emoji mapping assumes small→medium→large.
        #expect(TipJar.productIDs.count == 3)
        #expect(TipJar.productIDs[0].hasSuffix(".small"))
        #expect(TipJar.productIDs[1].hasSuffix(".medium"))
        #expect(TipJar.productIDs[2].hasSuffix(".large"))
    }

    @Test func productIDsAreUnique() {
        #expect(Set(TipJar.productIDs).count == TipJar.productIDs.count)
    }

    @Test func everyTierHasDistinctEmoji() {
        let emojis = TipJar.productIDs.map(TipJar.emoji(for:))
        #expect(Set(emojis).count == TipJar.productIDs.count)
        #expect(!emojis.contains("🎁")) // 🎁 is the unknown-ID fallback
    }

    @Test func unknownProductFallsBackToGiftEmoji() {
        #expect(TipJar.emoji(for: "com.demarconet.weedlabel.tip.bogus") == "🎁")
    }

    @Test func freshJarHasNotTipped() {
        // A jar with no recorded tips reports the not-yet-tipped state. (We read
        // the live count rather than mutate UserDefaults to avoid cross-test
        // pollution of standard defaults.)
        let jar = TipJar()
        #expect(jar.tipsGivenCount >= 0)
        #expect(jar.hasTippedBefore == (jar.tipsGivenCount > 0))
        #expect(jar.purchasingProductID == nil)
        #expect(jar.didJustTip == false)
    }
}
