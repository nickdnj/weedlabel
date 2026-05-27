import Testing
import Foundation
@testable import weedlabel

@Suite("FieldDetector")
struct FieldDetectorTests {

    // MARK: - License

    @Test func detectsCanonicalCrcLicense() {
        #expect(FieldDetector.hasLicense("License # C000186"))
    }

    @Test func detectsLicenseWithoutLabel() {
        #expect(FieldDetector.hasLicense("Random text C123456 more text"))
    }

    @Test func rejectsLowercaseLicense() {
        #expect(!FieldDetector.hasLicense("c123456"))
    }

    @Test func rejectsShortNumbers() {
        #expect(!FieldDetector.hasLicense("C123"))
    }

    // MARK: - Metrc

    @Test func detectsCanonicalMetrcTag() {
        #expect(FieldDetector.hasMetrcTag("1A4110300003C8D000041730"))
    }

    @Test func detectsMetrcTagInLine() {
        #expect(FieldDetector.hasMetrcTag("Lot: 1A4110300003C8D000041730 (Metrc)"))
    }

    @Test func rejectsWrongPrefix() {
        #expect(!FieldDetector.hasMetrcTag("1B5110300003C8D000041730"))
    }

    @Test func rejectsShortString() {
        #expect(!FieldDetector.hasMetrcTag("1A4123"))
    }

    // MARK: - Potency

    @Test func detectsPotencyByAcronym() {
        #expect(FieldDetector.hasPotency("THCA: 29.73%"))
    }

    @Test func detectsPotencyByDelta9() {
        #expect(FieldDetector.hasPotency("Delta-9-THC: 1.45%"))
    }

    @Test func detectsPotencyByBareThcWithColon() {
        #expect(FieldDetector.hasPotency("THC: 27.52%"))
    }

    @Test func rejectsBareThcWordInsideOtherText() {
        // No digit nearby — shouldn't trigger.
        #expect(!FieldDetector.hasPotency("we thoroughly tested this"))
    }

    @Test func detectsPotencyByCBG() {
        #expect(FieldDetector.hasPotency("CBG: 0.49%"))
    }

    // MARK: - Terpenes

    @Test func detectsTerpenesByMyrcene() {
        #expect(FieldDetector.hasTerpenes("Beta-Myrcene: 1.83%"))
    }

    @Test func detectsTerpenesByCaryophyllene() {
        #expect(FieldDetector.hasTerpenes("BetaCaryophyllene: 0.44%"))
    }

    @Test func detectsTerpenesBySectionHeader() {
        #expect(FieldDetector.hasTerpenes("Terpene Contents -"))
    }

    @Test func rejectsNonCannabisText() {
        #expect(!FieldDetector.hasTerpenes("Net weight 28g, store cool dry place."))
    }

    // MARK: - Aggregate detect()

    @Test func aggregatesCanaryFields() {
        let canary = """
        License # C000186
        1A4110300003C8D000041730
        THCA: 29.73%
        Limonene: 1.83%
        """
        let found = FieldDetector.detect(ocrText: canary, qrCodes: ["1A4110300003C8D000041730"])
        #expect(found.contains(.license))
        #expect(found.contains(.metrcTag))
        #expect(found.contains(.potency))
        #expect(found.contains(.terpenes))
        #expect(found.contains(.qrCode))
    }

    @Test func emptyTextReturnsEmptySet() {
        let found = FieldDetector.detect(ocrText: "", qrCodes: [])
        #expect(found.isEmpty)
    }

    @Test func qrCodesAloneCountsAsOneField() {
        let found = FieldDetector.detect(ocrText: "", qrCodes: ["1A4..."])
        #expect(found == [.qrCode])
    }

    // MARK: - Capture threshold

    @Test func threeFieldsMeetsCaptureThreshold() {
        let fields: Set<DetectedField> = [.license, .metrcTag, .potency]
        #expect(FieldDetector.meetsCaptureThreshold(fields))
    }

    @Test func twoFieldsDoesNotMeetThreshold() {
        let fields: Set<DetectedField> = [.license, .metrcTag]
        #expect(!FieldDetector.meetsCaptureThreshold(fields))
    }
}
