import Foundation
import Vision
import ImageIO
import CoreGraphics

// macOS counterpart to the app's StaticImageOCR (which is UIKit/UIImage-bound,
// so it can't be symlinked). Same recognition config — .accurate, language
// correction on, en-US — and the same orientation-sweep quality heuristic, but
// loads CGImage via ImageIO from a file URL so no UIKit/AppKit is dragged in.
// Result shape matches StaticImageOCR.Result for downstream parity.
//
// NOTE: the app's StaticImageOCR uses recognitionLanguages = ["en-US"]; we
// match that exactly (NJ-CRC labels are English). The orientation sweep matters
// here because the canary set includes a cylindrical tin photographed sideways.

enum MacImageOCR {
    enum OCRError: Error, LocalizedError {
        case noCGImage(URL)
        case visionFailed(Error)
        case noOrientationSucceeded

        var errorDescription: String? {
            switch self {
            case .noCGImage(let url): return "Could not load CGImage from \(url.lastPathComponent)."
            case .visionFailed(let e): return "Vision request failed: \(e.localizedDescription)"
            case .noOrientationSucceeded: return "No orientation produced a successful Vision pass."
            }
        }
    }

    struct Result: Sendable {
        let ocrText: String
        let qrCodes: [String]
    }

    /// Matches StaticImageOCR exactly: English-only. NJ-CRC labels are English;
    /// adding other languages only adds OCR noise.
    static let recognitionLanguages = ["en-US"]

    static func recognize(at url: URL) async throws -> Result {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw OCRError.noCGImage(url)
        }

        // Start from the file's EXIF orientation, then sweep the standard four
        // as fallback — labels photographed sideways (the Zips tin canary) are
        // common, and the quality heuristic picks the upright read.
        let exif = exifOrientation(from: src) ?? .up

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var seen = Set<UInt32>()
                let candidates: [CGImagePropertyOrientation] = [exif, .right, .left, .down, .up]
                    .filter { seen.insert($0.rawValue).inserted }

                var bestObservations: [VNRecognizedTextObservation] = []
                var bestQuality: Double = -1
                var lastError: Error?
                for orientation in candidates {
                    let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
                    let req = VNRecognizeTextRequest()
                    req.recognitionLevel = .accurate
                    req.usesLanguageCorrection = true
                    req.recognitionLanguages = recognitionLanguages
                    do {
                        try handler.perform([req])
                    } catch {
                        lastError = error
                        continue
                    }
                    let obs = req.results ?? []
                    let q = qualityScore(obs)
                    if q > bestQuality {
                        bestQuality = q
                        bestObservations = obs
                    }
                }

                if bestQuality < 0 {
                    cont.resume(throwing: OCRError.visionFailed(lastError ?? OCRError.noOrientationSucceeded))
                    return
                }

                // Top-to-bottom, then left-to-right reading order.
                let sorted = bestObservations.sorted { a, b in
                    let aTop = 1.0 - a.boundingBox.maxY
                    let bTop = 1.0 - b.boundingBox.maxY
                    if abs(aTop - bTop) > 0.01 { return aTop < bTop }
                    return a.boundingBox.minX < b.boundingBox.minX
                }
                let text = sorted
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                // Barcodes/QR — orientation-invariant enough to read off the EXIF
                // orientation. These feed the app's "merge VisionKit QRs" step.
                let barcodeHandler = VNImageRequestHandler(cgImage: cg, orientation: exif, options: [:])
                let barcodeReq = VNDetectBarcodesRequest()
                _ = try? barcodeHandler.perform([barcodeReq])
                let qrs = (barcodeReq.results ?? []).compactMap { $0.payloadStringValue }

                cont.resume(returning: Result(ocrText: text, qrCodes: qrs))
            }
        }
    }

    /// Prefer orientations where text boxes are wider than tall (upright text);
    /// cap each box's contribution so one huge box can't dominate.
    private static func qualityScore(_ obs: [VNRecognizedTextObservation]) -> Double {
        guard !obs.isEmpty else { return 0 }
        var score: Double = 0
        for o in obs {
            let w = o.boundingBox.width, h = o.boundingBox.height
            guard h > 0 else { continue }
            score += min(w / h, 20.0)
        }
        return score
    }

    private static func exifOrientation(from source: CGImageSource) -> CGImagePropertyOrientation? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = props[kCGImagePropertyOrientation] as? UInt32 else { return nil }
        return CGImagePropertyOrientation(rawValue: raw)
    }
}
