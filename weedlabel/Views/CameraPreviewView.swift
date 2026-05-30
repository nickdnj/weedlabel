import SwiftUI
import AVFoundation
import UIKit

// CameraPreviewView — SwiftUI wrapper around an AVCaptureVideoPreviewLayer fed by
// LabelCamera's session. Tapping converts to a device focus point and asks the
// camera to focus there (deliberate, in-focus capture is the whole point).

struct CameraPreviewView: UIViewRepresentable {
    let camera: LabelCamera

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTapToFocus = { devicePoint in camera.focus(atDevicePoint: devicePoint) }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== camera.session {
            uiView.previewLayer.session = camera.session
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTapToFocus: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func handleTap(_ gr: UITapGestureRecognizer) {
            let layerPoint = gr.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            onTapToFocus?(devicePoint)
        }
    }
}
