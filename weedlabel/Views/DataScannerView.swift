import SwiftUI
import VisionKit
import UIKit

// ScannerController — bridge that lets ScanModel pull a high-resolution still
// from the live DataScannerViewController. We confirm we're looking at the
// right thing using the live OCR field chips (content, not geometry — rectangle
// detection fails on labels fused to packaging), then capture a sharp full-res
// photo and OCR THAT, which is far cleaner than live preview-frame OCR.
@MainActor
final class ScannerController {
    weak var scanner: DataScannerViewController?

    /// Capture a high-resolution still of the current scene. Returns nil if no
    /// scanner is attached (e.g. simulator) or capture fails — callers fall
    /// back to the live OCR text in that case.
    func capturePhoto() async -> UIImage? {
        guard let scanner else { return nil }
        return try? await scanner.capturePhoto()
    }
}

// DataScannerView — UIViewControllerRepresentable bridge for VisionKit's
// DataScannerViewController.
//
// New behavior (post-Phase-1 UX overhaul, 2026-05-26):
//   - Reads OCR text + barcode payloads continuously and emits them to the
//     parent via `onTextUpdate`. The parent (ScanModel) tracks `lastSeenOcr`
//     and `lastSeenQRs` and runs FieldDetector against them to drive the
//     live "fields detected" chip row.
//   - The 150-char auto-capture is GONE. Capture is initiated explicitly by
//     the user tapping the shutter button in the scanning overlay, which calls
//     ScanModel.confirmCapture() on the snapshot the model has been tracking.
//   - `regionOfInterest` is set to a centered viewfinder rectangle so OCR only
//     reads inside the user-visible bracket frame — like a check-deposit app.

struct DataScannerView: UIViewControllerRepresentable {
    var onTextUpdate: @MainActor (_ ocrText: String, _ qrCodes: [String]) -> Void
    var onError: @MainActor (_ error: Error) -> Void
    /// Receives the underlying controller so ScanModel can call capturePhoto().
    var scannerController: ScannerController?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [
                .text(),
                .barcode()
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        scannerController?.scanner = vc
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning {
            do { try vc.startScanning() } catch { onError(error) }
        }
        // Re-apply the region of interest in case the bounds changed (rotation,
        // safe area updates). DataScannerViewController honors this in view
        // coordinates; we use a centered rect ~75% wide × ~40% tall.
        let bounds = vc.view.bounds
        let width = bounds.width * 0.78
        let height = bounds.height * 0.42
        vc.regionOfInterest = CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: DataScannerView

        init(parent: DataScannerView) {
            self.parent = parent
        }

        @MainActor
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            emit(allItems)
        }

        @MainActor
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            emit(allItems)
        }

        @MainActor
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didRemove removedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            emit(allItems)
        }

        @MainActor
        private func emit(_ allItems: [RecognizedItem]) {
            let texts = allItems.compactMap { item -> String? in
                if case .text(let text) = item { return text.transcript }
                return nil
            }
            let combined = texts.joined(separator: "\n")
            let qrs = allItems.compactMap { item -> String? in
                if case .barcode(let bc) = item { return bc.payloadStringValue }
                return nil
            }
            parent.onTextUpdate(combined, qrs)
        }
    }
}
