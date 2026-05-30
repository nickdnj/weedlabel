import Testing
import Foundation
@testable import weedlabel

@Suite("StrainNameFixer")
struct StrainNameFixerTests {

    // MARK: - Suspicious-name detection

    @Test func detectsTerpeneNameAsSuspicious() {
        #expect(StrainNameFixer.isSuspicious("Limonene"))
        #expect(StrainNameFixer.isSuspicious("BetaCaryophyllene"))
        #expect(StrainNameFixer.isSuspicious("Myrcene"))
    }

    @Test func detectsCannabinoidNameAsSuspicious() {
        #expect(StrainNameFixer.isSuspicious("THCA"))
        #expect(StrainNameFixer.isSuspicious("CBD"))
        #expect(StrainNameFixer.isSuspicious("Delta-9-THC"))
    }

    @Test func detectsSectionHeaderAsSuspicious() {
        #expect(StrainNameFixer.isSuspicious("Total THC"))
        #expect(StrainNameFixer.isSuspicious("Potency Analysis"))
    }

    @Test func realStrainNamesNotSuspicious() {
        #expect(!StrainNameFixer.isSuspicious("Blue Candy Rain"))
        #expect(!StrainNameFixer.isSuspicious("Kynd Lollipopz"))
        #expect(!StrainNameFixer.isSuspicious("Northern Lights"))
        #expect(!StrainNameFixer.isSuspicious("Caramel Gelato"))
    }

    @Test func caseInsensitive() {
        #expect(StrainNameFixer.isSuspicious("limonene"))
        #expect(StrainNameFixer.isSuspicious("LIMONENE"))
        #expect(StrainNameFixer.isSuspicious(" Limonene "))
    }

    // MARK: - OCR candidate extraction

    @Test func picksFirstTextyLineFromOCR() {
        let ocr = """
        Kynd Lollipopz (I) Flower 3.5g
        1A41103000003E9000064032
        Limonene: 0.85%
        """
        let cand = StrainNameFixer.candidateFromOCR(ocr)
        // Should strip the " Flower 3.5g" weight suffix
        #expect(cand == "Kynd Lollipopz (I)")
    }

    // Real on-device capture (Jet Fuel, 2026-05-30): row-grouped OCR merged the
    // strain name into the top row with the Metrc tag, Total THC, and terpenes,
    // and the model picked the bold "NOT SAFE FOR KIDS" warning as the strain.
    // The fixer must (a) reject the warning and (b) salvage "Kynd Jet Fuel" from
    // the cluttered top row rather than fall back to the warning line.
    static let jetFuelClutteredOCR = """
    1A41103000003E9000067952  Kynd Jet Fuel (S) Flower 3.5g  Total THC:  25.74%  Terpinolene: 0.76 46  Beta Marcene: 0.38 5b
    High THC, Low CBD  THCa:  28.36  Betacano phyllene: 0.36 40  Limonene: 0.32 40
    Lic Number: C000067  Grow Method: Indoor  D9THC:  0.87  0.00%  Lina 1001: 0.14 4t  getaPinene: 0.12 8b
    Garden State Dispensary  CBN:  CBD:  0.00  AlphaPinene: 0.09 46
    950 US Highway 1 North  CBG:  0.29%  Bisa Dolol: 0.08 46  Humulene: 0.09 40
    Woodbridge NJ. 07095  (848) 999-2005
    PKG Date:  04/28/2026  Drug Administration. This product is not intended to
    EXP Date:  10/25/2026  diagnose, treat, cure, or prevent any disease.
    Requires Refrigeration: No  inactive ingredients: None
    Pesticides Used: None
    NOT SAFE FOR KIDS
    """

    @Test func rejectsNotSafeForKidsWarningAsStrain() {
        #expect(StrainNameFixer.isBoilerplateLine("NOT SAFE FOR KIDS"))
        let result = StrainNameFixer.fix(
            strain: "NOT SAFE FOR KIDS",
            cultivator: "Garden State Dispensary",
            ocrText: Self.jetFuelClutteredOCR
        )
        #expect(result.didFix)
        #expect(result.strain.lowercased().contains("jet fuel"))
        #expect(!result.strain.lowercased().contains("safe for kids"))
    }

    @Test func salvagesNameFromClutteredTopRow() {
        // candidateFromOCR alone (every line is metrc/value/boilerplate) must
        // still recover the leading name segment from the top row.
        let cand = StrainNameFixer.candidateFromOCR(Self.jetFuelClutteredOCR, cultivator: "Garden State Dispensary")
        #expect(cand != nil)
        #expect(cand?.lowercased().contains("jet fuel") == true)
    }

    @Test func skipsMetrcTagLine() {
        let ocr = """
        1A41103000003E9000064032
        Kynd Caramel Gelato Flower 3.5g
        """
        let cand = StrainNameFixer.candidateFromOCR(ocr)
        #expect(cand == "Kynd Caramel Gelato")
    }

    @Test func skipsLicenseLine() {
        let ocr = """
        License # C000186
        Blue Candy Rain
        """
        let cand = StrainNameFixer.candidateFromOCR(ocr)
        #expect(cand == "Blue Candy Rain")
    }

    @Test func skipsDateLine() {
        let ocr = """
        07/25/2026
        Harvest Date: 12/10/2025
        Zips Blue Candy Rain
        """
        let cand = StrainNameFixer.candidateFromOCR(ocr)
        #expect(cand == "Zips Blue Candy Rain")
    }

    @Test func skipsAddressLine() {
        let ocr = """
        Garden State Dispensary
        950 US Highway 1 North
        Kynd Lollipopz Flower 3.5g
        """
        let cand = StrainNameFixer.candidateFromOCR(ocr)
        #expect(cand == "Kynd Lollipopz")
    }

    @Test func returnsNilWhenNothingLooksLikeAStrain() {
        let ocr = """
        1A4110300003C8D000041730
        License # C000186
        07/25/2026
        """
        let cand = StrainNameFixer.candidateFromOCR(ocr)
        #expect(cand == nil)
    }

    // MARK: - Fix integration

    @Test func fixReplacesLimoneneStrainWithFirstOcrLine() {
        let ocr = """
        Kynd Lollipopz (I) Flower 3.5g
        1A41103000003E9000064032
        Limonene: 0.85%
        """
        let result = StrainNameFixer.fix(strain: "Limonene", ocrText: ocr)
        #expect(result.didFix)
        #expect(result.strain == "Kynd Lollipopz (I)")
    }

    @Test func fixLeavesRealStrainAlone() {
        let ocr = """
        Blue Candy Rain
        1A4110300003C8D000041730
        """
        let result = StrainNameFixer.fix(strain: "Blue Candy Rain", ocrText: ocr)
        #expect(!result.didFix)
        #expect(result.strain == "Blue Candy Rain")
    }

    @Test func fixLeavesSuspiciousNameAloneWhenNoCandidate() {
        let ocr = """
        1A4110300003C8D000041730
        License # C000186
        """
        let result = StrainNameFixer.fix(strain: "Limonene", ocrText: ocr)
        // No candidate found → keep original (UI will still show "Limonene"
        // but that's the best we can do without a real strain in the OCR).
        #expect(!result.didFix)
        #expect(result.strain == "Limonene")
    }

    // MARK: - Chemical fragment heuristic (device case 2026-05-27)

    @Test func detectsOcrFragmentAdjacentToPercent() {
        // Real device case: model picked "Beicaropa" (an OCR fragment of
        // "BetaCaryophyllene") as the strain. It appears in the OCR right
        // next to a "0.64%" — a chemical fragment, not a strain.
        let ocr = """
        Krnd Lollipopz (I) Flower 3.5g
        25.65 % Beicaropa yuene: 0.64 96
        """
        #expect(StrainNameFixer.looksLikeChemicalFragment("Beicaropa", in: ocr))
    }

    @Test func fragmentFixReplacesWithFirstOcrLine() {
        let ocr = """
        Krnd Lollipopz (I) Flower 3.5g
        25.65 % Beicaropa yuene: 0.64 96
        """
        let result = StrainNameFixer.fix(strain: "Beicaropa", ocrText: ocr)
        #expect(result.didFix)
        #expect(result.strain == "Krnd Lollipopz (I)")
    }

    @Test func realStrainOnPercentLineNotMisidentified() {
        // Counter-case: a multi-word strain wouldn't normally be flagged
        // even if it appears on a percent line, because real strains rarely
        // sit immediately next to chemistry values. The heuristic caps name
        // length at 18 chars to be safe.
        let ocr = """
        Sherbet Cookies Flower 3.5g
        """
        // Sherbet Cookies = 15 chars; doesn't appear with a % anywhere → no flag.
        #expect(!StrainNameFixer.looksLikeChemicalFragment("Sherbet Cookies", in: ocr))
    }

    @Test func longStrainNotFlaggedEvenIfOnPercentLine() {
        // If a strain name is unusually long (>18 chars), don't flag — that's
        // the wrong shape for a chemical fragment OCR error.
        let ocr = """
        Some Long Strain Name 25%
        """
        #expect(!StrainNameFixer.looksLikeChemicalFragment("Some Long Strain Name", in: ocr))
    }

    // MARK: - Hallucinated-name detection (regurgitated @Guide example)
    // Device/harness case 2026-05-28: on labels it couldn't read, the model
    // stamped "Blue Candy Rain" (the example in the strainName @Guide) onto
    // unrelated products. A real name's words must appear somewhere on the label.

    @Test func absentNameDetectedAsHallucinated() {
        let ocr = """
        Panda Farms
        Sundae Driver
        Pre-Roll 1g
        THCA: 25.0%
        """
        #expect(StrainNameFixer.isAbsentFromOCR("Blue Candy Rain", in: ocr))
    }

    @Test func presentNameNotHallucinatedEvenWhenWrappedAcrossLines() {
        // The canary: the name is really on the label, split across two lines
        // with chemistry between. Token match must keep it.
        let ocr = """
        Zips - Blue Candy
        THCA: 29.73 %
        Rain - 28g
        """
        #expect(!StrainNameFixer.isAbsentFromOCR("Blue Candy Rain", in: ocr))
    }

    @Test func significantTokensDropFormWords() {
        let toks = StrainNameFixer.significantTokens("Kynd Caramel Gelato (H) Flower")
        #expect(toks.contains("caramel"))
        #expect(toks.contains("gelato"))
        #expect(!toks.contains("flower"))   // form word stripped
        #expect(!toks.contains("h"))         // <3 chars dropped
    }

    @Test func fixRecoversWhenNameIsHallucinated() {
        // "Blue Candy Rain" stamped on a Panda Farms pre-roll whose OCR contains
        // none of those words → drop the hallucination, recover from the label.
        let ocr = """
        Panda Farms
        Pre-Roll 1g
        1A4110300003C8D000041730
        THCA: 25.0%
        """
        let result = StrainNameFixer.fix(strain: "Blue Candy Rain", ocrText: ocr)
        #expect(result.didFix)
        #expect(result.strain != "Blue Candy Rain")
    }

    @Test func candidateSkipsChemotypeLine() {
        // The Garden Society tin recovered "Moderate THC, Moderate CBG" as a
        // strain. A potency/chemotype line must be skipped.
        let ocr = """
        High THC, Low CBD
        Wedding Cake
        3.5g
        """
        #expect(StrainNameFixer.candidateFromOCR(ocr) == "Wedding Cake")
    }

    @Test func candidateSkipsFormOnlyLine() {
        // "Gummies" / "Inhalable Product" are product forms, not strains.
        let ocr = """
        Inhalable Product
        Gummies
        Sour Watermelon
        """
        #expect(StrainNameFixer.candidateFromOCR(ocr) == "Sour Watermelon")
    }

    @Test func fixKeepsHallucinatedNameWhenNothingRecoverable() {
        // Absent from OCR, but the OCR is all metadata → no candidate → keep
        // original rather than blanking the field.
        let ocr = """
        1A4110300003C8D000041730
        License # C000186
        07/25/2026
        """
        let result = StrainNameFixer.fix(strain: "Blue Candy Rain", ocrText: ocr)
        #expect(!result.didFix)
        #expect(result.strain == "Blue Candy Rain")
    }
}
