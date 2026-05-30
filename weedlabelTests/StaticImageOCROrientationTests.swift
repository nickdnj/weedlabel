import Testing
import CoreGraphics
@testable import weedlabel

// Orientation-selection tests for StaticImageOCR. Vision OCR itself can't run in
// the Simulator, but the orientation CHOICE is pure arithmetic over per-
// orientation aspect + anchor scores — so we test it with the exact numbers
// measured from real on-device Jet Fuel captures (both upright and flipped 180°).
// Candidate order matches recognize(): [imageOrientation, .right, .left, .down].

@Suite struct StaticImageOCROrientationTests {

    // MARK: - chooseBestOrientation (the 180° discriminator)

    @Test func uprightCaptureChoosesUpOverFlippedDown() {
        // 6A43 upright: .up reads correctly (anchor 0.55), .down is reversed
        // (anchor 0.43) — and .down's aspect is actually HIGHER, which is exactly
        // why aspect alone failed. Anchor must win.
        let aspects = [529.9, 7.1, 7.7, 538.9]
        let anchors: [Double?] = [0.55, 0.48, 0.52, 0.43]
        #expect(StaticImageOCR.chooseBestOrientation(aspects: aspects, anchors: anchors) == 0)
    }

    @Test func upsideDownCaptureChoosesDown() {
        // 6A43 flipped 180°: now .down is the correct reading (anchor 0.56) and
        // .up is reversed (anchor 0.42).
        let aspects = [540.0, 7.7, 7.1, 528.8]
        let anchors: [Double?] = [0.42, 0.52, 0.48, 0.56]
        #expect(StaticImageOCR.chooseBestOrientation(aspects: aspects, anchors: anchors) == 3)
    }

    @Test func ninetyDegreeReadingsAreDroppedByAspectFilter() {
        // 489B upright: only .up is horizontal (aspect 401.6); the 180° read was
        // garbage (aspect 91.3, no anchors). Aspect filter keeps only .up.
        let aspects = [401.6, 5.5, 5.8, 91.3]
        let anchors: [Double?] = [0.53, 0.53, 0.46, nil]
        #expect(StaticImageOCR.chooseBestOrientation(aspects: aspects, anchors: anchors) == 0)
    }

    @Test func fallsBackToAspectWhenNoAnchors() {
        // Non-NJ label with no boilerplate: no anchor scores anywhere → pick the
        // highest aspect (prior behavior).
        let aspects = [120.0, 6.0, 500.0, 5.0]
        let anchors: [Double?] = [nil, nil, nil, nil]
        #expect(StaticImageOCR.chooseBestOrientation(aspects: aspects, anchors: anchors) == 2)
    }

    @Test func returnsNilWhenNoOrientationsSucceeded() {
        #expect(StaticImageOCR.chooseBestOrientation(aspects: [], anchors: []) == nil)
    }

    // MARK: - anchorOrientationScore

    @Test func anchorScoreIsHighWhenBoilerplateSitsLow() {
        // Title at top (yc 0.05), warning block at bottom (yc 0.9) → high score.
        let rows: [(text: String, yc: CGFloat)] = [
            ("Kynd Jet Fuel (S) Flower 3.5g", 0.05),
            ("Total THC: 25.74%", 0.20),
            ("NOT SAFE FOR KIDS", 0.90),
            ("Keep out of the reach of children", 0.95),
        ]
        let s = StaticImageOCR.anchorOrientationScore(rows)
        #expect(s != nil)
        #expect(s! > 0.8)
    }

    @Test func anchorScoreIsLowWhenBoilerplateSitsHigh() {
        // Reversed: warnings at top (yc 0.05), title at bottom → low score.
        let rows: [(text: String, yc: CGFloat)] = [
            ("NOT SAFE FOR KIDS", 0.05),
            ("Keep out of the reach of children", 0.10),
            ("Total THC: 25.74%", 0.80),
            ("Kynd Jet Fuel (S) Flower 3.5g", 0.95),
        ]
        let s = StaticImageOCR.anchorOrientationScore(rows)
        #expect(s != nil)
        #expect(s! < 0.2)
    }

    @Test func anchorScoreNilWithoutBoilerplate() {
        let rows: [(text: String, yc: CGFloat)] = [
            ("Some Strain", 0.1),
            ("THCA 28%", 0.3),
        ]
        #expect(StaticImageOCR.anchorOrientationScore(rows) == nil)
    }
}
