import SwiftUI
import PhotosUI

// ContentView — root view for the spike. Single-screen flow that dispatches
// based on ScanModel.Phase. No SwiftData persistence yet (spike scope per
// design doc Approach A).

struct ContentView: View {
    @State private var model = ScanModel()
    #if DEBUG
    @State private var showPromptLab: Bool = false
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
                        onRunCanary: {
                            #if DEBUG
                            model.refreshAvailability()
                            model.runBundledCanary()
                            #endif
                        },
                        onOpenPromptLab: {
                            #if DEBUG
                            showPromptLab = true
                            #endif
                        },
                        onImport: { model.importPickedImage($0) }
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
                        summary: summary,
                        sanityWarning: sanityWarning,
                        strainInsight: strainInsight,
                        onSetStrainClass: { model.setStrainClass($0) },
                        onClearStrainClass: { model.clearStrainClass() },
                        onSetProductType: { model.setProductType($0) },
                        onReset: { model.cancel() }
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
            if CommandLine.arguments.contains("-OpenPromptLab") {
                showPromptLab = true
            }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $showPromptLab) {
            PromptLabView()
        }
        #endif
    }

}

// MARK: - Scanning

private struct ScanningView: View {
    let model: ScanModel

    var body: some View {
        ZStack {
            DataScannerView(
                onTextUpdate: { ocr, qrs in
                    model.handleTextUpdate(ocr: ocr, qrCodes: qrs)
                },
                onError: { _ in
                    model.cancel()
                },
                scannerController: model.scannerController
            )
            .ignoresSafeArea()

            // Dim the camera outside the viewfinder. Brackets indicate the
            // active OCR region.
            ViewfinderOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                FieldChipsRow(detected: model.detectedFields)
                    .padding(.top, 20)
                Spacer()
                ScannerControls(
                    canCapture: model.canCapture,
                    detectedCount: model.detectedFields.count,
                    totalFields: DetectedField.allCases.count,
                    isAutoCapturePending: model.isAutoCapturePending,
                    autoCaptureDuration: ScanModel.autoCaptureDebounceSeconds,
                    onCapture: { model.confirmCapture() },
                    onCancel: { model.cancel() }
                )
            }
        }
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
    let onRunCanary: () -> Void
    let onOpenPromptLab: () -> Void
    let onImport: (UIImage) -> Void
    @State private var showAbout = false
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Brand.gradient)
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
            #if DEBUG
            HStack(spacing: 12) {
                Button(action: onRunCanary) {
                    HStack {
                        Image(systemName: "testtube.2")
                        Text("Run canary")
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                Button(action: onOpenPromptLab) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Prompt Lab")
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .padding(.top, 10)
            .foregroundStyle(.secondary)
            #endif
            Spacer().frame(height: 32)
        }
        .overlay(alignment: .topTrailing) {
            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            .accessibilityLabel("About HighNotes")
        }
        .sheet(isPresented: $showAbout) { AboutView() }
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
            Group {
                if let v = label.thca { row("THCA", "\(v)%") }
                if let v = label.delta9thc { row("Δ9-THC", "\(v)%") }
                if let v = label.cbg { row("CBG", "\(v)%") }
                if let v = label.cbd { row("CBD", "\(v)%") }
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
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.footnote).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text(value).font(.callout)
            Spacer()
        }
    }
}
