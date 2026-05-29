import Foundation
import StoreKit

// TipJar — HighNotes' only monetization, and it's pure goodwill: "tip if you
// can, don't if you can't." Never a paywall (see the rebrand/monetization
// stance). Apple requires developer tips to be IAP consumables (App Review
// guideline 3.1.1), so even though the app is otherwise 100% on-device with no
// accounts, *this one flow* talks to the App Store. Nothing user-identifying
// leaves the phone — StoreKit owns the transaction; we only keep a local count
// of tips given so we can show a warm "you've chipped in before" state.
//
// Tiers are defined locally (`productIDs`) and mirrored by `TipJar.storekit` so
// the whole purchase flow runs in the simulator before these IDs are ever
// registered in App Store Connect. The `.storekit` file is wired into the run
// scheme via `project.yml` (storeKitConfiguration).

/// A single tip option, flattened from a StoreKit `Product` into just what the
/// UI renders. Keeping the view off `Product` directly makes it previewable and
/// lets the price/name/blurb come from StoreKit (localized) while the emoji is
/// ours. `id` is the product ID — the key back to the underlying `Product`.
struct TipTier: Identifiable, Equatable {
    let id: String
    let emoji: String
    let name: String
    let blurb: String
    let displayPrice: String
}

@Observable
@MainActor
final class TipJar {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    /// Product fetch status. The view switches on this.
    private(set) var loadState: LoadState = .loading

    /// Tip tiers to show, ordered cheapest → most generous.
    private(set) var tiers: [TipTier] = []

    /// The StoreKit products backing `tiers`, keyed by product ID, so a tapped
    /// tier can find its `Product` to purchase.
    private var products: [String: Product] = [:]

    /// Product ID of an in-flight purchase, so the view can spin only that row
    /// and disable the others. `nil` when idle.
    private(set) var purchasingProductID: String?

    /// Flipped true right after a successful tip — drives the thank-you state.
    /// The view clears it on dismiss / "you're welcome".
    private(set) var didJustTip = false

    /// Lifetime count of tips left from this device. Local-only; never synced.
    var tipsGivenCount: Int {
        UserDefaults.standard.integer(forKey: Self.tipsGivenKey)
    }
    var hasTippedBefore: Bool { tipsGivenCount > 0 }

    private static let tipsGivenKey = "highnotes.tipJar.tipsGiven.v1"

    /// The tier product IDs, smallest → largest. Must stay in sync with both
    /// `TipJar.storekit` and (eventually) the products created in App Store
    /// Connect — the IDs are the contract between all three.
    static let productIDs = [
        "com.demarconet.weedlabel.tip.small",
        "com.demarconet.weedlabel.tip.medium",
        "com.demarconet.weedlabel.tip.large",
    ]

    /// An emoji per tier, keyed by product ID so display order doesn't matter.
    /// Names/prices/descriptions come from StoreKit (localized); this is the
    /// one bit of flavor that isn't worth a round-trip to the store.
    static func emoji(for productID: String) -> String {
        switch productID {
        case productIDs[0]: return "🌱"
        case productIDs[1]: return "🌿"
        case productIDs[2]: return "💚"
        default: return "🎁"
        }
    }

    // `nonisolated(unsafe)` so the nonisolated `deinit` can cancel it; the
    // field is only ever written once in `init` and Task.cancel() is safe to
    // call from any context.
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init() {
        // Catch transactions that resolve out of band — e.g. an "Ask to Buy"
        // request a parent approves later. Direct `purchase()` results do NOT
        // come through here, so there's no double-finish with `tip(_:)`.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                self?.noteOutOfBandTip(transaction)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    /// Load the tip tiers. Called when the sheet appears; safe to call again to
    /// retry after a failure.
    func load() async {
        loadState = .loading

        #if DEBUG
        // `-TipJarSampleData` renders the tiers without StoreKit, so the sheet
        // can be screenshotted / previewed outside an Xcode run (where the
        // `.storekit` config isn't injected). Real runs ignore this.
        if CommandLine.arguments.contains("-TipJarSampleData") {
            tiers = Self.sampleTiers
            loadState = .loaded
            return
        }
        #endif

        do {
            let fetched = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            tiers = fetched.map { product in
                TipTier(
                    id: product.id,
                    emoji: Self.emoji(for: product.id),
                    name: product.displayName,
                    blurb: product.description,
                    displayPrice: product.displayPrice
                )
            }
            loadState = tiers.isEmpty
                ? .failed(message: "No tip options right now. Try again in a bit.")
                : .loaded
        } catch {
            loadState = .failed(message: "Couldn't reach the App Store. Try again in a bit.")
        }
    }

    /// Run the purchase for a tier. Consumables aren't restorable and don't grant
    /// entitlements — a tip is delivered the moment it's verified, then finished.
    func tip(_ tier: TipTier) async {
        guard purchasingProductID == nil else { return }

        guard let product = products[tier.id] else {
            #if DEBUG
            // Sample-data mode has no real Product — simulate success so the
            // thank-you state is reachable for previews/screenshots.
            if CommandLine.arguments.contains("-TipJarSampleData") { didJustTip = true }
            #endif
            return
        }

        purchasingProductID = tier.id
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // Unverified (failed App Store signature check) — don't count it.
                    return
                }
                recordTip()
                await transaction.finish()
                didJustTip = true
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // A failed purchase is a no-op: the tiers stay tappable so the
            // user can simply try again. Nothing to surface for a tip.
        }
    }

    #if DEBUG
    /// Stand-in tiers for previews/screenshots; mirror `TipJar.storekit`.
    static let sampleTiers: [TipTier] = [
        TipTier(id: productIDs[0], emoji: emoji(for: productIDs[0]),
                name: "A little love", blurb: "A little love for the dev who built this.", displayPrice: "$0.99"),
        TipTier(id: productIDs[1], emoji: emoji(for: productIDs[1]),
                name: "Good vibes", blurb: "Good vibes — thanks for keeping HighNotes going.", displayPrice: "$2.99"),
        TipTier(id: productIDs[2], emoji: emoji(for: productIDs[2]),
                name: "Big love", blurb: "Big love — this genuinely makes someone's day.", displayPrice: "$4.99"),
    ]
    #endif

    /// Dismiss the thank-you state (back to the tier list, or on sheet close).
    func clearThankYou() { didJustTip = false }

    private func recordTip() {
        UserDefaults.standard.set(tipsGivenCount + 1, forKey: Self.tipsGivenKey)
    }

    /// Count a tip that arrived via `Transaction.updates` (Ask-to-Buy approval,
    /// etc.) and that we know is a current, non-revoked purchase.
    private func noteOutOfBandTip(_ transaction: Transaction) {
        guard transaction.revocationDate == nil,
              Self.productIDs.contains(transaction.productID) else { return }
        recordTip()
    }
}
