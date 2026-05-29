import Testing
@testable import weedlabel

@Suite("OCRPreprocessor")
struct OCRPreprocessorTests {

    // MARK: - Percent-glyph noise

    @Test func replacesTrailing90WithPercent() {
        let input = "THCA: 29.73 90"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "THCA: 29.73%")
    }

    @Test func replacesTrailing00WithPercent() {
        let input = "Total THC: 27.52 00"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Total THC: 27.52%")
    }

    @Test func replacesTrailing06WithPercent() {
        let input = "CBD: 0.00 06"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "CBD: 0.00%")
    }

    @Test func replacesTrailing0PercentWithPercent() {
        let input = "Linalool: 0.84 0%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Linalool: 0.84%")
    }

    @Test func replacesDoublePercentWithPercent() {
        let input = "BetaMyrcene: 0.84 %%"
        let out = OCRPreprocessor.clean(input)
        // BetaMyrcene also gets terpene fix
        #expect(out.contains("0.84%"))
        #expect(!out.contains("%%"))
    }

    // MARK: - Terpene name fixes

    @Test func fixesBetataryophyllene() {
        let input = "Betataryophyllene: 0.44%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "BetaCaryophyllene: 0.44%")
    }

    @Test func fixesBisabolot() {
        let input = "Bisabolot: 0.00%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Bisabolol: 0.00%")
    }

    @Test func fixesLimoneneWithSpace() {
        let input = "Lim onene: 1.83%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Limonene: 1.83%")
    }

    @Test func fixesBetaMyrceneToHyphenated() {
        let input = "BetaMyrcene: 0.84%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Beta-Myrcene: 0.84%")
    }

    @Test func fixesAlphaPineneToHyphenated() {
        let input = "AlphaPinene: 0.13%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Alpha-Pinene: 0.13%")
    }

    // MARK: - Cannabinoid name fixes

    @Test func fixesCBOtoCBG() {
        let input = "CBO: 0.49%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "CBG: 0.49%")
    }

    @Test func fixesCBOAtoCBGA() {
        let input = "CBOA: 0.49%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "CBGA: 0.49%")
    }

    @Test func fixesTHC9toDelta9THC() {
        let input = "THC9: 1.45%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Delta-9-THC: 1.45%")
    }

    // MARK: - Negative cases (don't over-correct)

    @Test func doesNotMatchNonNumericPrefixedBy90() {
        let input = "Some text 9001 more"
        let out = OCRPreprocessor.clean(input)
        // "9001" is a multi-digit, "90" is consumed in the prefix → no change expected.
        #expect(out == input)
    }

    @Test func preservesPlainPercentValues() {
        let input = "Total: 32.25%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == input)
    }

    @Test func preservesUnrelatedThreeLetterAcronyms() {
        let input = "Vague text mentioning CBO Industries"
        let out = OCRPreprocessor.clean(input)
        // "CBO:" with colon is the substitution trigger; "CBO " without colon is left alone.
        #expect(out == input)
    }

    // MARK: - Per-line scoping (the percent fixes shouldn't touch lines that
    //         don't look like cannabinoid/terpene rows)

    @Test func doesNotCorruptNonCannabisLineWithNoiseLikeNumbers() {
        // A line with no cannabinoid/terpene keyword and a "XX YY" digit
        // sequence should pass through unchanged — this was a real risk in the
        // unscoped preprocessor.
        let input = "Batch 12 96 of 2025"
        let out = OCRPreprocessor.clean(input)
        #expect(out == input)
    }

    @Test func stripsAddressContainingNumbers() {
        // Updated 2026-05-27: addresses are now boilerplate that the
        // preprocessor strips entirely (regulatory content the FM doesn't
        // need). Originally this test was about NOT applying percent fixes to
        // address-shaped lines; now we drop the line outright.
        let input = "15 World's Fair Drive 96"
        let out = OCRPreprocessor.clean(input)
        #expect(out.isEmpty)
    }

    @Test func doesNotCorruptGenericLineContainingBareTotal() {
        // Regression: an earlier version used "total" as a bare keyword which
        // would have rewritten "Total memory: 4 96 GB" → "Total memory: 4% GB".
        // The scoped version uses "total cannabinoids" / "total terpenes" /
        // "total thc" / "total cbd" specifically.
        let input = "Total memory: 4 96 GB"
        let out = OCRPreprocessor.clean(input)
        #expect(out == input)
    }

    @Test func appliesToTotalThcLine() {
        // "Total THC" is now an explicit in-scope phrase (was previously caught
        // by the over-broad bare "total" keyword).
        let input = "Total THC: 27.52 00"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Total THC: 27.52%")
    }

    // MARK: - New device-OCR noise patterns (from real iPhone 16 captures)

    @Test func handlesGeSuffixAsPercent() {
        let input = "Beta-Pinene: 0.05 ge"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Beta-Pinene: 0.05%")
    }

    @Test func handlesForwardSlashSuffixAsPercent() {
        // "35.45 /" observed on Kynd label — the % glyph mis-read as /.
        let input = "Total THC: 35.45 /"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Total THC: 35.45%")
    }

    @Test func handles46SuffixAsPercent() {
        let input = "Beta Mycene: 1.52 46"
        let out = OCRPreprocessor.clean(input)
        // BetaMycene → Beta-Myrcene, then percent fix.
        #expect(out == "Beta-Myrcene: 1.52%")
    }

    @Test func fixesLineNumberOcrError() {
        let input = "Lie Number: C000067"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "License # C000067")
    }

    @Test func fixesThcaLowercaseRendering() {
        let input = "THCa: 32.22%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "THCA: 32.22%")
    }

    @Test func fixes09ThcOcrError() {
        let input = "09THC: 35.45%"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Delta-9-THC: 35.45%")
    }

    // MARK: - Boilerplate stripping

    @Test func stripsFdaDisclaimer() {
        let input = """
        THCA: 29.73%
        This statement has not been evaluated by the Food and Drug Administration.
        Linalool: 0.84%
        """
        let out = OCRPreprocessor.clean(input)
        #expect(!out.lowercased().contains("food and drug administration"))
        #expect(out.contains("THCA: 29.73%"))
        #expect(out.contains("Linalool: 0.84%"))
    }

    @Test func stripsPhoneNumber() {
        let input = """
        License # C000186
        Phone #: (973) 400-0188
        Metrc: 1A4...
        """
        let out = OCRPreprocessor.clean(input)
        #expect(!out.contains("(973)"))
        #expect(out.contains("License # C000186"))
    }

    @Test func stripsKeepOutOfReachWarning() {
        let input = """
        THC: 22%
        Keep out of reach of children
        Linalool: 0.5%
        """
        let out = OCRPreprocessor.clean(input)
        #expect(!out.lowercased().contains("keep out of reach"))
        #expect(out.contains("THC: 22%"))
    }

    @Test func stripsDoNotDriveWarning() {
        let input = """
        Do not drive a motor vehicle or operate heavy machinery while using this product
        Total Terpenes: 5.03%
        """
        let out = OCRPreprocessor.clean(input)
        #expect(!out.lowercased().contains("motor vehicle"))
        #expect(out.contains("Total Terpenes: 5.03%"))
    }

    @Test func preservesActualCannabinoidLinesWhenStrippingBoilerplate() {
        // Regression: make sure a line containing "100" or "21" or other
        // numbers that LOOK boilerplate-y but aren't, is preserved.
        let input = """
        THCA: 21.5%
        CBD: 1.0%
        """
        let out = OCRPreprocessor.clean(input)
        #expect(out.contains("THCA: 21.5%"))
        #expect(out.contains("CBD: 1.0%"))
    }

    // MARK: - Line dedup

    @Test func dedupRemovesIdenticalLines() {
        let input = """
        Kynd Caramel Gelato (H) Flower 3.5g
        1A4110...
        Kynd Caramel Gelato (H) Flower 3.5g
        """
        let out = OCRPreprocessor.dedupLines(input)
        let lines = out.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "Kynd Caramel Gelato (H) Flower 3.5g")
        #expect(lines[1] == "1A4110...")
    }

    @Test func dedupCaseAndWhitespaceInsensitive() {
        let input = """
        License # C000186
          license # c000186
        """
        let out = OCRPreprocessor.dedupLines(input)
        #expect(out.components(separatedBy: "\n").count == 1)
    }

    @Test func dedupPreservesEmptyLinesAsSeparators() {
        let input = """
        line A

        line A
        """
        let out = OCRPreprocessor.dedupLines(input)
        let lines = out.components(separatedBy: "\n")
        // line A, empty, (dup line A dropped)
        #expect(lines == ["line A", ""])
    }

    @Test func cleanAppliesDedupAfterStrip() {
        // The same regulatory boilerplate line shouldn't survive twice even if
        // somehow stripping missed one — and structured data appearing twice
        // (strain name on package + inventory tag) collapses.
        let input = """
        Kynd Caramel Gelato (H) Flower 3.5g
        1A4110300000001
        Kynd Caramel Gelato (H) Flower 3.5g
        1A4110300000002
        """
        let out = OCRPreprocessor.clean(input)
        let lines = out.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 3) // strain + 2 distinct Metrc tags
        #expect(lines.filter { $0.contains("Caramel Gelato") }.count == 1)
    }

    @Test func caramelGelatoDeviceCaptureShrinksBelowContextBudget() {
        // Captured from real iPhone 16 device 2026-05-27. Original failed FM
        // extraction at 4093 tokens (within 3 of the 4096 limit). After the
        // expanded boilerplate phrases + Guide tightening, this needs to drop
        // well under 1500 chars to leave safe headroom.
        let captured = """
        Kynd Caramel Gelato (H) Flower 3.5g
        Rackage
        1A41103000003E9000066676
        Inventory ID:
        Kynd Caramel Gelato (H) Flower 3.5g
        1A41103000003E9000066657
        High THC, Low CBD
        Grow Method: Indoor
        Lie Number.
        C000067
        Garden State Dispensary
        Woodbridge NJ.
        07095
        848) 999-2005
        PKG Date:
        04/09/2026
        EXP Date:
        10/06/2026
        Tiractione
        Se ving size: 10mg
        serings Per unit: 36
        Reta mutene: 1.5244
        32.22 ветаса портупеле: 0.82 мл
        35.45%
        Limonene
        32 46
        CBD:
        1.13%
        CBN:
        0.00 %
        0.06%
        CBG:
        0.00%
        AlonaPinana: 0.02 s
        canopylenexid: 0.02 44
        0.47%
        :0.00 40
        This product is not intended 1ol
        Tor use Dy adults 21
        Ider and not tor
        resale. Keep out of the reach of cailanen.
        There may De
        nealth risis associated breasteeding, or planning on
        not arive a motor venicle or operate neavy macninery
        » nile using this product, National Poison contol cente
        """
        let out = OCRPreprocessor.clean(captured)
        // Should be substantially smaller — boilerplate fragments removed.
        #expect(out.count < 700, "cleaned length was \(out.count); expected < 700")
        // Should drop the obvious regulatory fragments.
        #expect(!out.lowercased().contains("adults 21"))
        #expect(!out.lowercased().contains("poison"))
        #expect(!out.lowercased().contains("breast"))
        #expect(!out.lowercased().contains("machinery"))
        #expect(!out.lowercased().contains("motor v"))
        #expect(!out.lowercased().contains("serving size"))
        #expect(!out.lowercased().contains("per unit"))
        #expect(!out.contains("(848)"))
        #expect(!out.contains("848) 999"))
        // Should retain structured data.
        #expect(out.contains("Caramel Gelato"))
        #expect(out.contains("C000067"))
        #expect(out.contains("PKG Date:"))
        #expect(out.contains("EXP Date:"))
    }

    @Test func kyndLabelShrinksSignificantly() {
        // The Kynd Caramel Gelato label from device capture — 1455 chars of
        // OCR. After preprocessing it should drop the FDA disclaimer paragraph
        // plus warnings, shrinking enough to fit the FM 4096-token context
        // alongside the @Generable schema.
        let kynd = """
        Kynd Caramel Gelato (H) Flower 3.5g
        1A41103000003E9000066676
        Lic Number: C000067
        Garden State Dispensary
        950 US Highway 1 North
        Woodbridge NJ, 07095
        (848) 999-2005
        PKG Date: 04/09/2026
        EXP Date: 10/06/2026
        STORAGE: Store in cool, dry place.
        Total THC: 32.22%
        THCa: 35.45%
        09THC: 1.13%
        Beta Mycene: 1.52 46
        Limonene: 0.82%
        Linalool: 0.31%
        This statement has not been evaluated by the Food and Drug Administration.
        This product is not intended to diagnose, treat, cure, or prevent any disease.
        This product contains cannabis.
        This product is intended for use by adults 21 years of age or older and not for resale.
        Keep out of reach of children.
        There may be health risks associated with the consumption of this product, including for women who are pregnant, breastfeeding, or planning on becoming pregnant.
        Do not drive a motor vehicle or operate heavy machinery while using this product.
        National Poison Control Center (800) 222-1222.
        Directions: Light and inhale.
        NOT SAFE FOR KIDS
        """
        let out = OCRPreprocessor.clean(kynd)
        // Should be substantially shorter.
        #expect(out.count < kynd.count - 400)
        // Should retain the structured data.
        #expect(out.contains("Total THC: 32.22%"))
        #expect(out.contains("Beta-Myrcene: 1.52%"))
        #expect(out.contains("Limonene: 0.82%"))
        #expect(out.contains("License # C000067"))
        // Should drop the disclaimers.
        #expect(!out.lowercased().contains("evaluated"))
        #expect(!out.lowercased().contains("poison"))
        #expect(!out.contains("(848)"))
    }

    @Test func appliesToLinesContainingCannabinoidKeyword() {
        let input = "THCA: 29.73 90"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "THCA: 29.73%")
    }

    @Test func appliesToLinesContainingTerpeneKeyword() {
        let input = "Limonene: 0.84 96"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Limonene: 0.84%")
    }

    @Test func appliesToLinesContainingTotalKeyword() {
        let input = "Total Cannabinoids: 32.25 90"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "Total Cannabinoids: 32.25%")
    }

    @Test func appliesToStandaloneValueLines() {
        // The two-column Potency Analysis layout drops standalone value lines
        // like "0.49 06" with no keyword on the line itself. These should be
        // in-scope because the line consists only of a value + noise suffix.
        let input = "0.49 06"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "0.49%")
    }

    @Test func appliesToStandaloneValueWithDoubleDigit() {
        let input = "27.52 96"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "27.52%")
    }

    @Test func multilineScopingMixed() {
        // After the boilerplate-stripping pass, addresses are dropped entirely.
        // What remains: non-boilerplate non-keyword lines pass through
        // untouched, cannabinoid/terpene lines get percent-fixed.
        let input = """
        15 World's Fair Drive 96
        THCA: 29.73 90
        Random 12 00 here
        Limonene: 0.84 96
        """
        let out = OCRPreprocessor.clean(input)
        let lines = out.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "THCA: 29.73%")          // cannabinoid — fixed
        #expect(lines[1] == "Random 12 00 here")     // no keyword — untouched
        #expect(lines[2] == "Limonene: 0.84%")       // terpene — fixed
    }

    @Test func appliesNameFixesGloballyEvenOnNonScopedLine() {
        // Name fixes always apply since they're anchored substitutions.
        // Useful for the "Betataryophyllene" case where the OCR error becomes
        // a real terpene keyword AFTER the fix, bringing the line into scope.
        // (Note: a single " %" suffix is NOT a noise pattern — it's valid
        // formatting — so we don't strip the inner space.)
        let input = "Betataryophyllene: 0.44 %"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "BetaCaryophyllene: 0.44 %")
    }

    @Test func nameFixedLineGetsPercentFixesApplied() {
        // The chain we care about: an OCR-mangled terpene name turns into a
        // real keyword after the name fix, and THEN the percent fix kicks in
        // on the same line.
        let input = "Betataryophyllene: 0.44 90"
        let out = OCRPreprocessor.clean(input)
        #expect(out == "BetaCaryophyllene: 0.44%")
    }

    // MARK: - Combined canary substring

    @Test func cleansCanaryPotencyValues() {
        let input = """
        THCA: 29.73 90
        Total THC: 27.52 00
        CBD: 0.00 06
        """
        let out = OCRPreprocessor.clean(input)
        #expect(out.contains("29.73%"))
        #expect(out.contains("27.52%"))
        #expect(out.contains("0.00%"))
    }

    // MARK: - Lot/batch-code line stripping

    @Test func stripsLotCodeLine() {
        // "9 - 120925- Blueberry Caviar" is a batch identifier; the FM was
        // pulling "9" and "120925" into cannabinoid fields. Drop the whole line.
        let input = """
        Blue Candy Rain
        9 - 120925- Blueberry Caviar
        THCA: 29.73%
        """
        let out = OCRPreprocessor.clean(input)
        #expect(!out.contains("120925"))
        #expect(out.contains("Blue Candy Rain"))
        #expect(out.contains("THCA: 29.73%"))
    }

    @Test func keepsNormalDashedProductLine() {
        // A normal hyphenated product line must NOT be mistaken for a lot code.
        let input = "Zips - Blue Candy Rain - 28g"
        let out = OCRPreprocessor.clean(input)
        #expect(out.contains("Blue Candy Rain"))
    }
}
