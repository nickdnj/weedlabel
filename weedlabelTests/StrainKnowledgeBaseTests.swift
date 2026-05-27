import Testing
@testable import weedlabel

@Suite("StrainKnowledgeBase")
struct StrainKnowledgeBaseTests {

    // MARK: - Lineage inference

    @Test func kushInfersIndica() {
        let m = StrainKnowledgeBase.classify(strainName: "OG Kush")
        #expect(m?.lean == .indica)
    }

    @Test func hazeInfersSativa() {
        let m = StrainKnowledgeBase.classify(strainName: "Super Lemon Haze")
        #expect(m?.lean == .sativa)
    }

    @Test func gelatoInfersHybrid() {
        let m = StrainKnowledgeBase.classify(strainName: "Caramel Gelato")
        #expect(m?.lean == .hybrid)
    }

    @Test func dieselInfersSativa() {
        let m = StrainKnowledgeBase.classify(strainName: "Sour Diesel")
        #expect(m?.lean == .sativa)
    }

    @Test func cookiesInfersHybrid() {
        let m = StrainKnowledgeBase.classify(strainName: "Animal Cookies")
        #expect(m?.lean == .hybrid)
    }

    @Test func unknownStrainReturnsNil() {
        #expect(StrainKnowledgeBase.classify(strainName: "Lollipopz") == nil)
    }

    @Test func multiWordFragmentWinsOverSingleToken() {
        // "girl scout cookies" (hybrid) comes before "cookies" — same lean here,
        // but verify the more specific fragment matches. "granddaddy purple"
        // (indica) must win over "purple" (also indica) — both indica, but we
        // assert the specific fragment is reported.
        let m = StrainKnowledgeBase.classify(strainName: "Granddaddy Purple")
        #expect(m?.lean == .indica)
        #expect(m?.fragment == "granddaddy purple")
    }

    @Test func caseInsensitive() {
        #expect(StrainKnowledgeBase.classify(strainName: "blueberry kush")?.lean == .indica)
        #expect(StrainKnowledgeBase.classify(strainName: "GELATO")?.lean == .hybrid)
    }

    // MARK: - Printed marker detection

    @Test func detectsParentheticalIndicaMarker() {
        #expect(StrainKnowledgeBase.detectPrintedClass(in: "Kynd Lollipopz (I) Flower 3.5g") == .indica)
    }

    @Test func detectsParentheticalHybridMarker() {
        #expect(StrainKnowledgeBase.detectPrintedClass(in: "Kynd Caramel Gelato (H) Flower 3.5g") == .hybrid)
    }

    @Test func detectsParentheticalSativaMarker() {
        #expect(StrainKnowledgeBase.detectPrintedClass(in: "Green Crack (S) Flower") == .sativa)
    }

    @Test func detectsSpelledOutWord() {
        #expect(StrainKnowledgeBase.detectPrintedClass(in: "Blue Dream — Sativa Dominant") == .sativa)
        #expect(StrainKnowledgeBase.detectPrintedClass(in: "Bubba Kush, Indica") == .indica)
        #expect(StrainKnowledgeBase.detectPrintedClass(in: "Wedding Cake Hybrid") == .hybrid)
    }

    @Test func noMarkerReturnsNil() {
        #expect(StrainKnowledgeBase.detectPrintedClass(in: "Just a product name 3.5g") == nil)
    }

    // MARK: - Resolution precedence (insight)

    @Test func printedMarkerWinsOverLineage() {
        // Name "Kush" would infer indica from lineage, but the label marks it
        // "(S)" — the printed marker is authoritative and should win.
        let insight = StrainKnowledgeBase.insight(
            strainName: "Mystery Kush",
            ocrText: "Mystery Kush (S) Flower 3.5g"
        )
        #expect(insight?.lean == .sativa)
        #expect(insight?.source == .printedMarker)
    }

    @Test func fallsBackToLineageWhenNoMarker() {
        // "OG Kush" contains both "og" and "kush" — both indica. "og" is
        // earlier in the lineage table so it matches first; the lean is what
        // matters and it's correct.
        let insight = StrainKnowledgeBase.insight(
            strainName: "Bubba Kush",
            ocrText: "Bubba Kush Flower 3.5g — no class marker here"
        )
        #expect(insight?.lean == .indica)
        if case .lineage(let frag)? = insight?.source {
            #expect(frag == "bubba")
        } else {
            Issue.record("expected lineage source, got \(String(describing: insight?.source))")
        }
    }

    @Test func returnsNilWhenNothingKnown() {
        let insight = StrainKnowledgeBase.insight(
            strainName: "Lollipopz",
            ocrText: "Lollipopz Flower 3.5g"
        )
        #expect(insight == nil)
    }

    // MARK: - Insight presentation

    @Test func headlineFormatsCleanly() {
        let insight = StrainInsight(lean: .hybrid, source: .printedMarker)
        #expect(insight.headline.contains("Hybrid"))
        #expect(insight.headline.contains("any time of day"))
        #expect(insight.sourceNote == "from label marking")
    }

    @Test func lineageSourceNoteShowsFragment() {
        let insight = StrainInsight(lean: .indica, source: .lineage("kush"))
        #expect(insight.sourceNote == "inferred from name (kush)")
    }

    // MARK: - Lineage character (flavor from the name)

    @Test func knownFragmentHasSpecificCharacter() {
        #expect(StrainKnowledgeBase.character(forFragment: "gelato") == "sweet, creamy dessert")
        #expect(StrainKnowledgeBase.character(forFragment: "kush")?.contains("earthy") == true)
        #expect(StrainKnowledgeBase.character(forFragment: "diesel")?.contains("fuel") == true)
    }

    @Test func unknownFragmentHasNoSpecificCharacter() {
        #expect(StrainKnowledgeBase.character(forFragment: "lollipopz") == nil)
    }

    @Test func characterNoteUsesSpecificForLineage() {
        let insight = StrainInsight(lean: .hybrid, source: .lineage("gelato"))
        #expect(insight.characterNote == "sweet, creamy dessert")
    }

    @Test func characterNoteFallsBackToGeneralForMarker() {
        // Marker source has no fragment → general per-lean character.
        let insight = StrainInsight(lean: .indica, source: .printedMarker)
        #expect(insight.characterNote == StrainLean.indica.generalCharacter)
    }
}
