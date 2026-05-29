import Foundation

// HighNotesHarness — local macOS 26 batch harness. Runs every fixture cannabis
// label through BOTH the on-device Apple Foundation Models chain (the PRODUCTION
// ExtractionService + deterministic post-processing + SummaryService) and the
// Claude API with the SAME prompts, then diffs and scores them.
//
// Usage:
//   swift run HighNotesHarness                       # default fixtures, no refine
//   swift run HighNotesHarness --limit 3             # smoke test
//   swift run HighNotesHarness --refine              # also propose prompt edits
//   swift run HighNotesHarness --model claude-sonnet-4-6
//   swift run HighNotesHarness --include-pattern 0774
//   swift run HighNotesHarness --skip-apple          # Claude-only sanity run
//   swift run HighNotesHarness --claude-concurrency 4

struct CLIOptions {
    var imagesDir: URL
    var outputDir: URL
    var includePattern: String?
    var limit: Int?
    var model: String = "claude-opus-4-7"
    var refine: Bool = false
    var skipApple: Bool = false
    /// Max concurrent Claude+OCR label stages. Apple Foundation Models stays
    /// strictly serial regardless (the on-device model dislikes overlapped
    /// sessions); only the network-bound Claude side is parallelized.
    var claudeConcurrency: Int = 6

    static func parse(_ argv: [String]) -> CLIOptions {
        // Resolve defaults relative to the harness package dir via this source
        // file's compile-time path — robust to whatever CWD `swift run` uses.
        let harnessRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // HighNotesHarness
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // tests/harness
        // Fixtures default to the repo's real validation labels.
        var imagesDir = harnessRoot.appendingPathComponent("../../assets/validation").standardizedFileURL
        var outputDir = harnessRoot.appendingPathComponent("results").standardizedFileURL
        var includePattern: String?
        var limit: Int?
        var model = "claude-opus-4-7"
        var refine = false
        var skipApple = false
        var claudeConcurrency = 6

        var i = 1
        while i < argv.count {
            switch argv[i] {
            case "--images": i += 1; imagesDir = URL(fileURLWithPath: argv[i]).standardizedFileURL
            case "--output": i += 1; outputDir = URL(fileURLWithPath: argv[i]).standardizedFileURL
            case "--include-pattern": i += 1; includePattern = argv[i]
            case "--limit": i += 1; limit = Int(argv[i])
            case "--model": i += 1; model = argv[i]
            case "--refine": refine = true
            case "--skip-apple": skipApple = true
            case "--claude-concurrency": i += 1; claudeConcurrency = max(1, Int(argv[i]) ?? 6)
            case "--help", "-h": print(Self.helpText); exit(0)
            default:
                FileHandle.standardError.write(Data("unknown argument: \(argv[i])\n".utf8)); exit(2)
            }
            i += 1
        }
        return CLIOptions(imagesDir: imagesDir, outputDir: outputDir, includePattern: includePattern,
                          limit: limit, model: model, refine: refine, skipApple: skipApple,
                          claudeConcurrency: claudeConcurrency)
    }

    static let helpText = """
    HighNotesHarness — HighNotes AI-chain comparison harness (Apple FM vs Claude)

    Options:
      --images <dir>            Image fixtures dir (default: ../../assets/validation)
      --output <dir>            Output root (default: ./results)
      --include-pattern <s>     Only process files whose path contains <s>
      --limit <n>               Process at most N labels
      --model <id>              Claude model id (default: claude-opus-4-7)
      --refine                  After the run, call Claude to propose prompt edits
      --skip-apple              Skip the Foundation Models side (Claude only)
      --claude-concurrency <n>  Max concurrent Claude+OCR stages (default 6).
                                Apple Foundation Models always stays serial.
      --help                    This help
    """
}

@main
struct HighNotesHarnessApp {
    static func main() async {
        let opts = CLIOptions.parse(CommandLine.arguments)
        do {
            try await Run.go(opts: opts)
        } catch {
            FileHandle.standardError.write(Data("Run failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

enum Run {
    static func go(opts: CLIOptions) async throws {
        log("HighNotesHarness starting.")
        log("Images: \(opts.imagesDir.path)")
        log("Output: \(opts.outputDir.path)")

        let images = try discoverImages(in: opts.imagesDir, pattern: opts.includePattern, limit: opts.limit)
        guard !images.isEmpty else {
            log("No images found under \(opts.imagesDir.path).")
            return
        }
        log("Found \(images.count) image(s) to process.")

        let availability = AvailabilityGate.current()
        let appleEnabled = !opts.skipApple && availability == .available
        if opts.skipApple {
            log("Apple Pass A/B will be skipped (--skip-apple).")
        } else if availability != .available {
            log("Foundation Models unavailable: \(String(describing: availability)). Apple side skipped per-label.")
        } else {
            log("Foundation Models available.")
        }

        let claude = try ClaudeClient(config: .fromEnv(model: opts.model))
        log("Claude model: \(opts.model)")

        // ONE shared ExtractionService/SummaryService reused across ALL labels —
        // mirroring the app, where ScanModel holds a single long-lived instance
        // for the whole session. This is also a regression test for the session-
        // lifecycle fix: the services now create a fresh LanguageModelSession per
        // call, so a reused instance no longer accumulates context and decays to
        // empty (the bug this harness originally surfaced). If extraction starts
        // dying after ~5 labels again, that fix regressed.
        let extractor = ExtractionService()
        let summarizer = SummaryService()
        if appleEnabled {
            await extractor.warm()
            await summarizer.warm()
        }

        let timestamp = isoStampForFilename()
        let runDir = opts.outputDir.appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        log("Writing to \(runDir.path)")

        let appleUnavailableReason = availability == .available ? nil : String(describing: availability)
        let n = images.count
        let concurrency = max(1, min(opts.claudeConcurrency, n))

        // STAGE 0 — OCR every label concurrently. Vision is local + cheap and
        // both downstream halves need the text, so we do it once up front.
        log("Stage 0: OCR \(n) label(s)…")
        var ocrSlots = [OCRStage?](repeating: nil, count: n)
        await withTaskGroup(of: OCRStage.self) { group in
            var next = 0
            func launch(_ i: Int) { let u = images[i]; group.addTask { await ocrStage(idx: i, url: u) } }
            while next < concurrency { launch(next); next += 1 }
            while let s = await group.next() {
                ocrSlots[s.idx] = s
                if next < n { launch(next); next += 1 }
            }
        }
        let ocr = ocrSlots.compactMap { $0 }.sorted { $0.idx < $1.idx }

        // STAGES A + C — OVERLAPPED via async let. The Apple half (strictly
        // serial Foundation Models) and the Claude half (concurrent network)
        // share nothing mutable, so they run at the same time. Wall-clock ≈
        // max(Apple-serial, Claude-concurrent), not the sum.
        log("Stages A‖C: Apple FM (serial) running alongside Claude (concurrency \(concurrency))…")
        async let appleHalves: [AppleHalf] = runAppleSerial(
            ocr: ocr, extractor: extractor, summarizer: summarizer,
            appleEnabled: appleEnabled, appleUnavailableReason: appleUnavailableReason, total: n)
        async let claudeHalves: [ClaudeHalf] = runClaudeConcurrent(
            ocr: ocr, claude: claude, concurrency: concurrency, total: n)
        let apples = await appleHalves
        let claudes = await claudeHalves

        // ASSEMBLE — zip the two halves by index, preserving label order.
        var appleByIdx: [Int: AppleHalf] = [:]; for a in apples { appleByIdx[a.idx] = a }
        var claudeByIdx: [Int: ClaudeHalf] = [:]; for c in claudes { claudeByIdx[c.idx] = c }
        var results: [RunResult] = []
        for o in ocr {
            guard let a = appleByIdx[o.idx], let c = claudeByIdx[o.idx] else { continue }
            let diff = LabelComparator.diff(apple: a.passA.label, claude: c.passA.label)
            results.append(RunResult(
                imagePath: o.url.path, imageName: o.url.lastPathComponent, slug: slug(for: o.url),
                ocrText: o.ocrText, safeOcr: o.safeOcr,
                appleDuration: a.duration, claudeDuration: c.duration,
                applePassA: a.passA, claudePassA: c.passA, claudeRaw: c.raw,
                strainInsightNote: a.strainInsightNote, sanityWarning: a.sanityWarning,
                applePassB: a.passB, claudePassB: c.passB, labelDiff: diff))
        }

        try Reporter.write(results, to: runDir)
        log("Wrote run report to \(runDir.appendingPathComponent("index.md").path)")

        emitAccuracy(runDir: runDir)

        if opts.refine {
            log("Generating proposed prompt refinements via Claude…")
            let md = try await Refiner.refine(results: results, client: claude)
            try md.write(to: runDir.appendingPathComponent("proposed-prompts.md"), atomically: true, encoding: .utf8)
            log("Wrote \(runDir.appendingPathComponent("proposed-prompts.md").path)")
        }

        log("Done.")
    }

    /// Shell out to score.py to emit accuracy.md beside run.json. Best-effort:
    /// no-ops quietly if python3 or the script can't be found.
    private static func emitAccuracy(runDir: URL) {
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: #filePath)            // .../Sources/HighNotesHarness/Main.swift
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("score.py"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("score.py"),
        ]
        guard let script = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            log("accuracy: score.py not found; skipping accuracy.md")
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", script.path, runDir.appendingPathComponent("run.json").path, "--emit"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run(); proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                log("Wrote \(runDir.appendingPathComponent("accuracy.md").path)")
            } else {
                log("accuracy: score.py exited \(proc.terminationStatus); skipping")
            }
        } catch {
            log("accuracy: could not run score.py (\(error.localizedDescription)); skipping")
        }
    }

    // MARK: - Per-label halves (Sendable so Apple-serial and Claude-concurrent overlap)

    struct OCRStage: Sendable {
        let idx: Int; let url: URL
        let ocrText: String; let safeOcr: String; let qrCodes: [String]; let ocrError: String?
    }
    struct AppleHalf: Sendable {
        let idx: Int
        let passA: RunResult.PassAOutcome
        let duration: TimeInterval
        let passB: RunResult.PassBOutcome
        let strainInsightNote: String?
        let sanityWarning: String?
    }
    struct ClaudeHalf: Sendable {
        let idx: Int
        let passA: RunResult.PassAOutcome
        let duration: TimeInterval
        let passB: RunResult.PassBOutcome
        let raw: RunResult.ClaudeRaw?
    }

    /// OCR one label (local Vision). Never throws — captures failure inline.
    private static func ocrStage(idx: Int, url: URL) async -> OCRStage {
        do {
            let r = try await MacImageOCR.recognize(at: url)
            return OCRStage(idx: idx, url: url, ocrText: r.ocrText,
                            safeOcr: safeOCR(r.ocrText), qrCodes: r.qrCodes, ocrError: nil)
        } catch {
            return OCRStage(idx: idx, url: url, ocrText: "", safeOcr: "", qrCodes: [],
                            ocrError: error.localizedDescription)
        }
    }

    // MARK: - Apple side (STRICTLY SERIAL)

    private static func runAppleSerial(
        ocr: [OCRStage], extractor: ExtractionService, summarizer: SummaryService,
        appleEnabled: Bool, appleUnavailableReason: String?, total: Int
    ) async -> [AppleHalf] {
        var out: [AppleHalf] = []; out.reserveCapacity(ocr.count)
        for (k, o) in ocr.enumerated() {
            out.append(await appleHalf(o: o, extractor: extractor, summarizer: summarizer,
                                       appleEnabled: appleEnabled, appleUnavailableReason: appleUnavailableReason))
            if (k + 1) % 5 == 0 || k + 1 == ocr.count { log("  Apple \(k + 1)/\(total)") }
        }
        return out
    }

    private static func appleHalf(
        o: OCRStage, extractor: ExtractionService, summarizer: SummaryService,
        appleEnabled: Bool, appleUnavailableReason: String?
    ) async -> AppleHalf {
        let start = Date()
        var label: CannabisLabel?
        let passA: RunResult.PassAOutcome
        if let e = o.ocrError {
            passA = .failed("OCR failed: \(e)")
        } else if !appleEnabled {
            passA = .skipped(appleUnavailableReason ?? "--skip-apple")
        } else {
            do {
                let raw = try await extractor.extract(rawOcrText: o.ocrText)
                let cleaned = Pipeline.postProcess(raw, ocrText: o.ocrText, qrCodes: o.qrCodes)
                label = cleaned
                passA = .ok(cleaned)
            } catch { passA = .failed(error.localizedDescription) }
        }
        let dur = Date().timeIntervalSince(start)

        // Deterministic insight + sanity (computed on Apple's label — the app
        // ships Apple's output, so these are the values surfaced to the user).
        var insight: StrainInsight?
        var sanityWarning: String?
        if let label {
            insight = Pipeline.strainInsight(for: label, ocrText: o.ocrText)
            sanityWarning = Pipeline.sanityWarning(for: label)
        }
        let insightNote = insight.map { "\($0.headline) [\($0.sourceNote)]" }

        // Pass B — grounds on Apple's own label + insight. Sanity does NOT block
        // it (matches the app; the %-hallucination guard is the safety net).
        let passB: RunResult.PassBOutcome
        if !appleEnabled {
            passB = .skipped(appleUnavailableReason ?? "--skip-apple")
        } else if let label {
            do {
                let outcome = try await summarizer.summarize(label, strainInsight: insight)
                switch outcome {
                case .ai(let text, let regens):
                    passB = .ok(text: text, violation: nil, didFallback: false, regenerations: regens)
                case .deterministicFallback(let text, let regens):
                    passB = .ok(text: text, violation: "guard tripped → fallback", didFallback: true, regenerations: regens)
                }
            } catch { passB = .failed(error.localizedDescription) }
        } else {
            passB = .skipped("no Apple Pass A label")
        }

        return AppleHalf(idx: o.idx, passA: passA, duration: dur, passB: passB,
                         strainInsightNote: insightNote, sanityWarning: sanityWarning)
    }

    // MARK: - Claude side (CONCURRENT, bounded)

    private static func runClaudeConcurrent(
        ocr: [OCRStage], claude: ClaudeClient, concurrency: Int, total: Int
    ) async -> [ClaudeHalf] {
        var out: [ClaudeHalf] = []; out.reserveCapacity(ocr.count)
        var done = 0
        await withTaskGroup(of: ClaudeHalf.self) { group in
            var next = 0
            func launch(_ k: Int) {
                let o = ocr[k]
                group.addTask { await claudeHalf(o: o, claude: claude) }
            }
            while next < min(concurrency, ocr.count) { launch(next); next += 1 }
            while let h = await group.next() {
                out.append(h); done += 1
                if done % 5 == 0 || done == ocr.count { log("  Claude \(done)/\(total)") }
                if next < ocr.count { launch(next); next += 1 }
            }
        }
        return out
    }

    private static func claudeHalf(o: OCRStage, claude: ClaudeClient) async -> ClaudeHalf {
        if let e = o.ocrError {
            return ClaudeHalf(idx: o.idx, passA: .failed("OCR failed: \(e)"),
                              duration: 0, passB: .skipped("no OCR"), raw: nil)
        }
        let start = Date()
        var label: CannabisLabel?
        var raw: RunResult.ClaudeRaw?
        let passA: RunResult.PassAOutcome
        do {
            let res = try await ClaudeChain.extractViaClaude(safeOcr: o.safeOcr, client: claude)
            raw = RunResult.ClaudeRaw(metadata: res.metadataRaw, chemistry: res.chemistryRaw)
            if let l = res.label {
                // SAME deterministic post-processing as the Apple side, so the
                // comparison is end-of-pipeline rather than raw model output.
                let cleaned = Pipeline.postProcess(l, ocrText: o.ocrText, qrCodes: o.qrCodes)
                label = cleaned
                passA = .ok(cleaned)
            } else {
                passA = .failed(res.parseError ?? "no label produced")
            }
        } catch { passA = .failed(error.localizedDescription) }
        let dur = Date().timeIntervalSince(start)

        let passB: RunResult.PassBOutcome
        if let label {
            let insight = Pipeline.strainInsight(for: label, ocrText: o.ocrText)
            do {
                let res = try await ClaudeChain.summarizeViaClaude(label: label, strainInsight: insight, client: claude)
                // Claude has no on-device regenerate/fallback loop; we flag the
                // guard result for parity rather than mutating the output.
                passB = .ok(text: res.text, violation: res.violation, didFallback: false, regenerations: 0)
            } catch { passB = .failed(error.localizedDescription) }
        } else {
            passB = .skipped("no Claude Pass A label")
        }
        return ClaudeHalf(idx: o.idx, passA: passA, duration: dur, passB: passB, raw: raw)
    }

    // MARK: - Helpers

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff"]

    static func discoverImages(in dir: URL, pattern: String?, limit: Int?) throws -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [URL] = []
        for case let u as URL in en {
            if u.hasDirectoryPath { continue }
            guard imageExtensions.contains(u.pathExtension.lowercased()) else { continue }
            if let p = pattern, !u.path.localizedCaseInsensitiveContains(p) { continue }
            out.append(u)
        }
        out.sort { $0.path < $1.path }
        if let limit { out = Array(out.prefix(limit)) }
        return out
    }

    /// File-system-safe slug from the image basename (keeps parent dir so files
    /// in different fixture folders don't collide).
    private static func slug(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let base = url.deletingPathExtension().lastPathComponent
        let joined = "\(parent)__\(base)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(joined.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    /// Matches ExtractionService.preprocessedOCR: clean then clamp to 2000 chars.
    /// This is the byte-identical text the Claude side receives, so both models
    /// see the same input.
    private static func safeOCR(_ raw: String) -> String {
        let cleaned = OCRPreprocessor.clean(raw)
        return cleaned.count > 2000 ? String(cleaned.prefix(2000)) : cleaned
    }

    private static func isoStampForFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    static func log(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}
