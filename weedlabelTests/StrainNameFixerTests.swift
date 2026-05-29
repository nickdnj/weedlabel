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
