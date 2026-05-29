import Foundation

// Per-label artifacts + roll-up writer. Layout:
//
//   results/<UTC-timestamp>/
//     index.md                  — roll-up across the run
//     run.json                  — machine-readable summary (score.py + Refiner read this)
//     accuracy.md               — ground-truth accuracy (emitted by score.py)
//     proposed-prompts.md       — (only with --refine)
//     <label-slug>/
//       ocr.txt                 — raw Vision OCR
//       ocr-cleaned.txt         — preprocessed+clamped OCR fed to both models (if different)
//       apple-passA.json        — composed CannabisLabel (or .txt if failed/skipped)
//       claude-passA.json       — composed CannabisLabel (or .txt if failed/skipped)
//       claude-passA-raw.txt    — raw Claude metadata+chemistry responses (if parse failed)
//       insight.json            — deterministic strain insight + sanity warning
//       apple-passB.txt         — narrative + outcome metadata
//       claude-passB.txt        — narrative + guard status
//       diff.md                 — human-readable side-by-side

struct RunResult: Sendable {
    let imagePath: String
    let imageName: String          // basename — the key score.py / ground-truth.json use
    let slug: String
    let ocrText: String
    let safeOcr: String
    let appleDuration: TimeInterval
    let claudeDuration: TimeInterval

    let applePassA: PassAOutcome
    let claudePassA: PassAOutcome
    let claudeRaw: ClaudeRaw?
    let strainInsightNote: String?  // headline + provenance, or nil
    let sanityWarning: String?
    let applePassB: PassBOutcome
    let claudePassB: PassBOutcome
    let labelDiff: LabelDiff

    struct ClaudeRaw: Sendable {
        let metadata: String
        let chemistry: String
    }

    enum PassAOutcome: Sendable {
        case ok(CannabisLabel)
        case failed(String)
        case skipped(String)

        var label: CannabisLabel? {
            if case .ok(let l) = self { return l } else { return nil }
        }
    }

    enum PassBOutcome: Sendable {
        case ok(text: String, violation: String?, didFallback: Bool, regenerations: Int)
        case failed(String)
        case skipped(String)
    }
}

enum Reporter {
    static func write(_ results: [RunResult], to runDir: URL) throws {
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        for r in results {
            try writeOne(r, under: runDir)
        }
        try writeIndex(results, under: runDir)
        try writeRunJSON(results, under: runDir)
    }

    private static func writeOne(_ r: RunResult, under runDir: URL) throws {
        let dir = runDir.appendingPathComponent(r.slug, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try r.ocrText.write(to: dir.appendingPathComponent("ocr.txt"), atomically: true, encoding: .utf8)
        if r.safeOcr != r.ocrText {
            try r.safeOcr.write(to: dir.appendingPathComponent("ocr-cleaned.txt"), atomically: true, encoding: .utf8)
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]

        try writePassA(r.applePassA, side: "apple", enc: enc, dir: dir)
        try writePassA(r.claudePassA, side: "claude", enc: enc, dir: dir)

        // When Claude's compose/parse failed, keep the raw responses so the
        // failure is diagnosable.
        if case .failed = r.claudePassA, let raw = r.claudeRaw {
            let body = "== METADATA RESPONSE ==\n\(raw.metadata)\n\n== CHEMISTRY RESPONSE ==\n\(raw.chemistry)\n"
            try body.write(to: dir.appendingPathComponent("claude-passA-raw.txt"), atomically: true, encoding: .utf8)
        }

        // Strain insight + sanity verdict (deterministic, on-device).
        var insight: [String: Any] = [:]
        insight["strainInsight"] = r.strainInsightNote ?? NSNull()
        insight["sanityWarning"] = r.sanityWarning ?? NSNull()
        let insightData = try JSONSerialization.data(withJSONObject: insight, options: [.prettyPrinted, .sortedKeys])
        try insightData.write(to: dir.appendingPathComponent("insight.json"))

        try writePassB(r.applePassB, label: "APPLE", to: dir.appendingPathComponent("apple-passB.txt"))
        try writePassB(r.claudePassB, label: "CLAUDE", to: dir.appendingPathComponent("claude-passB.txt"))

        let md = renderDiffMarkdown(r)
        try md.write(to: dir.appendingPathComponent("diff.md"), atomically: true, encoding: .utf8)
    }

    private static func writePassA(_ outcome: RunResult.PassAOutcome, side: String, enc: JSONEncoder, dir: URL) throws {
        switch outcome {
        case .ok(let label):
            let data = try enc.encode(label)
            try data.write(to: dir.appendingPathComponent("\(side)-passA.json"))
        case .failed(let msg):
            try ("FAILED: " + msg).write(to: dir.appendingPathComponent("\(side)-passA.txt"), atomically: true, encoding: .utf8)
        case .skipped(let reason):
            try ("SKIPPED: " + reason).write(to: dir.appendingPathComponent("\(side)-passA.txt"), atomically: true, encoding: .utf8)
        }
    }

    private static func writePassB(_ outcome: RunResult.PassBOutcome, label: String, to url: URL) throws {
        var lines: [String] = ["== \(label) PASS B =="]
        switch outcome {
        case .ok(let text, let violation, let didFallback, let regenerations):
            lines.append("regenerations: \(regenerations)")
            lines.append("didFallback: \(didFallback)")
            lines.append("guardOnFinalOutput: \(violation ?? "none")")
            lines.append("")
            lines.append(text)
        case .failed(let msg):
            lines.append("FAILED: \(msg)")
        case .skipped(let reason):
            lines.append("SKIPPED: \(reason)")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Markdown rendering

    private static func renderDiffMarkdown(_ r: RunResult) -> String {
        var lines: [String] = []
        lines.append("# Diff — \(r.slug)")
        lines.append("")
        lines.append("Image: `\(r.imagePath)`  ")
        lines.append("Apple duration: \(format(r.appleDuration))s  ")
        lines.append("Claude duration: \(format(r.claudeDuration))s  ")
        if let note = r.strainInsightNote { lines.append("Strain insight: \(note)  ") }
        if let warn = r.sanityWarning { lines.append("Sanity: ⚠️ \(warn)  ") }
        lines.append("")
        lines.append("## OCR (cleaned, fed to both)")
        lines.append("```")
        lines.append(r.safeOcr)
        lines.append("```")
        lines.append("")
        lines.append("## Pass A — field-by-field (post-pipeline)")
        lines.append("")
        lines.append("| Field | Apple | Claude | Status |")
        lines.append("|---|---|---|---|")
        for f in r.labelDiff.fields {
            let badge: String
            switch f.status {
            case .bothNull: badge = "·"
            case .agree: badge = "✓ agree"
            case .disagree: badge = "✗ disagree"
            case .onlyApple: badge = "+ apple only"
            case .onlyClaude: badge = "+ claude only"
            }
            lines.append("| \(f.name) | \(escapeMD(f.apple ?? "—")) | \(escapeMD(f.claude ?? "—")) | \(badge) |")
        }
        lines.append("")

        switch r.applePassA {
        case .failed(let m): lines.append("> Apple Pass A failed: \(m)")
        case .skipped(let reason): lines.append("> Apple Pass A skipped: \(reason)")
        case .ok: break
        }
        switch r.claudePassA {
        case .failed(let m): lines.append("> Claude Pass A failed: \(m)")
        case .skipped(let reason): lines.append("> Claude Pass A skipped: \(reason)")
        case .ok: break
        }
        lines.append("")

        lines.append("## Pass B — narratives")
        lines.append("")
        lines.append("**Apple:**")
        lines.append("")
        lines.append(passBQuote(r.applePassB))
        lines.append("")
        lines.append("**Claude:**")
        lines.append("")
        lines.append(passBQuote(r.claudePassB))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func passBQuote(_ outcome: RunResult.PassBOutcome) -> String {
        switch outcome {
        case .ok(let text, let violation, let didFallback, let regenerations):
            var head = "> _regens: \(regenerations)"
            if didFallback { head += ", grounded-fallback" }
            if let v = violation { head += ", guard tripped: \(v)" }
            head += "_"
            return head + "\n>\n> " + text.replacingOccurrences(of: "\n", with: "\n> ")
        case .failed(let msg): return "> FAILED: \(msg)"
        case .skipped(let reason): return "> SKIPPED: \(reason)"
        }
    }

    private static func escapeMD(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    private static func format(_ d: TimeInterval) -> String { String(format: "%.2f", d) }

    // MARK: - Roll-up

    private static func writeIndex(_ results: [RunResult], under runDir: URL) throws {
        var lines: [String] = []
        lines.append("# Run — \(runDir.lastPathComponent)")
        lines.append("")
        lines.append("Labels processed: \(results.count)  ")
        let appleA = results.filter { if case .ok = $0.applePassA { return true } else { return false } }.count
        let claudeA = results.filter { if case .ok = $0.claudePassA { return true } else { return false } }.count
        lines.append("Apple Pass A success: \(appleA) / \(results.count)  ")
        lines.append("Claude Pass A success: \(claudeA) / \(results.count)  ")
        let totalDisagree = results.flatMap { $0.labelDiff.disagreements }.count
        lines.append("Total Pass A field disagreements: \(totalDisagree)  ")
        lines.append("")
        lines.append("> Apple-vs-Claude agreement is a PROXY, not ground truth. Chasing it can")
        lines.append("> pull Apple toward Claude's errors. See `accuracy.md` (score.py) for")
        lines.append("> Apple-correct% vs Claude-correct% against hand-authored ground truth.")
        lines.append("")
        lines.append("## Per-field disagreement rate")
        lines.append("")
        lines.append("| Field | Agree | Disagree | Apple-only | Claude-only | Both null |")
        lines.append("|---|---:|---:|---:|---:|---:|")
        for key in LabelComparator.scalarKeys {
            var agree = 0, disagree = 0, ao = 0, co = 0, bn = 0
            for r in results {
                if let f = r.labelDiff.fields.first(where: { $0.name == key }) {
                    switch f.status {
                    case .agree: agree += 1
                    case .disagree: disagree += 1
                    case .onlyApple: ao += 1
                    case .onlyClaude: co += 1
                    case .bothNull: bn += 1
                    }
                }
            }
            lines.append("| \(key) | \(agree) | \(disagree) | \(ao) | \(co) | \(bn) |")
        }
        lines.append("")
        lines.append("## Labels")
        lines.append("")
        for r in results {
            let dCount = r.labelDiff.disagreements.count
            let flag = dCount == 0 ? "✓" : "Δ\(dCount)"
            lines.append("- [\(flag) \(r.imageName)](./\(r.slug)/diff.md)")
        }
        try lines.joined(separator: "\n").write(to: runDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
    }

    private static func writeRunJSON(_ results: [RunResult], under runDir: URL) throws {
        var arr: [[String: Any]] = []
        for r in results {
            var item: [String: Any] = [
                "image": r.imageName,       // score.py / ground-truth.json key
                "slug": r.slug,
                "imagePath": r.imagePath,
            ]
            item["apple"] = passAToJSON(r.applePassA)
            item["claude"] = passAToJSON(r.claudePassA)
            var diffs: [[String: Any]] = []
            for f in r.labelDiff.fields where f.status != .agree && f.status != .bothNull {
                diffs.append([
                    "field": f.name,
                    "apple": f.apple ?? NSNull(),
                    "claude": f.claude ?? NSNull(),
                    "status": f.status.rawValue,
                ])
            }
            item["passADisagreements"] = diffs
            item["applePassB"] = passBToJSON(r.applePassB)
            item["claudePassB"] = passBToJSON(r.claudePassB)
            item["sanityWarning"] = r.sanityWarning ?? NSNull()
            arr.append(item)
        }
        let data = try JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: runDir.appendingPathComponent("run.json"))
    }

    private static func passAToJSON(_ outcome: RunResult.PassAOutcome) -> [String: Any] {
        switch outcome {
        case .ok(let label):
            let enc = JSONEncoder()
            if let data = try? enc.encode(label), let obj = try? JSONSerialization.jsonObject(with: data) {
                return ["status": "ok", "label": obj]
            }
            return ["status": "ok", "label": NSNull()]
        case .failed(let m): return ["status": "failed", "message": m]
        case .skipped(let reason): return ["status": "skipped", "reason": reason]
        }
    }

    private static func passBToJSON(_ outcome: RunResult.PassBOutcome) -> [String: Any] {
        switch outcome {
        case .ok(let text, let violation, let didFallback, let regenerations):
            return [
                "status": "ok",
                "text": text,
                "violation": violation ?? NSNull(),
                "didFallback": didFallback,
                "regenerations": regenerations,
            ]
        case .failed(let m): return ["status": "failed", "message": m]
        case .skipped(let reason): return ["status": "skipped", "reason": reason]
        }
    }
}
