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

    // MARK: - Real device leak cases (2026-05-30 batch)

    // Boilerplate fragment grabbed as strain: "DISEASE. T" off the disclaimer
    // "...prevent any disease." on a Zips Warheadz label.
    static let warheadzOCR = """
    Zips - warheadz  THCA: 21.74 %%  Potency Analysis: Terpene Contents -
    - 28g  THC:  22.18 %  Betacaryophyllene: 1.14 96
    High THC, Low CBD  THC9:  cBO:  3.11 %  0.17  BetaMyrcene: 0.37 9%6
    Inhalable Product  Store in a cool, dry place HQV:  0.00  Linaool: 0.31
    License #  C000186  CBD:  0.00  Humuiene: 0.26 %
    Phone #: (973) 400 - 0188  Bisabolol: 0.16
    Warheadz 7725F6  1A4110300003C8D000032417  Total Terpenes:  3.26%
    THIS STATEMENT HAS NOT BEEN
    diagnose, treat, cure, or prevent any disease. T
    """

    @Test func rejectsDiseaseDisclaimerFragment() {
        let r = StrainNameFixer.fix(strain: "DISEASE. T", cultivator: "Fresh Grow LLC", ocrText: Self.warheadzOCR)
        #expect(r.strain.lowercased() != "disease. t")
        #expect(r.strain.lowercased().contains("warheadz"))
    }

    // Metrc tag OCR'd contiguously as "1841103000003E9000067952" (1A4 -> 184),
    // so a leading "E9000067952" fragment survived on the name.
    @Test func stripsMetrcFragmentPrefix() {
        let ocr = "1841103000003E9000067952  Kynd Jet Fuel (S) Flower 3.5g  Total THC:  25.74%"
        let r = StrainNameFixer.fix(strain: "E9000067952  Kynd Jet Fuel (S)", cultivator: "Garden State Dispensary", ocrText: ocr)
        #expect(!r.strain.contains("9000067952"))
        #expect(r.strain.lowercased().contains("jet fuel"))
    }

    // Pure hallucination: OCR clearly says Kynd Lollipopz; FM emitted the @Guide
    // example "Blue Candy Rain" (none of those tokens are on the label).
    static let lollipopzOCR = """
    1A41103000003E9000063920  Kynd Lollipopz (1) Flower 3.5g  Total THC:  25.65%  Limonene: 0.06 40
    Grow Method: Indoor  High THC, Low CBD  TH Ca:  29.05 %  Betacaryophyllene: 0.64
    LIC Number: C000067  D9THC:  CBD:  0.00 %  0.17%  Humulene: 0.14
    950 US Highway 1 North  Garden State Dispensary  CBN:  0.00 %  BetaPinene: 0.08
    Woodbridge NJ. 07095  (848) 939-2005  CBG:  0.35
    NOT SAFE FOR KIDS
    """

    @Test func rejectsHallucinatedCanaryName() {
        let r = StrainNameFixer.fix(strain: "Blue Candy Rain", cultivator: "Garden State Dispensary", ocrText: Self.lollipopzOCR)
        #expect(r.strain.lowercased() != "blue candy rain")
        #expect(r.strain.lowercased().contains("lollipopz"))
    }

    // Same hallucination but with the brand ("Kynd") as the extracted cultivator —
    // the recovered "Kynd Lollipopz" must not be rejected for containing the brand.
    @Test func rejectsHallucinatedCanaryNameWithBrandCultivator() {
        let r = StrainNameFixer.fix(strain: "Blue Candy Rain", cultivator: "Kynd", ocrText: Self.lollipopzOCR)
        #expect(r.strain.lowercased() != "blue candy rain")
        #expect(r.strain.lowercased().contains("lollipopz"))
    }

    // OCR double-spacing must not defeat boilerplate matching: "THIS  PRODUCT
    // IS NOT INTEN" (two spaces) still contains the "this product" marker.
    @Test func rejectsDoubleSpacedBoilerplate() {
        #expect(StrainNameFixer.isBoilerplateLine("THIS  PRODUCT IS NOT INTEN"))
        let r = StrainNameFixer.fix(strain: "THIS  PRODUCT IS NOT INTEN", cultivator: "Fresh Grow LLC", ocrText: Self.warheadzOCR)
        #expect(!r.strain.lowercased().contains("product is not"))
        #expect(r.strain.lowercased().contains("warheadz"))
    }

    // The lone chemotype qualifier "High" (off "High THC, Low CBD") is never a strain.
    @Test func rejectsBareChemotypeQualifier() {
        #expect(StrainNameFixer.isChemotypeQualifierOnly("High"))
        #expect(StrainNameFixer.isChemotypeQualifierOnly("Low CBD"))
        #expect(!StrainNameFixer.isChemotypeQualifierOnly("Highlighter"))
        let r = StrainNameFixer.fix(strain: "High", cultivator: "Garden State Dispensary", ocrText: Self.lollipopzOCR)
        #expect(r.strain.lowercased() != "high")
        #expect(r.strain.lowercased().contains("lollipopz"))
    }

    // Stylized-logo OCR garbage on the first line ("BLO НАЧАААА…") must be
    // skipped so recovery reaches the real "Zips - Warheadz" on the next line.
    static let warheadzLogoGarbageOCR = """
    BLO НАЧАААААААААААААААААААААААААААААААА
    Zips - Warheadz  THCA: 21.74 0%  Potency Analysis:  Terpene Contents -
    - 28g  THC:  22.18%0  BetaCaryophyllene: 1.14 00
    License #  C000186  CBD:  0.00 %
    """

    @Test func skipsStylizedLogoGibberish() {
        #expect(StrainNameFixer.isGibberish("BLO НАЧАААААААААААА"))
        #expect(!StrainNameFixer.isGibberish("Zips - Warheadz"))
        #expect(!StrainNameFixer.isGibberish("Kynd Lollipopz (I)"))
        let cand = StrainNameFixer.candidateFromOCR(Self.warheadzLogoGarbageOCR, cultivator: "Fresh Grow LLC")
        #expect(cand?.lowercased().contains("warheadz") == true)
        #expect(cand?.lowercased().contains("нача") != true)
    }

    // MARK: - candidateNames (tap-to-pick correction list)

    // The exact device OCR where auto-extraction grabbed "AN": the picker list
    // must surface the real "Zips - warheadz" at the TOP, past the junk lines.
    static let warheadzGarbageTopOCR = """
    AN
    H-HM
    Zips - warheadz  THCA: 21.74 96  Potency Analysis:  Terpene Contents -
    - 28g  THC:  22.18 %  BetaCaryophyllene: 1.14 96
    High THC, LOW CBD  THC9:  CBO:  3.11  0.17  BetaMyrcene: 0.37 %
    Inhalable Product  Store in a cool, dry place
    License #  C000186
    Fresh Grow LLC.  15 World's Fair Drive
    """

    @Test func candidateNamesSurfacesRealNameTop() {
        let names = StrainNameFixer.candidateNames(ocrText: Self.warheadzGarbageTopOCR, cultivator: "Fresh Grow LLC")
        #expect(!names.isEmpty)
        #expect(names.first?.lowercased().contains("warheadz") == true)
        // The 2-char specks must not appear at all.
        #expect(!names.contains { $0.lowercased() == "an" })
    }

    // The real device case: the picker offered "Warheadz 7725F6 Tota Terpenes:
    // 3.26" and the user had to re-correct to "Warheadz". Now the lot code +
    // trailing junk are trimmed so a clean "Warheadz" is offered directly.
    @Test func candidateNamesTrimsLotCodeAndJunk() {
        let ocr = """
        Warheadz 7725F6  Tota Terpenes: 3.26%  25.16 %
        Fresh Grow LLC.  15 World's Fair Drive
        """
        let names = StrainNameFixer.candidateNames(ocrText: ocr, cultivator: "Fresh Grow LLC")
        #expect(names.contains("Warheadz"))
        #expect(!names.contains { $0.contains("7725") || $0.lowercased().contains("terpenes") })
    }

    // Variant tags must survive trimming — "#15" and "(S)" are part of the name.
    @Test func candidateNamesKeepsVariantTags() {
        let ocr = "1A41103000003E9000066335  Kynd Permanent Gas #15 (S) Flower 3.5g  Total THC: 25.08%"
        let names = StrainNameFixer.candidateNames(ocrText: ocr, cultivator: "Garden State Dispensary")
        #expect(names.contains { $0.contains("Permanent Gas #15") })
    }

    @Test func candidateNamesRanksClutteredJetFuel() {
        // Jet Fuel name fused into the cluttered top row → still listed.
        let names = StrainNameFixer.candidateNames(ocrText: Self.jetFuelClutteredOCR, cultivator: "Garden State Dispensary")
        #expect(names.contains { $0.lowercased().contains("jet fuel") })
    }

    @Test func candidateNamesDedupesAndCaps() {
        let names = StrainNameFixer.candidateNames(ocrText: Self.lollipopzOCR, cultivator: "Kynd", limit: 6)
        #expect(names.count <= 6)
        #expect(Set(names.map { $0.lowercased() }).count == names.count)   // no dupes
        #expect(names.contains { $0.lowercased().contains("lollipopz") })
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
