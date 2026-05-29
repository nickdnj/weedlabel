import UIKit
import Vision
import CoreImage

// LabelIsolator — finds the rectangular product label inside a photo and returns
// a deskewed, cropped, frontal image of just the label.
//
// Why: real scans are often whole-bag shots where the label fills a small,
// tilted patch of the frame — Vision OCR then mangles the tiny low-contrast
// terpene column. Isolating + perspective-correcting the label gives OCR a
// large, straight, high-contrast target (and gives the Log Book a clean crop).
//
// Strategy: VNDetectDocumentSegmentationRequest (the document/rectangle
// segmenter scanner apps use) → fall back to VNDetectRectanglesRequest → return
// nil if no convincing quad is found (caller then uses the original image). Pure,
// synchronous, no FM — safe to call on a background queue before OCR.

enum LabelIsolator {
    /// Returns a deskewed crop of the dominant label/document rectangle, or nil
    /// if none is found with enough confidence (caller falls back to original).
    static func isolate(_ image: UIImage) -> UIImage? {
        let upright = normalizedUp(image)
        guard let cg = upright.cgImage else { return nil }

        guard let quad = detectQuad(cg) else { return nil }
        // Reject implausible detections: a sliver, or near the whole frame
        // (nothing isolated). Area is in normalized units (0–1).
        let area = quadArea(quad)
        guard area > 0.03, area < 0.97 else { return nil }

        return perspectiveCorrected(cg, quad: quad)
    }

    // MARK: - Detection

    /// Normalized (0–1, lower-left origin) corners of the best rectangle.
    private struct Quad { var tl, tr, bl, br: CGPoint }

    private static func detectQuad(_ cg: CGImage) -> Quad? {
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)

        // 1) Document segmentation — best for labels/documents.
        let doc = VNDetectDocumentSegmentationRequest()
        if (try? handler.perform([doc])) != nil,
           let obs = (doc.results)?.first,
           obs.confidence >= 0.5 {
            return Quad(tl: obs.topLeft, tr: obs.topRight, bl: obs.bottomLeft, br: obs.bottomRight)
        }

        // 2) Rectangle detection fallback — tuned for a single prominent label.
        let rect = VNDetectRectanglesRequest()
        rect.minimumConfidence = 0.6
        rect.minimumAspectRatio = 0.2   // labels are wide-ish; allow a wide range
        rect.maximumObservations = 1
        rect.minimumSize = 0.1
        if (try? handler.perform([rect])) != nil,
           let obs = (rect.results)?.max(by: { $0.confidence < $1.confidence }) {
            return Quad(tl: obs.topLeft, tr: obs.topRight, bl: obs.bottomLeft, br: obs.bottomRight)
        }
        return nil
    }

    // MARK: - Perspective correction

    /// Deskew the quad to a frontal rectangle and render it to a UIImage.
    private static func perspectiveCorrected(_ cg: CGImage, quad: Quad) -> UIImage? {
        let ci = CIImage(cgImage: cg)
        let w = ci.extent.width, h = ci.extent.height
        // Vision normalized coords share CoreImage's lower-left origin, so just
        // scale into pixel space.
        func p(_ n: CGPoint) -> CIVector { CIVector(x: n.x * w, y: n.y * h) }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(p(quad.tl), forKey: "inputTopLeft")
        filter.setValue(p(quad.tr), forKey: "inputTopRight")
        filter.setValue(p(quad.br), forKey: "inputBottomRight")
        filter.setValue(p(quad.bl), forKey: "inputBottomLeft")
        guard let out = filter.outputImage else { return nil }

        let ctx = CIContext(options: nil)
        guard let cgOut = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cgOut)
    }

    // MARK: - Helpers

    /// Normalized quad area via the shoelace formula (corners in 0–1 space).
    private static func quadArea(_ q: Quad) -> CGFloat {
        let pts = [q.tl, q.tr, q.br, q.bl]
        var a: CGFloat = 0
        for i in 0..<4 {
            let j = (i + 1) % 4
            a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return abs(a) / 2
    }

    /// Redraw the image upright so its CGImage needs no orientation handling.
    private static func normalizedUp(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
