import Testing
import Foundation
@testable import weedlabel

// MARK: - Hallucination guard

@Suite("SummaryHallucinationGuard")
struct SummaryHallucinationGuardTests {

    /// Build a CannabisLabel with arbitrary numeric overrides. All metadata
    /// fields stay null/empty.
    static func label(
        thca: Double? = nil,
        delta9thc: Double? = nil,
        cbd: Double? = nil,
        totalCannabinoids: Double? = nil,
        totalThc: Double? = nil,
        myrcene: Double? = nil,
        limonene: Double? = nil
    ) -> CannabisLabel {
        CannabisLabel(
            strainName: "X", cultivator: "Y",
            licenseNumber: nil, metrcTag: nil, netWeight: nil,
            harvestDate: nil, expirationDate: nil,
            productType: .flower,
            thca: thca, delta9thc: delta9thc, cbd: cbd, cbg: nil,
            totalCannabinoids: totalCannabinoids,
            totalThc: totalThc, totalCbd: nil,
            myrcene: myrcene, limonene: limonene, linalool: nil,
            betaCaryophyllene: nil, pinene: nil, humulene: nil,
            totalTerpenes: nil,
            qrCodes: []
        )
    }

    // MARK: - Extraction

    @Test func extractsAllPercentagesFromSummary() {
        let text = "Contains 22.5% THC and 0.8% myrcene with 14% limonene."
        let pcts = SummaryService.extractPercentages(from: text)
        #expect(pcts.sorted() == [0.8, 14.0, 22.5])
    }

    @Test func returnsEmptyWhenNoPercentages() {
        let text = "Plain prose with no numeric claims."
        #expect(SummaryService.extractPercentages(from: text).isEmpty)
    }

    // MARK: - Guard behavior

    @Test func passesWhenAllPercentagesAreInLabel() {
        let lbl = Self.label(thca: 22.5, myrcene: 0.8, limonene: 1.0)
        let summary = "Contains 22.5% THCA and 0.8% myrcene."
        #expect(!SummaryService.summaryMentionsHallucinatedPercentages(summary, against: lbl))
    }

    @Test func toleratesRoundingWithinHalfPercent() {
        // Label has 22.5%, summary rounds to 22%. Should still pass.
        let lbl = Self.label(thca: 22.5)
        let summary = "Contains about 22% THC."
        #expect(!SummaryService.summaryMentionsHallucinatedPercentages(summary, against: lbl))
    }

    @Test func rejectsHallucinatedNumberOutsideLabel() {
        let lbl = Self.label(thca: 22.5)
        let summary = "Contains 50% THC."
        #expect(SummaryService.summaryMentionsHallucinatedPercentages(summary, against: lbl))
    }

    @Test func rejectsAnyPercentageWhenLabelHasNoChemistry() {
        // This is the device-observed case: all chemistry null, model invents
        // numbers like "18.3% THC and 1.6% CBD".
        let lbl = Self.label()
        let summary = "Contains 18.3% THC and 1.6% CBD, with 22.2% limonene."
        #expect(SummaryService.summaryMentionsHallucinatedPercentages(summary, against: lbl))
    }

    @Test func passesNonChemistrySummaryWithEmptyLabel() {
        // Summary makes no numeric claims — fine even on an empty label.
        let lbl = Self.label()
        let summary = "We couldn't read chemistry data; verify the printed label."
        #expect(!SummaryService.summaryMentionsHallucinatedPercentages(summary, against: lbl))
    }

    @Test func usesComputedTotalThcAsValidSource() {
        // THCA × 0.877 + Δ9-THC = 29.73 × 0.877 + 1.45 = 27.5147
        // A summary saying "27.5% Total THC" should be allowed via computed value.
        let lbl = Self.label(thca: 29.73, delta9thc: 1.45)
        let summary = "Computed total THC is 27.5%."
        #expect(!SummaryService.summaryMentionsHallucinatedPercentages(summary, against: lbl))
    }
}

// P6 validator (regex denylist) tests. These run on simulator without
// Foundation Models — they validate the safety floor regardless of FM behavior.

@Suite struct P6ValidatorTests {
    // MARK: - Medical claim verbs

    @Test func detectsTreats() {
        #expect(SummaryService.firstViolation(in: "This treats anxiety effectively.") != nil)
    }

    @Test func detectsCures() {
        #expect(SummaryService.firstViolation(in: "Said to cure insomnia.") != nil)
    }

    @Test func detectsHeals() {
        #expect(SummaryService.firstViolation(in: "Heals chronic pain.") != nil)
    }

    @Test func detectsPrevents() {
        #expect(SummaryService.firstViolation(in: "Prevents nausea.") != nil)
    }

    @Test func detectsRelieves() {
        #expect(SummaryService.firstViolation(in: "Relieves stress.") != nil)
    }

    @Test func detectsReducesSymptom() {
        #expect(SummaryService.firstViolation(in: "Reduces pain in patients.") != nil)
        #expect(SummaryService.firstViolation(in: "May reduce anxiety.") != nil)
    }

    // MARK: - Helping-claim phrases

    @Test func detectsWillHelp() {
        #expect(SummaryService.firstViolation(in: "This will help with sleep.") != nil)
    }

    @Test func detectsHelpsWith() {
        #expect(SummaryService.firstViolation(in: "Helps with relaxation.") != nil)
    }

    @Test func detectsGoodFor() {
        #expect(SummaryService.firstViolation(in: "Good for chronic conditions.") != nil)
    }

    @Test func detectsMayHelp() {
        #expect(SummaryService.firstViolation(in: "May help reduce stress.") != nil)
    }

    // MARK: - Second-person directives

    @Test func detectsYouShould() {
        #expect(SummaryService.firstViolation(in: "You should take this before bed.") != nil)
    }

    @Test func detectsYoullFeel() {
        #expect(SummaryService.firstViolation(in: "You'll feel relaxed within an hour.") != nil)
    }

    @Test func detectsTakeThisWhen() {
        #expect(SummaryService.firstViolation(in: "Take this when you can't sleep.") != nil)
    }

    // MARK: - Dosing language

    @Test func detectsRecommendedDose() {
        #expect(SummaryService.firstViolation(in: "Recommended dose is one gram.") != nil)
    }

    @Test func detectsExplicitMg() {
        #expect(SummaryService.firstViolation(in: "Each serving contains 10mg.") != nil)
    }

    @Test func detectsPrescription() {
        #expect(SummaryService.firstViolation(in: "Available by prescription only.") != nil)
    }

    @Test func detectsDiagnose() {
        #expect(SummaryService.firstViolation(in: "Used to diagnose pain disorders.") != nil)
    }

    // MARK: - Negative cases (must NOT fire)

    @Test func cleanFactualSummary() {
        let s = """
        High-THC flower at 32.25% total cannabinoids with a sedative-leaning \
        terpene profile. Myrcene dominates at 1.83%, with linalool and \
        β-caryophyllene reinforcing relaxation.
        """
        #expect(SummaryService.firstViolation(in: s) == nil)
    }

    @Test func cleanFactualWithCBG() {
        let s = "The 0.49% CBG content is unusually high for NJ flower."
        #expect(SummaryService.firstViolation(in: s) == nil)
    }

    @Test func cleanThirdPersonEffect() {
        let s = "The terpene profile leans sedative; myrcene is dominant."
        #expect(SummaryService.firstViolation(in: s) == nil)
    }

    // MARK: - Case insensitivity

    @Test func caseInsensitive() {
        #expect(SummaryService.firstViolation(in: "TREATS chronic pain.") != nil)
        #expect(SummaryService.firstViolation(in: "Will Help with anxiety.") != nil)
    }
}
