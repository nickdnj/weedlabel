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
        netWeight: "28.35g",
        harvestDate: "2025-12-10",
        expirationDate: "2027-12-10",
        productType: .flower,
        thca: 29.73,
        delta9thc: 1.45,
        cbd: nil,
        cbg: 0.49,
        totalCannabinoids: 32.25,
        totalThc: nil,
        totalCbd: nil,
        myrcene: 1.83,
        limonene: 0.84,
        linalool: 0.84,
        betaCaryophyllene: 0.44,
        pinene: nil,
        humulene: nil,
        totalTerpenes: 5.03,
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
        bad.totalCannabinoids = 50.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for flower at 50% total")
        }
    }

    @Test func concentrateAt80IsOk() {
        var concentrate = Self.zips
        concentrate.productType = .concentrate
        concentrate.totalCannabinoids = 80.0
        if case .verifyHint(let r) = LabelSanityChecker.check(concentrate) {
            // Allowed reasons: terpene-related or date-related, NOT total-cannabinoid
            #expect(!r.contains("total cannabinoids"))
        }
    }

    @Test func concentrateOver99FlagsVerify() {
        var bad = Self.zips
        bad.productType = .concentrate
        bad.totalCannabinoids = 105.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for concentrate at 105%")
        }
    }

    // MARK: - Terpene rules

    @Test func singleTerpeneOver5Flags() {
        var bad = Self.zips
        bad.myrcene = 6.5
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for myrcene at 6.5%")
        }
    }

    @Test func totalTerpenesOver8Flags() {
        var bad = Self.zips
        bad.totalTerpenes = 12.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for total terpenes at 12%")
        }
    }

    @Test func namedSumExceedingTotalFlags() {
        var bad = Self.zips
        bad.totalTerpenes = 1.0  // declared total way under named sum
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
        bad.totalThc = 30.0
        if case .ok = LabelSanityChecker.check(bad) {
            Issue.record("Expected .verifyHint for printed Total THC mismatching computed")
        }
    }

    @Test func totalThcMismatchSurfacedBeforeTerpeneSum() {
        // Regression: a label with BOTH a Total THC mismatch AND a terpene-sum
        // problem should surface the Total THC mismatch first — it's more
        // diagnostic for the user. (Observed device case: terpene sum fired
        // first, hiding the bigger Total THC issue.)
        var bad = Self.zips
        bad.totalThc = 0.64                 // wildly wrong (should be ~27.5)
        bad.totalTerpenes = 0.91            // also broken (named sum > total)
        let v = LabelSanityChecker.check(bad)
        guard case .verifyHint(let reason) = v else {
            Issue.record("expected verifyHint, got \(v)")
            return
        }
        #expect(reason.contains("Total THC"), "expected Total THC reason, got: \(reason)")
    }

    @Test func matchingTotalTHCPasses() {
        // THCA 29.73 × 0.877 + 1.45 = 27.5147... within tolerance
        var label = Self.zips
        label.totalThc = 27.51
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
        hot.thca = 47.0
        hot.delta9thc = 2.0
        // 47 * 0.877 + 2 = 43.22 → > 40 → high potency
        #expect(hot.isHighPotency)
    }

    @Test func zipsNotHighPotency() {
        // 27.5 < 40
        #expect(!Self.zips.isHighPotency)
    }

    // MARK: - THC post-fix (delta9thc vs totalThc swap)

    @Test func postFixSwapsObviouslyMisassignedDelta9() {
        // FM put 27.52 (the printed Total THC) into delta9thc — implausibly
        // high for actual Δ9-THC, which is rarely above 5% on flower.
        var label = Self.zips
        label.delta9thc = 27.52
        label.totalThc = nil
        label.fixSwappedThcFields()
        #expect(label.delta9thc == nil)
        #expect(label.totalThc == 27.52)
    }

    @Test func postFixLeavesPlausibleDelta9Alone() {
        // Actual Δ9-THC value (1.45%) — should not be moved.
        var label = Self.zips
        label.delta9thc = 1.45
        label.totalThc = nil
        label.fixSwappedThcFields()
        #expect(label.delta9thc == 1.45)
        #expect(label.totalThc == nil)
    }

    @Test func postFixLeavesBothAloneIfTotalAlreadyLarger() {
        // Both values are set and Total THC is the larger one — model got it
        // right, leave alone even if delta9thc looks high.
        var label = Self.zips
        label.delta9thc = 15.0
        label.totalThc = 28.0
        label.fixSwappedThcFields()
        #expect(label.delta9thc == 15.0)
        #expect(label.totalThc == 28.0)
    }

    @Test func postFixSwapsThcaAndTotalThcWhenReversed() {
        // FM put "Total THC: 25.65" into thca and "THCA: 29.05" into totalThc.
        // Real labels have THCA > Total THC because Total THC = 0.877×THCA + Δ9-THC.
        var label = Self.zips
        label.thca = 25.65    // actually the printed Total THC
        label.totalThc = 29.05 // actually the printed THCA
        label.delta9thc = nil  // avoid delta9 path interfering
        label.fixSwappedThcFields()
        #expect(label.thca == 29.05)
        #expect(label.totalThc == 25.65)
    }

    @Test func postFixLeavesThcaAndTotalThcAloneOnConcentrate() {
        // Concentrates can have Total THC > THCA due to decarboxylation.
        // Don't apply the swap on non-flower product types.
        var label = Self.zips
        label.productType = .concentrate
        label.thca = 25.0
        label.totalThc = 65.0
        label.delta9thc = nil
        label.fixSwappedThcFields()
        #expect(label.thca == 25.0)
        #expect(label.totalThc == 65.0)
    }
}

// MARK: - Empty-chemistry fallback message

@Suite("SummaryFallback")
struct SummaryFallbackTests {
    static func bareLabel(strain: String = "Mystery") -> CannabisLabel {
        CannabisLabel(
            strainName: strain, cultivator: "Y",
            licenseNumber: nil, metrcTag: nil, netWeight: nil,
            harvestDate: nil, expirationDate: nil,
            productType: .flower,
            thca: nil, delta9thc: nil, cbd: nil, cbg: nil,
            totalCannabinoids: nil, totalThc: nil, totalCbd: nil,
            myrcene: nil, limonene: nil, linalool: nil,
            betaCaryophyllene: nil, pinene: nil, humulene: nil,
            totalTerpenes: nil,
            qrCodes: []
        )
    }

    @Test func emptyEverythingNamesProductAndStaysHonest() {
        // No insight, no chemistry — still names the product, no fake numbers.
        let text = SummaryService.buildFallback(Self.bareLabel(strain: "Mystery"))
        #expect(text.contains("Mystery"))
        #expect(text.lowercased().contains("legible"))
        #expect(!text.contains("%")) // no fabricated percentages
    }

    @Test func leansOnStrainInsightWhenChemistryEmpty() {
        // The "infer from the name" win: with an insight but no chemistry, the
        // fallback should describe character + classification, not go blank.
        let insight = StrainInsight(lean: .indica, source: .lineage("kush"))
        let text = SummaryService.buildFallback(Self.bareLabel(strain: "Bubba Kush"), strainInsight: insight)
        #expect(text.contains("Bubba Kush"))
        #expect(text.lowercased().contains("indica"))
        // Character note from the "kush" lineage should appear.
        #expect(text.lowercased().contains("earthy"))
        #expect(!text.contains("%"))
    }

    @Test func includesChemistryHighlightsWhenPresent() {
        var lbl = Self.bareLabel(strain: "Test")
        lbl.thca = 24.0
        lbl.limonene = 1.2
        let insight = StrainInsight(lean: .hybrid, source: .printedMarker)
        let text = SummaryService.buildFallback(lbl, strainInsight: insight)
        #expect(text.contains("THCA 24.00%"))
        #expect(text.lowercased().contains("limonene"))
    }
}
