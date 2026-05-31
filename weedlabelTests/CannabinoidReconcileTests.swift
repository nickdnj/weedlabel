import Testing
@testable import weedlabel

// Cannabinoid reconciliation — the deterministic re-read of cannabinoid values
// straight from the OCR by printed label, which overrides the FM's slotting.
// These focus on the CLUSTERED two-column row regression (OI-2/OI-4): OCR
// row-grouping can emit a dense potency row as all labels first, then all
// values, which the per-label `valueAfter` window mis-pairs.

@Suite struct CannabinoidReconcileTests {

    /// A label seeded with the FM's *wrong* slotting, mirroring the on-device
    /// Kynd Jet Fuel trace (PRE-reconcile thca=25.74, d9=0, totalThc=0.87).
    private static func jetFuelMisSlotted() -> CannabisLabel {
        CannabisLabel(
            strainName: "Kynd Jet Fuel",
            cultivator: "Garden State Dispensary",
            licenseNumber: "C000067",
            metrcTag: nil,
            netWeight: "3.5g",
            harvestDate: nil,
            expirationDate: nil,
            productType: .flower,
            thca: 25.74,        // wrong — FM grabbed Total THC
            delta9thc: 0.0,
            cbd: nil,
            cbg: nil,
            totalCannabinoids: nil,
            totalThc: 0.87,     // wrong — FM grabbed D9-THC
            totalCbd: nil,
            myrcene: nil, limonene: nil, linalool: nil,
            betaCaryophyllene: nil, pinene: nil, humulene: nil,
            totalTerpenes: nil,
            qrCodes: []
        )
    }

    // The clustered potency row as it came off the device: D9-THC and THCa
    // labels first, then their two values. Total THC sits on the title line.
    private static let clusteredOCR = """
    Kynd Jet Fuel (S) Flower 3.5g  Total THC:  25.74%
    D9T HC:  THCa:  0.87%  28.36%
    CBG:  0.29
    CBD:  0.00%
    """

    @Test func clusteredRowPairsValuesPositionally() {
        var label = Self.jetFuelMisSlotted()
        label.reconcileCannabinoids(ocrText: Self.clusteredOCR)
        // THCa is the SECOND value in the cluster — the bug was it reading 0.87.
        #expect(label.thca == 28.36)
        #expect(label.delta9thc == 0.87)
        #expect(label.totalThc == 25.74)
        #expect(label.cbg == 0.29)
        #expect(label.cbd == 0.00)
    }

    // Clustered row PREFIXED by the chemotype descriptor ("High THC, Low CBD")
    // — the `cbd` in "Low CBD" must not be counted as a value label, or the
    // cluster fails to pair. Real device trace (Jet Fuel, second orientation).
    @Test func clusteredRowWithChemotypePrefixStillPairs() {
        var label = Self.jetFuelMisSlotted()
        label.reconcileCannabinoids(ocrText: """
        High THC, Low CBD  Total THC:  THCa:  25.74%  28.36%  Beta Mycene: 0.38 46
        D9T HC:  0.87 %
        CBG:  0.29%
        """)
        #expect(label.totalThc == 25.74)
        #expect(label.thca == 28.36)
        #expect(label.delta9thc == 0.87)
        #expect(label.cbg == 0.29)
    }

    // Cross-row column desync (Permanent Gas #15, real device trace): the potency
    // columns split across two rows so THCa's value lands beside Δ9, and valueAfter
    // grabbed the "9" inside "d9thc" for thca (=9.0). The fixes: valueAfter ignores
    // the token-internal digit, and fixImpossibleThc promotes the impossible Δ9
    // (28.2) back to THCa, anchored on Total THC.
    @Test func permanentGasCrossRowDesyncRecoversThca() {
        var label = Self.jetFuelMisSlotted()
        label.reconcileCannabinoids(ocrText: """
        Kynd Permanent Gas #15 (S) Flower 3.5g  Total THC:  25.08%  Limonene: 1.08
        High THC, Low CBD  THCa:  D9T HC:  28.20%  Beta lycene: 0.88
        Lic Number: C000067  Grow Method: Indoor  0.35 /  AlphaPinene: 0.16
        CBG:  0.59%
        """)
        label.fixImpossibleThc()
        #expect(label.thca == 28.2)
        #expect(label.delta9thc == nil)   // bogus 28.x nulled
        #expect(label.totalThc == 25.08)
    }

    // Lollipopz (real device trace): THCa's value (29.05) desynced onto the Δ9 row.
    @Test func lollipopzCrossRowDesyncRecoversThca() {
        var label = Self.jetFuelMisSlotted()
        label.reconcileCannabinoids(ocrText: """
        Kynd Lollipopz (l) Flower 3.5g  Limonene: 0.66
        High THC, Low CBD  Total THC:  THCa:  25.65%  Betacaryophyllene: 0.64
        Grow Method: Indoor  D9THC:  29.05%  0.17%  Beta Mycene: 0.17
        CBG:  0.35%
        """)
        label.fixImpossibleThc()
        #expect(label.thca == 29.05)
        #expect(label.delta9thc == nil)
    }

    // A correctly-read flower must be untouched by fixImpossibleThc (Δ9 plausible).
    @Test func fixImpossibleThcLeavesGoodFlowerAlone() {
        var label = Self.jetFuelMisSlotted()
        label.thca = 28.36; label.delta9thc = 0.87; label.totalThc = 25.74
        label.fixImpossibleThc()
        #expect(label.thca == 28.36)
        #expect(label.delta9thc == 0.87)
    }

    // Interleaved "label: value  label: value" rows must NOT be disturbed by the
    // clustered pairing — valueAfter already reads them correctly, and clustering
    // would mis-handle a terpene value sharing the row.
    @Test func interleavedRowUnchanged() {
        var label = Self.jetFuelMisSlotted()
        label.thca = nil; label.delta9thc = nil; label.totalThc = nil
        label.reconcileCannabinoids(ocrText: "THCa: 28.36%  Total THC: 25.74%")
        #expect(label.thca == 28.36)
        #expect(label.totalThc == 25.74)
    }

    // MARK: - Value pick-list (Phase 2 tap-to-correct)

    private static let cleanPotencyOCR = """
    Total THC:  25.74%
    THCa:  28.36%
    D9THC:  0.87%
    CBG:  0.29%
    CBD:  0.00%
    Limonene: 0.22%
    """

    @Test func candidateValuesForThcaBigFirst() {
        let vals = CannabisLabel.candidatePotencyValues(for: .thca, ocrText: Self.cleanPotencyOCR)
        #expect(vals.first == 28.36)            // direct read leads
        #expect(vals.contains(25.74))
    }

    @Test func candidateValuesForDelta9IncludesSmall() {
        let vals = CannabisLabel.candidatePotencyValues(for: .delta9thc, ocrText: Self.cleanPotencyOCR)
        #expect(vals.contains(0.87))
        #expect(vals.contains(0.29))
    }

    @Test func setCannabinoidUpdatesField() {
        var label = Self.jetFuelMisSlotted()
        label.setCannabinoid(.thca, 28.36)
        label.setCannabinoid(.delta9thc, nil)
        #expect(label.thca == 28.36)
        #expect(label.delta9thc == nil)
    }

    // A single cannabinoid label followed by an unrelated number (e.g. a license
    // number bleeding into a row-grouped line) must not be positionally paired —
    // the cluster needs ≥2 adjacent labels, so this falls through to valueAfter's
    // bounded window and stays nil rather than grabbing the license digits.
    @Test func singleLabelWithForeignNumberNotPaired() {
        var label = Self.jetFuelMisSlotted()
        label.delta9thc = nil
        label.reconcileCannabinoids(ocrText: "D9THC:  Lic Number: C000067")
        #expect(label.delta9thc == nil)
    }

    // Impossible-THCA recovery (beta, Kynd Mandarin Diesel): the label prints
    // "Δ9THC: 0.82%" and "Total THC: 28.47%", with the real THCA (31.53%) sitting
    // unlabeled by the Metrc tag. FM put 0.82 into `thca`; reconcile reads Total
    // THC correctly but finds no "THCA" token, leaving thca implausibly below
    // Total THC. The final consistency pass recovers it from the regulatory
    // formula Total THC = 0.877×THCA + Δ9.
    @Test func impossibleThcaRecoveredFromTotalThc() {
        var label = Self.jetFuelMisSlotted()
        label.thca = 0.82
        label.delta9thc = 0.82
        label.totalThc = 28.47
        label.reconcileCannabinoids(ocrText: "Total THC:  28.47%  09THC:  0.82%")
        #expect(label.thca == 31.53)   // (28.47 − 0.82) / 0.877
        #expect(label.totalThc == 28.47)
    }

    // The recovery must NOT fire when THCA is already consistent (≥ Total THC) —
    // the normal flower case. Don't rewrite good data.
    @Test func consistentThcaNotRewritten() {
        var label = Self.jetFuelMisSlotted()
        label.thca = 28.36
        label.delta9thc = 0.87
        label.totalThc = 25.74
        label.reconcileCannabinoids(ocrText: "Total THC:  25.74%")
        #expect(label.thca == 28.36)
    }
}
