import Foundation
import UIKit
import Vision

// StaticImageOCR — runs Vision text + barcode recognition against a bundled or
// user-supplied UIImage. Output shape mirrors what DataScannerView's coordinator
// dispatches (ocrText, qrCodes), so the same ScanModel pipeline can ingest it.
//
// Debug-only entry path: used by the "Use bundled canary" button to validate the
// FM extraction step end-to-end without holding a phone over a label.

enum StaticImageOCR {
    enum OCRError: Error, LocalizedError {
        case missingResource(String)
        case noCGImage
        case visionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name): return "Resource not found: \(name)"
            case .noCGImage: return "Could not obtain CGImage from the source image."
            case .visionFailed(let e): return "Vision request failed: \(e.localizedDescription)"
            }
        }
    }

    struct Result: Sendable {
        let ocrText: String
        let qrCodes: [String]
    }

    /// Load a bundled image by name (without extension) and OCR it. Looks in
    /// the `validation/` folder reference where canary assets live.
    static func bundled(named name: String, withExtension ext: String) async throws -> Result {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "validation") else {
            throw OCRError.missingResource("\(name).\(ext)")
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw OCRError.missingResource(url.lastPathComponent)
        }
        return try await recognize(in: image)
    }

    /// Run Vision text recognition + barcode detection against an image. We try
    /// multiple orientations and pick the one that produces the most "tight"
    /// text observations — this handles labels photographed on their side or
    /// upside-down (common with cylindrical containers like Zips tins).
    /// Observations are then sorted top-to-bottom then left-to-right.
    static func recognize(in image: UIImage) async throws -> Result {
        guard let cg = image.cgImage else {
            throw OCRError.noCGImage
        }
        let imageOrientation = cgOrientation(from: image.imageOrientation)
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                // Dedupe so we don't run Vision twice for the same orientation.
                var seen = Set<UInt32>()
                let candidates = [imageOrientation, .right, .left, .down].filter { seen.insert($0.rawValue).inserted }

                var bestObservations: [VNRecognizedTextObservation] = []
                var bestQuality: Double = -1
                var lastError: Error?
                for orientation in candidates {
                    let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
                    let textRequest = VNRecognizeTextRequest()
                    textRequest.recognitionLevel = .accurate
                    textRequest.usesLanguageCorrection = true
                    textRequest.recognitionLanguages = ["en-US"]
                    do {
                        try handler.perform([textRequest])
                    } catch {
                        lastError = error
                        continue
                    }
                    let observations = textRequest.results ?? []
                    let quality = qualityScore(observations)
                    if quality > bestQuality {
                        bestQuality = quality
                        bestObservations = observations
                    }
                }

                // If every orientation failed, surface the last error rather than
                // silently returning an empty result.
                if bestQuality < 0 {
                    cont.resume(throwing: OCRError.visionFailed(lastError ?? noOrientationsSucceededError()))
                    return
                }

                let text = Self.assembleRows(bestObservations)

                // Barcodes are orientation-invariant for QR — one pass on the
                // original orientation is enough. Failure is non-fatal: a label
                // with no QR is valid.
                let barcodeHandler = VNImageRequestHandler(cgImage: cg, orientation: imageOrientation, options: [:])
                let barcodeRequest = VNDetectBarcodesRequest()
                _ = try? barcodeHandler.perform([barcodeRequest])
                let qrs = (barcodeRequest.results ?? []).compactMap { $0.payloadStringValue }

                cont.resume(returning: Result(ocrText: text, qrCodes: qrs))
            }
        }
    }

    /// Assemble OCR text by VISUAL ROW, not one-observation-per-line. Cannabis
    /// labels are multi-column ("Total THC:" in one column, "25.90 %" in the
    /// next); Vision returns those as separate observations at the same Y. We
    /// group observations whose vertical centers are close into one row and read
    /// them left-to-right, so "Total THC:" rejoins its value on one line — which
    /// is what lets both the model and the cannabinoid reconciler pair them.
    static func assembleRows(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Item { let text: String; let yc: CGFloat; let xMin: CGFloat }
        let items: [Item] = observations.compactMap { obs in
            guard let s = obs.topCandidates(1).first?.string else { return nil }
            return Item(text: s, yc: 1.0 - obs.boundingBox.midY, xMin: obs.boundingBox.minX)
        }.sorted { $0.yc < $1.yc }

        let rowTolerance: CGFloat = 0.015   // ~1.5% of height; rows sit ~5% apart
        var rows: [[Item]] = []
        for it in items {
            if let ref = rows.last?.first, abs(it.yc - ref.yc) <= rowTolerance {
                rows[rows.count - 1].append(it)
            } else {
                rows.append([it])
            }
        }
        return rows.map { row in
            row.sorted { $0.xMin < $1.xMin }.map(\.text).joined(separator: "  ")
        }.joined(separator: "\n")
    }

    private static func noOrientationsSucceededError() -> NSError {
        NSError(
            domain: "StaticImageOCR",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "No orientation produced a successful Vision recognition pass."]
        )
    }

    /// Heuristic quality score for a set of text observations. Higher = better.
    /// Prefers observations with tight (wider than tall) aspect ratios — the
    /// signature of upright single-line text. Penalises tall narrow boxes which
    /// are the signature of rotated text being read in the wrong orientation.
    private static func qualityScore(_ observations: [VNRecognizedTextObservation]) -> Double {
        guard !observations.isEmpty else { return 0 }
        var score: Double = 0
        for obs in observations {
            let w = obs.boundingBox.width
            let h = obs.boundingBox.height
            guard h > 0 else { continue }
            let aspect = w / h
            // A normal text line has aspect > 3 typically. Reward observations
            // whose aspect ratio matches that profile.
            score += min(aspect, 20.0)
        }
        return score
    }

    private static func cgOrientation(from ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch ui {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
