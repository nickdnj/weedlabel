import SwiftUI
import PhotosUI

// ContentView — root view for the spike. Single-screen flow that dispatches
// based on ScanModel.Phase. No SwiftData persistence yet (spike scope per
// design doc Approach A).

struct ContentView: View {
    @State private var model = ScanModel()
    #if DEBUG
    // Launch with `-ShowLogBook` to open the Log Book sheet directly (fast
    // visual iteration), mirroring `-AutoRunCanary` / `-ShowTipJar`.
    @State private var showLogBookDebug = false
    #endif

    #if BETA
    // Beta tester-feedback (opt-out, on by default). Prompts after the tester is
    // done with a result so their corrections are captured. Compiled out of the
    // App Store build — see docs/SPEC-beta-feedback.md.
    @AppStorage(BetaFeedback.shareEnabledKey) private var betaShareEnabled = true
    @AppStorage(BetaFeedback.noticeSeenKey) private var betaNoticeSeen = false
    @State private var showBetaPrompt = false
    @State private var showBetaNotice = false
    @State private var pendingFinish: (() -> Void)?
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch model.phase {
                case .idle(let availability):
                    IdleView(
                        availability: availability,
                        onScan: {
                            model.refreshAvailability()
                            model.startScan()
                        },
                        onImport: { model.importPickedImage($0) },
                        onClearData: { model.clearLocalData() }
                    )

                case .scanning:
                    ScanningView(model: model)

                case .capturing:
                    ProgressOverlay(title: "Capturing…", subtitle: "Taking a sharp photo of the label")

                case .previewing(let ocr, let qrs):
                    PreviewView(
                        ocrText: ocr,
                        qrCodes: qrs,
                        detectedFields: model.detectedFields,
                        capturedImage: model.capturedImage,
                        onProcess: { model.processCapture() },
                        onRescan: { model.rescan() },
                        onCancel: { model.cancel() }
                    )

                case .parsing:
                    ProgressOverlay(title: "Reading label…", subtitle: "Extracting structured fields")

                case .sanityChecking:
                    ProgressOverlay(title: "Checking values…", subtitle: nil)

                case .summarizing:
                    ProgressOverlay(title: "Generating AI summary…", subtitle: "On-device, nothing leaves your phone")

                case .ready(let label, let summary, let sanityWarning, let strainInsight):
                    PostScanView(
                        label: label,
                        ocrText: model.lastSeenOcr,
                        summary: summary,
                        sanityWarning: sanityWarning,
                        strainInsight: strainInsight,
                        onSetStrainClass: { model.setStrainClass($0) },
                        onClearStrainClass: { model.clearStrainClass() },
                        onSetProductType: { model.setProductType($0) },
                        onSetStrainName: { model.setStrainName($0) },
                        onSetCannabinoid: { model.setCannabinoidValue($0, $1) },
                        onSave: { finishScan(model.saveToLogBook) },
                        onReset: { finishScan(model.cancel) }
                    )

                case .failed(let message):
                    FailedView(message: message) {
                        model.cancel()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            model.refreshAvailability()
            #if DEBUG
            if CommandLine.arguments.contains("-AutoRunCanary") {
                print("[CANARY] Auto-run flag detected — invoking runBundledCanary()")
                model.runBundledCanary()
            }
            if CommandLine.arguments.contains("-ShowLogBook") { showLogBookDebug = true }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $showLogBookDebug) { LogBookView() }
        #endif
        #if BETA
        .sheet(isPresented: $showBetaNotice, onDismiss: {
            // Swipe-dismissing the notice (without tapping "Got it") shouldn't
            // strand the finish action; only chain to the prompt when it's queued.
            if !showBetaPrompt { runPendingFinish() }
        }) {
            BetaConsentView {
                betaNoticeSeen = true
                showBetaNotice = false
                showBetaPrompt = true
            }
        }
        .sheet(isPresented: $showBetaPrompt, onDismiss: { runPendingFinish() }) {
            if case .ready(let label, let summary, _, _) = model.phase {
                BetaFeedbackPrompt(
                    ocrText: model.lastSeenOcr,
                    label: label,
                    summary: summary,
                    corrections: model.appliedCorrections,
                    image: model.capturedImage,
                    onDismiss: { showBetaPrompt = false }
                )
            }
        }
        #endif
    }

    #if BETA
    /// When sharing is enabled, intercept the "done with this result" action to
    /// first offer the feedback prompt (and a one-time notice). The finish action
    /// runs once the sheet is dismissed, so the .ready data stays valid meanwhile.
    private func finishScan(_ action: @escaping () -> Void) {
        guard betaShareEnabled else { action(); return }
        pendingFinish = action
        if betaNoticeSeen { showBetaPrompt = true } else { showBetaNotice = true }
    }

    private func runPendingFinish() {
        let action = pendingFinish
        pendingFinish = nil
        action?()
    }
    #else
    private func finishScan(_ action: @escaping () -> Void) { action() }
    #endif

}

// MARK: - Scanning

private struct ScanningView: View {
    let model: ScanModel

    var body: some View {
        ZStack {
            // AVFoundation preview — focus-first, no live OCR. Tap to focus.
            CameraPreviewView(camera: model.labelCamera)
                .ignoresSafeArea()

            // Brackets indicate where to place the label.
            ViewfinderOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                CaptureHintBanner(framing: model.framing, hint: model.captureHint)
                    .padding(.top, 24)
                #if DEBUG
                CameraDiagHUD(diag: model.cameraDiag)
                    .padding(.top, 8)
                #endif
                Spacer()
                CaptureControls(
                    framing: model.framing,
                    onCapture: { model.confirmCapture() },
                    onCancel: { model.cancel() }
                )
            }
        }
    }
}

/// One-line guidance above the viewfinder: framing state, or a retake hint.
private struct CaptureHintBanner: View {
    let framing: CaptureFraming
    let hint: String?

    var body: some View {
        Text(hint ?? message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
            .multilineTextAlignment(.center)
    }

    private var message: String {
        switch framing {
        case .searching: return "Point at the label"
        case .tooFar:    return "Move closer — fill the box with the label"
        case .holdSteady: return "Bring the label into focus…"
        case .locking:   return "Hold steady…"
        case .ready:     return "Capturing…"
        }
    }
}

#if DEBUG
/// On-screen live camera telemetry — the reliable real-time debug channel while
/// tuning focus/framing on device. DEBUG-only.
private struct CameraDiagHUD: View {
    let diag: CameraDiag

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "fill %.2f   sharp %.1f   luma %.0f", diag.fill, diag.sharp, diag.luma))
            Text(String(format: "lens %.2f   zoom %.1f   %@%@", diag.lens, diag.zoom,
                        diag.focusing ? "FOCUSING " : "", diag.torch ? "TORCH" : ""))
            Text("active: \(diag.activeLens)")
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif

/// Cancel + manual shutter. The shutter glows green when the smart shutter is
/// about to fire (framed + sharp); tapping it captures immediately.
private struct CaptureControls: View {
    let framing: CaptureFraming
    let onCapture: () -> Void
    let onCancel: () -> Void

    private var lockProgress: CGFloat {
        if case .locking(let p) = framing { return CGFloat(p) }
        return framing == .ready ? 1 : 0
    }
    private var isReady: Bool { framing == .ready }

    var body: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel").font(.body.weight(.medium)).foregroundStyle(.white)
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            Button(action: onCapture) {
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.4), lineWidth: 4).frame(width: 74, height: 74)
                    // Lock progress ring fills as you hold steady.
                    Circle()
                        .trim(from: 0, to: lockProgress)
                        .stroke(Brand.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 74, height: 74)
                        .animation(.linear(duration: 0.2), value: lockProgress)
                    Circle().fill(isReady ? Brand.green : Color.white)
                        .frame(width: 60, height: 60)
                }
            }
            .accessibilityLabel("Capture")

            Spacer()

            Color.clear.frame(width: 80, height: 1)   // balances Cancel
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 40)
    }
}

private struct ViewfinderOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.78
            let height = geo.size.height * 0.42
            let frame = CGRect(
                x: (geo.size.width - width) / 2,
                y: (geo.size.height - height) / 2,
                width: width,
                height: height
            )
            ZStack {
                // Punched-out dim mask
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: frame.width, height: frame.height)
                                    .position(x: frame.midX, y: frame.midY)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    }
                // Corner brackets
                CornerBrackets()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }
}

private struct CornerBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let len: CGFloat = 28
            let thick: CGFloat = 3
            let color = Color.white.opacity(0.95)
            ZStack {
                // Top-left
                Path { p in
                    p.move(to: .init(x: 0, y: len))
                    p.addLine(to: .init(x: 0, y: 0))
                    p.addLine(to: .init(x: len, y: 0))
                }.stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round))

                // Top-right
                Path { p in
                    p.move(to: .init(x: geo.size.width - len, y: 0))
                    p.addLine(to: .init(x: geo.size.width, y: 0))
                    p.addLine(to: .init(x: geo.size.width, y: len))
                }.stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round))

                // Bottom-left
                Path { p in
                    p.move(to: .init(x: 0, y: geo.size.height - len))
                    p.addLine(to: .init(x: 0, y: geo.size.height))
                    p.addLine(to: .init(x: len, y: geo.size.height))
                }.stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round))

                // Bottom-right
                Path { p in
                    p.move(to: .init(x: geo.size.width - len, y: geo.size.height))
                    p.addLine(to: .init(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: .init(x: geo.size.width, y: geo.size.height - len))
                }.stroke(color, style: StrokeStyle(lineWidth: thick, lineCap: .round))
            }
        }
    }
}

struct FieldChipsRow: View {
    let detected: Set<DetectedField>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DetectedField.allCases, id: \.self) { field in
                let isOn = detected.contains(field)
                HStack(spacing: 4) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.caption2.weight(.semibold))
                    Text(field.displayName)
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isOn ? Color.green.opacity(0.85) : Color.black.opacity(0.5))
                )
                .foregroundStyle(.white)
            }
        }
    }
}

private struct ScannerControls: View {
    let canCapture: Bool
    let detectedCount: Int
    let totalFields: Int
    let isAutoCapturePending: Bool
    let autoCaptureDuration: Double
    let onCapture: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(guidanceText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())

            HStack {
                Button("Cancel") { onCancel() }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.45), in: Capsule())

                Spacer()

                ShutterButton(
                    canCapture: canCapture,
                    isAutoCapturePending: isAutoCapturePending,
                    autoCaptureDuration: autoCaptureDuration,
                    onTap: onCapture
                )

                Spacer()

                // Spacer-balance for the Cancel button so the shutter stays centered.
                Color.clear.frame(width: 80, height: 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var guidanceText: String {
        if isAutoCapturePending {
            return "Hold steady — auto-capturing…"
        }
        if detectedCount == totalFields {
            return "All fields detected"
        }
        if canCapture {
            return "Looks good — tap to capture, or wait for all fields"
        }
        switch detectedCount {
        case 0: return "Center the label in the frame"
        case 1: return "Hold steady — keep more of the label in view"
        default: return "Almost there — get the full label in frame"
        }
    }
}

private struct ShutterButton: View {
    let canCapture: Bool
    let isAutoCapturePending: Bool
    let autoCaptureDuration: Double
    let onTap: () -> Void

    @State private var ringFill: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer ring (static)
                Circle()
                    .stroke(Color.white.opacity(0.95), lineWidth: 4)
                    .frame(width: 72, height: 72)

                // Auto-capture countdown ring — fills clockwise from 12 o'clock
                // over the debounce period.
                if isAutoCapturePending {
                    Circle()
                        .trim(from: 0, to: ringFill)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                }

                // Inner fill
                Circle()
                    .fill(canCapture ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 58, height: 58)
            }
        }
        .disabled(!canCapture)
        .accessibilityLabel("Capture")
        .onChange(of: isAutoCapturePending) { _, pending in
            if pending {
                ringFill = 0
                withAnimation(.linear(duration: autoCaptureDuration)) {
                    ringFill = 1
                }
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    ringFill = 0
                }
            }
        }
    }
}

// MARK: - Subviews

private struct IdleView: View {
    let availability: FMAvailability
    let onScan: () -> Void
    let onImport: (UIImage) -> Void
    let onClearData: () -> Void
    @State private var showAbout = false
    @State private var showLogBook = false
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PocketbudMark(size: 66)
                .padding(.bottom, 14)
            Text(Brand.name)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.gradient)
            Text(Brand.tagline)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Spacer()
            if availability != .available {
                Text(availability.copy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
            Button(action: onScan) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Scan a label")
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)

            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("Import from Photos")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    if let data, let image = UIImage(data: data) {
                        onImport(image)
                    }
                    pickedItem = nil
                }
            }

            Button { showLogBook = true } label: {
                HStack {
                    Image(systemName: "books.vertical")
                    Text("Log Book")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            Spacer().frame(height: 32)
        }
        .overlay(alignment: .topTrailing) {
            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            .accessibilityLabel("About \(Brand.name)")
        }
        .sheet(isPresented: $showAbout) { AboutView(onClearData: onClearData) }
        .sheet(isPresented: $showLogBook) { LogBookView() }
    }
}

// MARK: - Preview / Confirm

private struct PreviewView: View {
    let ocrText: String
    let qrCodes: [String]
    let detectedFields: Set<DetectedField>
    var capturedImage: UIImage?
    let onProcess: () -> Void
    let onRescan: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .padding(8)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("Confirm capture")
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 30, height: 1) // visual balance
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let capturedImage {
                        Image(uiImage: capturedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.primary.opacity(0.1), lineWidth: 1)
                            )
                    }

                    Text("Captured \(ocrText.count) characters" + (qrCodes.isEmpty ? "" : ", \(qrCodes.count) QR"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FieldChipsRow(detected: detectedFields)

                    Text("OCR text")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Text(ocrText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button(action: onRescan) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Re-scan")
                    }
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .foregroundStyle(.primary)
                }

                Button(action: onProcess) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Process")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Status / failure overlays

private struct ProgressOverlay: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct FailedView: View {
    let message: String
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Try again", action: onReset)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 32)
        }
    }
}

struct ParsedFieldsList: View {
    let label: CannabisLabel
    /// OCR the label was read from — source for the potency value pick-list.
    var ocrText: String = ""
    /// Apply a user correction to a cannabinoid value (nil clears it).
    var onSetCannabinoid: (CannabisLabel.CannabinoidField, Double?) -> Void = { _, _ in }

    @State private var editingField: CannabisLabel.CannabinoidField?
    @State private var typingField: CannabisLabel.CannabinoidField?
    @State private var valueDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                row("Strain", label.strainName)
                row("Cultivator", label.cultivator)
                if let v = label.licenseNumber { row("License", v) }
                if let v = label.metrcTag { row("Metrc", v) }
                if let v = label.netWeight { row("Net weight", v) }
                if let v = label.harvestDate { row("Harvested", v) }
                if let v = label.expirationDate { row("Expires", v) }
            }
            Divider()
            // Tap a potency value to pick the right number straight off the label
            // — fixes the OCR column-desyncs without typing.
            Group {
                potencyRow(.thca)
                potencyRow(.delta9thc)
                potencyRow(.totalThc)
                potencyRow(.cbg)
                potencyRow(.cbd)
                if let v = label.totalCannabinoids { row("Total cannabinoids", "\(v)%") }
                if let v = label.computedTotalThc { row("Computed Total THC", String(format: "%.2f%%", v)) }
            }
            Divider()
            Group {
                if let v = label.myrcene { row("Myrcene", "\(v)%") }
                if let v = label.limonene { row("Limonene", "\(v)%") }
                if let v = label.linalool { row("Linalool", "\(v)%") }
                if let v = label.betaCaryophyllene { row("β-caryophyllene", "\(v)%") }
                if let v = label.totalTerpenes { row("Total terpenes", "\(v)%") }
            }
            if !label.qrCodes.isEmpty {
                Divider()
                row("QR codes", "\(label.qrCodes.count) detected")
            }
        }
        .confirmationDialog(
            "Pick the value from the label",
            isPresented: Binding(get: { editingField != nil }, set: { if !$0 { editingField = nil } }),
            titleVisibility: .visible,
            presenting: editingField
        ) { field in
            ForEach(CannabisLabel.candidatePotencyValues(for: field, ocrText: ocrText), id: \.self) { v in
                Button(String(format: "%.2f%%", v)) { onSetCannabinoid(field, v) }
            }
            Button("Type a value…") {
                valueDraft = label.cannabinoidValue(field).map { String($0) } ?? ""
                typingField = field
            }
            Button("Clear", role: .destructive) { onSetCannabinoid(field, nil) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Edit value", isPresented: Binding(get: { typingField != nil }, set: { if !$0 { typingField = nil } })) {
            TextField("Percent", text: $valueDraft)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let f = typingField {
                    let cleaned = valueDraft.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                    onSetCannabinoid(f, Double(cleaned))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A tappable cannabinoid value row — shows "—" when unread so the user can
    /// add it. Opens the pick-from-label dialog.
    private func potencyRow(_ field: CannabisLabel.CannabinoidField) -> some View {
        Button { editingField = field } label: {
            HStack {
                Text(field.displayName).font(.footnote).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                Text(label.cannabinoidValue(field).map { String(format: "%.2f%%", $0) } ?? "—")
                    .font(.callout).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "pencil").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.footnote).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text(value).font(.callout)
            Spacer()
        }
    }
}
