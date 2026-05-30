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
}
