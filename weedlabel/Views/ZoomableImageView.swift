import SwiftUI
import UIKit

// ZoomableImageView — full-screen pinch-to-zoom / drag-to-pan viewer for a saved
// scan image, so the user can inspect the label closely and check the extracted
// values against the actual print (fidelity check). Opened from the Log Book
// detail by tapping the image.
//
// Gestures: pinch to zoom (clamped 1×–6×), drag to pan while zoomed, double-tap
// to toggle between fit and 2.5×. Panning resets when zoomed back to fit.

struct ZoomableImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 6

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(SimultaneousGesture(magnify, drag))
                .onTapGesture(count: 2) { toggleZoom() }
                .animation(.interactiveSpring(), value: scale)
                .animation(.interactiveSpring(), value: offset)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .white.opacity(0.25))
                    .padding(16)
            }
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale { resetPan() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }   // only pan when zoomed in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        if scale > minScale {
            scale = minScale; lastScale = minScale; resetPan()
        } else {
            scale = 2.5; lastScale = 2.5
        }
    }

    private func resetPan() {
        offset = .zero; lastOffset = .zero
    }
}
