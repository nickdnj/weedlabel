import AVFoundation
import CoreMedia
import CoreVideo
import os
import UIKit
import Vision

/// Live camera diagnostics — stream from a plugged-in device with:
///   idevicesyslog | grep -i camdiag
private let camLog = Logger(subsystem: "com.demarconet.weedlabel", category: "camera")

// LabelCamera — the deliberate, focus-first capture engine that replaces the
// VisionKit DataScanner live-OCR path. There is NO live AI reading: we do not
// run text recognition on preview frames or auto-capture on "fields detected".
// Instead we watch FOCUS and FRAMING and snap a single sharp, full-resolution
// still only when the label fills the frame and is crisp — then hand that one
// good image to the post-processing pipeline (isolate → OCR → extract).
//
// Outputs on the AVCaptureSession:
//   - photo output  : the sharp still we actually extract from
//   - video output  : low-rate frames for sharpness + label-rectangle framing
//   - metadata output: QR / barcode (Metrc) payloads
//
// Threading: the session and all delegate callbacks run off the main actor on a
// private serial queue; UI-facing state is delivered through main-actor closures
// so the @Observable ScanModel stays the single source of truth for SwiftUI.

/// What the framing analysis currently sees — drives the on-screen hint.
enum CaptureFraming: Equatable {
    case searching      // no label rectangle found
    case tooFar         // label found but small — move closer
    case holdSteady     // framed but not yet sharp / focus settling
    case ready          // framed + sharp → about to auto-capture
}

struct CapturedFrame {
    let image: UIImage
    let qrCodes: [String]
}

// @unchecked Sendable: the AVFoundation delegate callbacks arrive on private
// queues and mutate simple flags (armed/capturing/readyStreak). Those mutations
// are benign (a missed/extra preview frame at worst) and all session mutation is
// funnelled through sessionQueue. This lets us hop results to the main actor for
// the @Observable ScanModel without the compiler flagging `self` capture.
final class LabelCamera: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    // Main-actor callbacks set by ScanModel.
    var onFraming: (@MainActor @Sendable (CaptureFraming) -> Void)?
    var onCapture: (@MainActor @Sendable (CapturedFrame) -> Void)?
    var onError: (@MainActor @Sendable (String) -> Void)?
    var onTorchChanged: (@MainActor @Sendable (Bool) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.demarconet.weedlabel.camera.session")
    private let videoQueue = DispatchQueue(label: "com.demarconet.weedlabel.camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var device: AVCaptureDevice?

    private var configured = false
    private var armed = false                 // smart shutter active
    private var capturing = false             // a still is in flight
    private var readyStreak = 0               // consecutive "ready" frames
    private var lastAnalysis = Date.distantPast
    private var seenQRCodes: [String] = []
    private var photoContinuation: ((UIImage?) -> Void)?

    // Torch.
    private(set) var torchOn = false
    /// Auto-torch: turn on when the scene's mean luma is below this (dark).
    private let autoTorchLumaCutoff = 70.0
    private var torchIsAuto = true

    // Tuning.
    private let analysisInterval: TimeInterval = 0.25   // ~4 fps analysis
    private let minLabelFillFraction: CGFloat = 0.25    // white label must fill ≥25% of frame
    private let sharpnessThreshold: Double = 9.0        // luma-gradient variance floor
    private let readyFramesToFire = 2                   // sharp+framed frames before snap

    // MARK: - Lifecycle

    /// Request access, configure the session, start running, and arm the smart
    /// shutter. Safe to call repeatedly.
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Task { @MainActor in self.onError?("Camera access is off. Enable it in Settings to scan labels.") }
                return
            }
            self.sessionQueue.async {
                self.configureIfNeeded()
                if !self.session.isRunning { self.session.startRunning() }
                self.readyStreak = 0
                self.armed = true
                self.capturing = false
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.armed = false
            if self.torchOn { self.applyTorch(false) }
            self.torchIsAuto = true
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Re-arm the smart shutter after a rejected/low-quality capture without
    /// tearing down the session.
    func rearm() {
        sessionQueue.async {
            self.readyStreak = 0
            self.capturing = false
            self.armed = true
        }
    }

    /// Tap-to-focus at a point in normalized (0–1) device coordinates.
    func focus(atDevicePoint point: CGPoint) {
        sessionQueue.async {
            guard let device = self.device, device.isFocusPointOfInterestSupported else { return }
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch { /* best effort */ }
        }
    }

    /// Manual shutter — capture now regardless of framing (override).
    func captureNow() {
        sessionQueue.async { self.triggerPhoto() }
    }

    // MARK: - Configuration

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Prefer a virtual multi-camera (triple/dual-wide) — on supported iPhones
        // the system auto-switches to the ultra-wide for macro when you get
        // close, which the plain wide-angle can't do (its ~20cm minimum focus
        // distance is why a small label goes blurry up close). Fall back to wide.
        let cam = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let cam,
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Task { @MainActor in self.onError?("Couldn't open the camera.") }
            return
        }
        session.addInput(input)
        device = cam
        configureFocus(cam)
        camLog.notice("camdiag config: device=\(cam.localizedName, privacy: .public) minFocusDist=\(cam.minimumFocusDistance)mm virtual=\(cam.isVirtualDevice)")

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: videoQueue)
            metadataOutput.metadataObjectTypes = [.qr, .pdf417, .aztec, .dataMatrix, .code128]
        }
        session.commitConfiguration()
        configured = true
    }

    private func configureFocus(_ cam: AVCaptureDevice) {
        do {
            try cam.lockForConfiguration()
            if cam.isFocusModeSupported(.continuousAutoFocus) { cam.focusMode = .continuousAutoFocus }
            if cam.isAutoFocusRangeRestrictionSupported { cam.autoFocusRangeRestriction = .near }
            if cam.isSmoothAutoFocusSupported { cam.isSmoothAutoFocusEnabled = true }
            if cam.isExposureModeSupported(.continuousAutoExposure) { cam.exposureMode = .continuousAutoExposure }
            // Let the virtual device auto-switch to ultra-wide for macro; geometric
            // distortion correction keeps the ultra-wide frame rectilinear so OCR
            // and the deskew stay accurate.
            if cam.isGeometricDistortionCorrectionSupported {
                cam.isGeometricDistortionCorrectionEnabled = true
            }
            cam.unlockForConfiguration()
        } catch { /* best effort */ }
    }

    // MARK: - Torch

    /// Manual torch toggle from the UI (switches off auto mode).
    func setTorch(_ on: Bool) {
        sessionQueue.async {
            self.torchIsAuto = false
            self.applyTorch(on)
        }
    }

    private func applyTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            if on {
                try? device.setTorchModeOn(level: 0.7)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            torchOn = on
            Task { @MainActor in self.onTorchChanged?(on) }
        } catch { /* best effort */ }
    }

    // MARK: - Smart shutter (framing + sharpness on preview frames)

    private func triggerPhoto() {
        guard configured, !capturing else { return }
        capturing = true
        armed = false
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func report(_ framing: CaptureFraming) {
        Task { @MainActor in self.onFraming?(framing) }
    }
}

// MARK: - Preview-frame analysis (sharpness + label rectangle)

extension LabelCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard armed, !capturing else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= analysisInterval else { return }
        lastAnalysis = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let (fill, meanLuma) = Self.fillAndLuma(pixelBuffer)
        let sharpVal = Self.sharpness(pixelBuffer)
        let focusing = device?.isAdjustingFocus ?? false
        let lens = device?.lensPosition ?? -1
        let zoom = device?.videoZoomFactor ?? -1

        // Auto-torch: light up when the scene is dark (helps focus + contrast).
        if torchIsAuto {
            let wantTorch = meanLuma < autoTorchLumaCutoff
            if wantTorch != torchOn { applyTorch(wantTorch) }
        }

        // Live diagnostics — stream with: idevicesyslog | grep camdiag
        // NSLog (not Logger.notice) so it reliably reaches idevicesyslog.
        NSLog("camdiag fill=%.2f sharp=%.1f luma=%.0f focusing=%d lens=%.2f zoom=%.1f torch=%d streak=%d",
              fill, sharpVal, meanLuma, focusing ? 1 : 0, lens, zoom, self.torchOn ? 1 : 0, self.readyStreak)

        // Framing: how much of the frame the WHITE LABEL fills. The label is a
        // bright near-white block against a vivid bag; measuring brightness
        // forces the user close to the LABEL (not the bag). Hard gate.
        guard fill >= minLabelFillFraction else {
            readyStreak = 0
            report(fill > 0.06 ? .tooFar : .searching)
            return
        }

        let sharp = sharpVal >= sharpnessThreshold
        if sharp && !focusing {
            readyStreak += 1
            report(.ready)
            if readyStreak >= readyFramesToFire { triggerPhoto() }
        } else {
            readyStreak = 0
            report(.holdSteady)
        }
    }

    /// Fraction of the frame covered by the bright near-white label. NJ labels
    /// are white blocks on vivid bags, so "how much of the frame is bright"
    /// directly measures how close/centered the label is — and forces the user
    /// to fill the frame with the LABEL, not the bag. Photometry only: no text,
    /// no AI reading. Cheap, samples the luma plane on a coarse grid.
    private static func fillAndLuma(_ pixelBuffer: CVPixelBuffer) -> (fill: CGFloat, meanLuma: Double) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return (0, 0) }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let brightCutoff: UInt8 = 170     // label white vs colored bag
        let step = 8
        var bright = 0, total = 0
        var lumaSum = 0.0
        var y = 0
        while y < height {
            let row = ptr + y * rowBytes
            var x = 0
            while x < width {
                let v = row[x]
                if v >= brightCutoff { bright += 1 }
                lumaSum += Double(v)
                total += 1
                x += step
            }
            y += step
        }
        guard total > 0 else { return (0, 0) }
        return (CGFloat(bright) / CGFloat(total), lumaSum / Double(total))
    }

    /// Sharpness proxy: variance of horizontal luma gradients on a subsampled
    /// grid of the Y plane. Higher = crisper. Cheap, no allocation per pixel.
    private static func sharpness(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        // Sample the central region (where the label is) on a coarse grid.
        let x0 = width / 4, x1 = width * 3 / 4
        let y0 = height / 4, y1 = height * 3 / 4
        let step = 4
        var n = 0
        var sum = 0.0, sumSq = 0.0
        var y = y0
        while y < y1 {
            let row = ptr + y * rowBytes
            var x = x0
            while x < x1 - step {
                let g = Double(Int(row[x]) - Int(row[x + step]))
                sum += g; sumSq += g * g; n += 1
                x += step
            }
            y += step
        }
        guard n > 0 else { return 0 }
        let mean = sum / Double(n)
        return sumSq / Double(n) - mean * mean   // variance of the gradient
    }
}

// MARK: - Barcode / QR

extension LabelCamera: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for obj in metadataObjects {
            if let m = obj as? AVMetadataMachineReadableCodeObject, let s = m.stringValue,
               !seenQRCodes.contains(s) {
                seenQRCodes.append(s)
            }
        }
    }
}

// MARK: - Still capture

extension LabelCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { capturing = false }
        guard error == nil, let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in self.onError?("Capture failed — try again.") }
            return
        }
        let qrs = seenQRCodes
        let frame = CapturedFrame(image: image, qrCodes: qrs)
        Task { @MainActor in self.onCapture?(frame) }
    }
}
