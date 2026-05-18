import Testing
import Foundation
@testable import weedlabel

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
