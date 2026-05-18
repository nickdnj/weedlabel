import SwiftUI
import VisionKit

// DataScannerView — UIViewControllerRepresentable bridge for
// VisionKit's DataScannerViewController. Captures live OCR text and barcode
// payloads from the camera. The MainActor-bound delegate snapshots on
// capture, then the parent view stops the scanner and hands off to the
// FM pipeline (per the v1 eng spec: tear down the camera before invoking FM
// to avoid thermal contention).

struct DataScannerView: UIViewControllerRepresentable {
    var onCapture: @MainActor (_ ocrText: String, _ qrCodes: [String]) -> Void
    var onError: @MainActor (_ error: Error) -> Void

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
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning {
            do { try vc.startScanning() } catch { onError(error) }
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: DataScannerView
        private var hasFired: Bool = false
        // Cache of the latest recognized items from delegate callbacks. iOS 26
        // changed `DataScannerViewController.recognizedItems` to an AsyncStream,
        // so we can no longer poll synchronously — track via the delegate.
        private var latestItems: [RecognizedItem] = []

        init(parent: DataScannerView) {
            self.parent = parent
        }

        // Aggregate recognized items into OCR text + QR strings.
        // Triggers onCapture once a sufficient burst of text is observed
        // (~150 chars), or when the user manually taps capture (handled by
        // didTapOn).
        @MainActor
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            latestItems = allItems
            checkAndDispatch(allItems: allItems, dataScanner: dataScanner)
        }

        @MainActor
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            latestItems = allItems
            checkAndDispatch(allItems: allItems, dataScanner: dataScanner)
        }

        @MainActor
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            // User tapped — treat as commit. Use cached items from prior
            // delegate callbacks (recognizedItems is AsyncStream in iOS 26+).
            forceDispatch(allItems: latestItems, dataScanner: dataScanner)
        }

        @MainActor
        private func checkAndDispatch(allItems: [RecognizedItem], dataScanner: DataScannerViewController) {
            guard !hasFired else { return }
            let texts = allItems.compactMap { item -> String? in
                if case .text(let text) = item { return text.transcript }
                return nil
            }
            let combined = texts.joined(separator: "\n")
            if combined.count >= 150 {
                forceDispatch(allItems: allItems, dataScanner: dataScanner)
            }
        }

        @MainActor
        private func forceDispatch(allItems: [RecognizedItem], dataScanner: DataScannerViewController) {
            guard !hasFired else { return }
            hasFired = true

            let ocrText = allItems.compactMap { item -> String? in
                if case .text(let text) = item { return text.transcript }
                return nil
            }.joined(separator: "\n")

            let qrs = allItems.compactMap { item -> String? in
                if case .barcode(let bc) = item { return bc.payloadStringValue }
                return nil
            }

            dataScanner.stopScanning()
            parent.onCapture(ocrText, qrs)
        }
    }
}
