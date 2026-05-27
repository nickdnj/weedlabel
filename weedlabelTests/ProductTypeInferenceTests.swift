import Testing
import Foundation
@testable import weedlabel

@Suite("ProductTypeInference")
struct ProductTypeInferenceTests {

    @Test func inhalableProductIsFlower() {
        // The reported bug: "…Candy" in the name biased FM to .edible, but the
        // label says "Inhalable Product".
        #expect(ProductTypeInference.infer(ocrText: "High THC, Low CBD\nInhalable Product\nZips - Blue Candy") == .flower)
    }

    @Test func gramWeightAloneIsNotEnough() {
        // A bare weight is a weak signal; defer to the model rather than guess.
        #expect(ProductTypeInference.infer(ocrText: "Some Strain - 28g") == nil)
    }

    @Test func preRollWinsOverGenericInhalable() {
        #expect(ProductTypeInference.infer(ocrText: "Inhalable Product\nPre-Roll 1g") == .preRoll)
    }

    @Test func vapeDetected() {
        #expect(ProductTypeInference.infer(ocrText: "Vape Cartridge 0.5g") == .vape)
    }

    @Test func ediblesDetectedByDosageWording() {
        #expect(ProductTypeInference.infer(ocrText: "Gummies — 10mg per serving") == .edible)
    }

    @Test func chocolateInNameDoesNotForceEdible() {
        // "Chocolope" is flower — a bare chocolate/candy substring must NOT
        // trigger .edible.
        #expect(ProductTypeInference.infer(ocrText: "Chocolope\nInhalable Product") == .flower)
        #expect(ProductTypeInference.infer(ocrText: "Chocolate Hashberry") == nil)
    }

    @Test func tinctureAndTopical() {
        #expect(ProductTypeInference.infer(ocrText: "Full-spectrum Tincture 30ml") == .tincture)
        #expect(ProductTypeInference.infer(ocrText: "Relief Topical Balm") == .topical)
    }

    @Test func noSignalReturnsNil() {
        #expect(ProductTypeInference.infer(ocrText: "Blue Candy Rain\nFresh Grow LLC") == nil)
    }

    @Test func canaryFixtureReadsAsFlower() {
        // The actual scrambled canary OCR contains "Inhalable Product".
        let ocr = """
        High THC, Low CBD
        Inhalable Product
        Zips - Blue Candy
        Rain - 28g
        THCA: 29.73
        """
        #expect(ProductTypeInference.infer(ocrText: ocr) == .flower)
    }
}
