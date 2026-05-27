#if DEBUG
import SwiftUI
import UIKit

// PromptLabView — Debug-only in-app tool for iterating on the FM extraction and
// summary prompts without rebuilding. Lets you edit the system instructions
// for both stages, edit the OCR input, toggle the preprocessor, run the
// pipeline, and inspect the parsed CannabisLabel JSON + AI summary.
//
// Intentionally rough around the edges. This is a dev tool, not a product
// surface — remove before App Store submission.

@MainActor
@Observable
final class PromptLabModel {
    enum RunSlot: String, Sendable {
        case edited
        case baseline
    }

    enum RunState {
        case idle
        case running(stage: String)
        case complete(extraction: ExtractionService.CustomRunResult, summary: SummaryService.CustomRunResult?)
        case failed(stage: String, message: String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    var extractionInstructions: String
    var summaryInstructions: String
    var ocrText: String
    var applyPreprocessor: Bool = true
    var runSummary: Bool = true

    /// Result of running with the user-edited instructions.
    var editedRun: RunState = .idle
    /// Result of running with the baked-in default instructions (for A/B
    /// comparison while iterating).
    var baselineRun: RunState = .idle

    var showResetConfirm: Bool = false
    var lastCopyToast: String?

    private let extraction = ExtractionService()
    private let summary = SummaryService()

    init() {
        self.extractionInstructions = ExtractionService.promptLabDefaultInstructions
        self.summaryInstructions = SummaryService.systemInstructions
        self.ocrText = Self.bundledCanaryOcr() ?? "(paste OCR text here)"
    }

    // MARK: - Edit helpers

    func resetToDefaults() {
        extractionInstructions = ExtractionService.promptLabDefaultInstructions
        summaryInstructions = SummaryService.systemInstructions
        ocrText = Self.bundledCanaryOcr() ?? "(paste OCR text here)"
        applyPreprocessor = true
        runSummary = true
        editedRun = .idle
        baselineRun = .idle
    }

    func loadCanaryOcr() {
        if let text = Self.bundledCanaryOcr() {
            ocrText = text
        }
    }

    // MARK: - Clipboard

    func copyExtractionPrompt() {
        UIPasteboard.general.string = extractionInstructions
        flashCopy("Extraction prompt copied")
    }

    func copySummaryPrompt() {
        UIPasteboard.general.string = summaryInstructions
        flashCopy("Summary prompt copied")
    }

    func copyJSON(from state: RunState) {
        guard case .complete(let extraction, _) = state else { return }
        UIPasteboard.general.string = extraction.label.diagnosticJSON
        flashCopy("Parsed JSON copied")
    }

    private func flashCopy(_ message: String) {
        lastCopyToast = message
        let key = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            // Only clear if the toast hasn't been replaced by a newer message.
            if self?.lastCopyToast == key {
                self?.lastCopyToast = nil
            }
        }
    }

    // MARK: - Run

    func run(slot: RunSlot) {
        // Snapshot the inputs at call time so any subsequent user edits don't
        // race with the in-flight task.
        let ocrText = self.ocrText
        let usePreprocessor = self.applyPreprocessor
        let alsoRunSummary = self.runSummary
        let extractionInstructions = slot == .edited
            ? self.extractionInstructions
            : ExtractionService.promptLabDefaultInstructions
        let summaryInstructions = slot == .edited
            ? self.summaryInstructions
            : SummaryService.systemInstructions

        setRunState(.running(stage: "extraction"), for: slot)
        Task { [weak self] in
            guard let self else { return }
            do {
                let extractionResult = try await self.extraction.extractWithCustomInstructions(
                    rawOcrText: ocrText,
                    instructions: extractionInstructions,
                    applyPreprocessor: usePreprocessor
                )
                if !alsoRunSummary {
                    self.setRunState(.complete(extraction: extractionResult, summary: nil), for: slot)
                    return
                }
                self.setRunState(.running(stage: "summary"), for: slot)
                do {
                    let summaryResult = try await self.summary.summarizeWithCustomInstructions(
                        extractionResult.label,
                        instructions: summaryInstructions
                    )
                    self.setRunState(.complete(extraction: extractionResult, summary: summaryResult), for: slot)
                } catch {
                    self.setRunState(.failed(stage: "summary", message: error.localizedDescription), for: slot)
                }
            } catch {
                self.setRunState(.failed(stage: "extraction", message: error.localizedDescription), for: slot)
            }
        }
    }

    private func setRunState(_ state: RunState, for slot: RunSlot) {
        switch slot {
        case .edited: editedRun = state
        case .baseline: baselineRun = state
        }
    }

    private static func bundledCanaryOcr() -> String? {
        guard let url = Bundle.main.url(
            forResource: "zips-blue-candy-rain.ocr",
            withExtension: "txt",
            subdirectory: "validation"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

struct PromptLabView: View {
    @State private var model = PromptLabModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    runStatusBanner(label: "Edited", state: model.editedRun)
                    if !isIdle(model.baselineRun) {
                        runStatusBanner(label: "Baseline", state: model.baselineRun)
                    }

                    sectionHeader("OCR Input", trailing: AnyView(
                        Button("Load canary") { model.loadCanaryOcr() }
                            .font(.caption)
                    ))
                    Toggle("Apply OCR preprocessor", isOn: $model.applyPreprocessor)
                        .font(.caption)
                    monoEditor(text: $model.ocrText, minHeight: 140)

                    sectionHeader("Extraction system instructions", trailing: AnyView(
                        Button { model.copyExtractionPrompt() } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .font(.caption)
                    ))
                    monoEditor(text: $model.extractionInstructions, minHeight: 220)

                    Toggle("Also run summary", isOn: $model.runSummary)
                        .font(.caption)

                    if model.runSummary {
                        sectionHeader("Summary system instructions", trailing: AnyView(
                            Button { model.copySummaryPrompt() } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .font(.caption)
                        ))
                        monoEditor(text: $model.summaryInstructions, minHeight: 180)
                    }

                    resultsSection
                }
                .padding(16)
                .padding(.bottom, 140)
            }
            .navigationTitle("Prompt Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            model.copyExtractionPrompt()
                        } label: {
                            Label("Copy extraction prompt", systemImage: "doc.on.doc")
                        }
                        Button {
                            model.copySummaryPrompt()
                        } label: {
                            Label("Copy summary prompt", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) {
                            model.showResetConfirm = true
                        } label: {
                            Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                runButtonBar
            }
            .confirmationDialog(
                "Discard all edits and reload defaults?",
                isPresented: $model.showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    model.resetToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            }
            .overlay(alignment: .top) {
                if let toast = model.lastCopyToast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 60)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.lastCopyToast)
        }
    }

    // MARK: - Status

    private func isIdle(_ s: PromptLabModel.RunState) -> Bool {
        if case .idle = s { return true }
        return false
    }

    private func runStatusBanner(label: String, state: PromptLabModel.RunState) -> some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .running(let stage):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(label) — running \(stage)…").font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            case .failed(let stage, let message):
                Label("\(label) \(stage) failed: \(message)", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            case .complete:
                Label("\(label) run complete", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        let hasResults = !isIdle(model.editedRun) || !isIdle(model.baselineRun)
        if hasResults {
            Divider().padding(.vertical, 8)
            sectionHeader("Results", trailing: nil)

            resultColumn(title: "Edited", state: model.editedRun, palette: .editedPalette)
            if !isIdle(model.baselineRun) {
                resultColumn(title: "Baseline (defaults)", state: model.baselineRun, palette: .baselinePalette)
            }
        }
    }

    @ViewBuilder
    private func resultColumn(title: String, state: PromptLabModel.RunState, palette: ResultPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Spacer()
                if case .complete = state {
                    Button {
                        model.copyJSON(from: state)
                    } label: {
                        Label("Copy JSON", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                }
            }

            if case .complete(let extraction, let summary) = state {
                Text("Parsed CannabisLabel")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                monoOutput(text: extraction.label.diagnosticJSON, minHeight: 200)

                if extraction.preprocessorChangedInput {
                    Text("Cleaned OCR (after preprocessor)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    monoOutput(text: extraction.cleanedOcr, minHeight: 80)
                }

                if let summary {
                    HStack {
                        Text("AI summary")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let violation = summary.violation {
                            Text("Violation: \(violation)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        } else {
                            Text("Clean")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    monoOutput(text: summary.rawResponse, minHeight: 80)
                }
            } else if case .failed(let stage, let message) = state {
                Text("\(stage) failed: \(message)")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(palette.accent.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Run bar

    @ViewBuilder
    private var runButtonBar: some View {
        let isAnyRunning = model.editedRun.isRunning || model.baselineRun.isRunning
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: { model.run(slot: .edited) }) {
                    HStack {
                        if model.editedRun.isRunning {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(model.editedRun.isRunning ? "Running…" : "Run").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(isAnyRunning)

                Button(action: { model.run(slot: .baseline) }) {
                    HStack {
                        if model.baselineRun.isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play")
                        }
                        Text("Baseline").font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: 130)
                    .padding(.vertical, 14)
                    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .disabled(isAnyRunning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, trailing: AnyView?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing { trailing }
        }
    }

    private func monoEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: minHeight)
            .padding(8)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.1), lineWidth: 1)
            )
            .scrollContentBackground(.hidden)
    }

    private func monoOutput(text: String, minHeight: CGFloat) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(8)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.1), lineWidth: 1)
            )
            .textSelection(.enabled)
    }
}

private struct ResultPalette {
    let accent: Color
    let background: Color

    static let editedPalette = ResultPalette(
        accent: Color(red: 0.26, green: 0.22, blue: 0.79),
        background: Color(red: 0.93, green: 0.92, blue: 1.0).opacity(0.4)
    )
    static let baselinePalette = ResultPalette(
        accent: Color.secondary,
        background: Color.secondary.opacity(0.08)
    )
}

#Preview {
    PromptLabView()
}

#endif
