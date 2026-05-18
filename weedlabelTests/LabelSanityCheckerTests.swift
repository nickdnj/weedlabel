import Testing
@testable import weedlabel

// LabelSanityChecker tests — productType-aware out-of-distribution rules.
// These validate the regulatory thresholds before FM ever runs on a real label.

@Suite struct LabelSanityCheckerTests {

    // MARK: - Fixtures

    /// Zips Blue Candy Rain canonical canary, as printed.
    static let zips = CannabisLabel(
        strainName: "Blue Candy Rain",
        cultivator: "Fresh Grow LLC",
        licenseNumber: "C000186",
        metrcTag: "1A4010300000000000000001",
        batchOrLot: nil,
        netWeight: "28.35g",
        harvestDate: "2025-12-10",
        expirationDate: "2027-12-10",
        productType: .flower,
        cannabinoids: Cannabinoids(
            thca: 29.73,
            delta9thc: 1.45,
            cbd: nil,
            cbda: nil,
            cbg: 0.49,
            cbga: nil,
            totalCannabinoids: 32.25,
            totalThc: nil,
            totalCbd: nil
        ),
        terpenes: Terpenes(
            myrcene: 1.83,
            limonene: 0.84,
            linalool: 0.84,
            betaCaryophyllene: 0.44,
            pinene: nil,
            humulene: nil,
            other: [],
            total: 5.03
        ),
        growthMethod: .indoor,
        qrCodes: ["https://example.com/coa/abc"]
    )

    // MARK: - Happy path

    @Test func zipsCanaryPasses() {
        let v = LabelSanityChecker.check(Self.zips)
        guard case .ok = v else {
            Issue.record("Expected .ok, got \(v)")
            return
        }
    }

    // MARK: - Cannabinoid ceilings

    @Test func flowerOver40FlagsVerify() {
        var bad = Self.zips
        bad.cannabinoids.totalCannabinoids = 50.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for flower at 50% total")
        }
    }

    @Test func concentrateAt80IsOk() {
        var concentrate = Self.zips
        concentrate.productType = .concentrate
        concentrate.cannabinoids.totalCannabinoids = 80.0
        if case .verifyHint(let r) = LabelSanityChecker.check(concentrate) {
            // Allowed reasons: terpene-related or date-related, NOT total-cannabinoid
            #expect(!r.contains("total cannabinoids"))
        }
    }

    @Test func concentrateOver99FlagsVerify() {
        var bad = Self.zips
        bad.productType = .concentrate
        bad.cannabinoids.totalCannabinoids = 105.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for concentrate at 105%")
        }
    }

    // MARK: - Terpene rules

    @Test func singleTerpeneOver5Flags() {
        var bad = Self.zips
        bad.terpenes.myrcene = 6.5
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for myrcene at 6.5%")
        }
    }

    @Test func totalTerpenesOver8Flags() {
        var bad = Self.zips
        bad.terpenes.total = 12.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for total terpenes at 12%")
        }
    }

    @Test func namedSumExceedingTotalFlags() {
        var bad = Self.zips
        bad.terpenes.total = 1.0  // declared total way under named sum
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint when named terpenes exceed declared total")
        }
    }

    // MARK: - Date sanity

    @Test func invertedDatesFlag() {
        var bad = Self.zips
        bad.harvestDate = "2025-12-10"
        bad.expirationDate = "2025-06-10"
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for inverted dates")
        }
    }

    // MARK: - Total THC formula (NJAC §17:30-16.3(b)(9)(ii)(1))

    @Test func mismatchedTotalTHCFlags() {
        // THCA 29.73 × 0.877 + 1.45 = 27.51, but printed says 30 → mismatch
        var bad = Self.zips
        bad.cannabinoids.totalThc = 30.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for printed Total THC mismatching computed")
        }
    }

    @Test func matchingTotalTHCPasses() {
        // THCA 29.73 × 0.877 + 1.45 = 27.5147... within tolerance
        var label = Self.zips
        label.cannabinoids.totalThc = 27.51
        let v = LabelSanityChecker.check(label)
        // May pass or hit a different rule — but should NOT fire on Total THC mismatch
        if case .verifyHint(let r) = v {
            #expect(!r.contains("Total THC"))
        }
    }

    // MARK: - Computed totals

    @Test func computedTotalThcOnZips() {
        let computed = Self.zips.computedTotalThc
        #expect(computed != nil)
        let expected = 29.73 * 0.877 + 1.45
        #expect(abs((computed ?? 0) - expected) < 0.01)
    }

    @Test func chemotypeOnZipsIsHighThc() {
        // Total THC ≈ 27.5, no CBD declared → ratio is +∞ → high THC, low CBD
        let chemo = Self.zips.chemotype
        #expect(chemo == .highThcLowCbd)
    }

    @Test func highPotencyAt40Plus() {
        var hot = Self.zips
        hot.cannabinoids.thca = 47.0
        hot.cannabinoids.delta9thc = 2.0
        // 47 * 0.877 + 2 = 43.22 → > 40 → high potency
        #expect(hot.isHighPotency)
    }

    @Test func zipsNotHighPotency() {
        // 27.5 < 40
        #expect(!Self.zips.isHighPotency)
    }
}
