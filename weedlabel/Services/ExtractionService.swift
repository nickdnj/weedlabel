import Foundation
import FoundationModels

// ExtractionService — wraps the Foundation Models @Generable extraction call.
// Per the eng spec, this runs as a child Task off the (MainActor) DataScanner
// delegate. The pipeline is sequential: extraction first, sanity check second,
// summary third.

actor ExtractionService {
    private var session: LanguageModelSession?

    func warm() {
        if session == nil {
            session = LanguageModelSession()
        }
    }

    func extract(rawOcrText: String) async throws -> CannabisLabel {
        if session == nil {
            session = LanguageModelSession()
        }
        guard let session else {
            throw ExtractionError.noSession
        }

        // Truncate OCR if it ever exceeds a safe context envelope.
        // NJ labels are < 2KB; FM context is 4K+ tokens. This is a guardrail.
        let safeOcr: String = {
            if rawOcrText.count > 3000 { return String(rawOcrText.prefix(3000)) }
            return rawOcrText
        }()

        let promptText = """
        Extract structured data from the OCR text of an NJ-CRC personal-use cannabis \
        label. Each field must reflect what is printed on the label. Set fields to \
        null if not present. Do NOT compute totals — copy the printed values.

        OCR text:
        \(safeOcr)
        """

        let response = try await session.respond(
            to: Prompt(promptText),
            generating: CannabisLabel.self
        )
        return response.content
    }

    enum ExtractionError: Error, Sendable {
        case noSession
    }
}
