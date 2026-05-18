import SwiftUI

// ContentView — root view for the spike. Single-screen flow that dispatches
// based on ScanModel.Phase. No SwiftData persistence yet (spike scope per
// design doc Approach A).

struct ContentView: View {
    @State private var model = ScanModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch model.phase {
                case .idle(let availability):
                    IdleView(availability: availability) {
                        model.refreshAvailability()
                        model.startScan()
                    }

                case .scanning:
                    DataScannerView(
                        onCapture: { ocr, qrs in
                            model.handleCapture(ocr: ocr, qrCodes: qrs)
                        },
                        onError: { err in
                            model.cancel()
                        }
                    )
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        scanGuidance
                    }
                    .overlay(alignment: .bottom) {
                        Button("Cancel") { model.cancel() }
                            .padding(.bottom, 24)
                            .foregroundStyle(.white)
                    }

                case .parsing:
                    ProgressOverlay(title: "Reading label…", subtitle: "Extracting structured fields")

                case .sanityChecking:
                    ProgressOverlay(title: "Checking values…", subtitle: nil)

                case .summarizing:
                    ProgressOverlay(title: "Generating AI summary…", subtitle: "On-device, nothing leaves your phone")

                case .ready(let label, let summary):
                    PostScanView(label: label, summary: summary) {
                        model.cancel()
                    }

                case .verifyHint(let label, let reason):
                    VerifyHintView(label: label, reason: reason) {
                        model.cancel()
                    }

                case .failed(let message):
                    FailedView(message: message) {
                        model.cancel()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { model.refreshAvailability() }
    }

    private var scanGuidance: some View {
        Text("Hold the label flat in frame")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(.top, 16)
    }
}

// MARK: - Subviews

private struct IdleView: View {
    let availability: FMAvailability
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 16)
            Text("weedlabel")
                .font(.largeTitle.weight(.semibold))
            Text("NJ cannabis label scanner")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
                .background(.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

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

private struct VerifyHintView: View {
    let label: CannabisLabel
    let reason: String
    let onReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Verify against the printed label")
                    .font(.title2.weight(.semibold))
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                ParsedFieldsList(label: label)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Scan again", action: onReset)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(20)
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
                if let v = label.batchOrLot { row("Batch/Lot", v) }
                if let v = label.netWeight { row("Net weight", v) }
                if let v = label.harvestDate { row("Harvested", v) }
                if let v = label.expirationDate { row("Expires", v) }
            }
            Divider()
            Group {
                if let v = label.cannabinoids.thca { row("THCA", "\(v)%") }
                if let v = label.cannabinoids.delta9thc { row("Δ9-THC", "\(v)%") }
                if let v = label.cannabinoids.cbg { row("CBG", "\(v)%") }
                if let v = label.cannabinoids.cbd { row("CBD", "\(v)%") }
                if let v = label.cannabinoids.totalCannabinoids { row("Total cannabinoids", "\(v)%") }
                if let v = label.computedTotalThc { row("Computed Total THC", String(format: "%.2f%%", v)) }
            }
            Divider()
            Group {
                if let v = label.terpenes.myrcene { row("Myrcene", "\(v)%") }
                if let v = label.terpenes.limonene { row("Limonene", "\(v)%") }
                if let v = label.terpenes.linalool { row("Linalool", "\(v)%") }
                if let v = label.terpenes.betaCaryophyllene { row("β-caryophyllene", "\(v)%") }
                if let v = label.terpenes.total { row("Total terpenes", "\(v)%") }
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
