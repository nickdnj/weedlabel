import Foundation

// Refiner — given a finished run, build a meta-prompt for Claude that includes
// the CURRENT production instructions verbatim + a digest of where Apple and
// Claude disagreed, and ask for CONCRETE, QUOTED edits to the upstream prompts.
//
// Output is written to proposed-prompts.md and is NEVER auto-applied. Auto-
// application is a foot-gun for prompt regressions.
//
// THE #1 LESSON (carried over from VinoLabel, paid for in real regressions):
//   - Prefer DETERMINISTIC reference/knowledge rules (StrainKnowledgeBase,
//     StrainNameFixer, ProductTypeInference, OCRPreprocessor, the swap-fixers)
//     over prompt edits. Prompt edits plateau.
//   - Negative-example banlists REGURGITATE: telling the model "do not write X"
//     measurably INCREASES X. Never propose a banlist.
//   - VALIDATE every proposed edit against the harness before adopting — several
//     of VinoLabel's auto-proposed edits regressed and were reverted; the real
//     wins came from deterministic backfill and recovering a field from OCR.
// These are encoded into the system prompt below so the refiner internalizes them.

enum Refiner {
    static func refine(results: [RunResult], client: ClaudeClient) async throws -> String {
        let digest = buildDigest(results)
        let meta = metaPrompt(digest: digest)
        return try await client.respond(system: refinerSystem, user: meta, maxTokensOverride: 4000)
    }

    static let refinerSystem: String = """
    You are a prompt-engineer reviewing an on-device LLM extraction pipeline for \
    cannabis labels. The pipeline uses Apple's Foundation Models (a small \
    on-device model) in TWO extraction passes — Pass A-metadata extracts a \
    LabelMetadata struct (strain name, cultivator, product type, weight, dates, \
    license, Metrc tag), Pass A-chemistry extracts a LabelChemistry struct \
    (cannabinoid + terpene percentages) — composed into one CannabisLabel. A \
    third pass (Pass B) writes a short, factual, non-medical aroma/chemistry \
    summary from the parsed label. You will see the CURRENT system instructions \
    for all three plus a comparison digest of where Apple disagreed with a Claude \
    reference run using the SAME prompts.

    BEFORE proposing any prompt edit, check the failure-reasons section. If \
    Apple's failures are dominated by INFRASTRUCTURE errors — context-window \
    overflow, timeouts, session/cache errors, JSON/schema decode failures, model \
    unavailability — those are NOT prompt problems; say so in a "Diagnosis" \
    section and propose NO prompt edits for that pass; recommend the infra fix.

    THREE HARD-WON RULES you MUST follow:
    1. PREFER DETERMINISTIC CODE OVER PROMPT EDITS. This pipeline already has \
       deterministic post-processing — OCRPreprocessor (OCR noise fixes), \
       StrainNameFixer (recover a real name when the model picks a terpene name), \
       ProductTypeInference (printed dosage form wins), fixSwappedThcFields \
       (THCA/Total-THC/Δ9 swaps), StrainKnowledgeBase (sativa/indica/hybrid). If a \
       disagreement pattern can be fixed by extending one of these deterministic \
       rules (e.g. a new OCR substitution, a known-category ⇒ implied-field \
       backfill, recovering a null field from the OCR text), RECOMMEND THAT — as a \
       concrete code rule — instead of a prompt edit. Deterministic wins are \
       durable; prompt edits plateau.
    2. NEVER propose a negative-example banlist. Listing "do not output X / never \
       write Y" phrases measurably INCREASES those outputs (regurgitation). State \
       desired behavior positively and minimally.
    3. EVERY proposed edit is a HYPOTHESIS to be validated against this harness \
       before adoption. Label each edit with how to validate it and what field \
       accuracy it should move. Do not present edits as certain.

    Propose CONCRETE, MINIMAL edits. Do NOT rewrite wholesale. Do NOT add new \
    schema fields. Do NOT weaken the Pass B safety guardrails (no medical claims, \
    no dosing, no second-person) — they are load-bearing product/legal claims.

    Output format — Markdown:

    # Proposed refinements

    ## Diagnosis
    One paragraph: infrastructure vs content-shaped, citing specific failure-reason \
    counts. If infrastructure-dominated, name the fix and stop for that pass.

    ## Deterministic rules (preferred)
    For each: **Pattern** (cite labels) · **Rule** (concrete code change to \
    OCRPreprocessor / StrainNameFixer / ProductTypeInference / a backfill) · \
    **Validate** (which field % it should move).

    ## Pass A-metadata / Pass A-chemistry / Pass B prompt edits (only if no \
    deterministic rule fits)
    ### Edit N: <title>
    **Why:** <2-3 sentences citing specific labels> \
    **Current rule:** > <quoted> \
    **Proposed rule:** > <quoted replacement> \
    **Risk / validate:** <one line>

    ## Patterns I did not change
    Bulleted, one-line reason each.

    Be conservative. Fewer than two clear supporting cases → propose nothing for \
    that pass.
    """

    private static func metaPrompt(digest: Digest) -> String {
        var parts: [String] = []
        parts.append("CURRENT Pass A-metadata instructions (ExtractionService.metadataInstructions):")
        parts.append("```")
        parts.append(ExtractionService.metadataInstructions)
        parts.append("```")
        parts.append("")
        parts.append("CURRENT Pass A-chemistry instructions (ExtractionService.chemistryInstructions):")
        parts.append("```")
        parts.append(ExtractionService.chemistryInstructions)
        parts.append("```")
        parts.append("")
        parts.append("CURRENT Pass B instructions (SummaryService.systemInstructions):")
        parts.append("```")
        parts.append(SummaryService.systemInstructions)
        parts.append("```")
        parts.append("")
        parts.append("Run digest — \(digest.totalLabels) labels processed.")
        parts.append("Apple Pass A success: \(digest.appleAOk)/\(digest.totalLabels); Claude Pass A success: \(digest.claudeAOk)/\(digest.totalLabels).")
        parts.append("Apple Pass B fallbacks: \(digest.applePassBFallbacks); Apple Pass B guard trips: \(digest.applePassBGuardTrips).")
        parts.append("Claude Pass B guard trips (run through the same guards): \(digest.claudePassBGuardTrips).")
        parts.append("")

        if !digest.appleAFailureReasons.isEmpty {
            parts.append("Apple Pass A failure reasons (Apple returned no label):")
            for (reason, count) in digest.appleAFailureReasons.sorted(by: { $0.value > $1.value }) {
                parts.append("- \(count)× \"\(reason)\"")
            }
            parts.append("")
        }
        if !digest.applePassBFailureReasons.isEmpty {
            parts.append("Apple Pass B failure reasons:")
            for (reason, count) in digest.applePassBFailureReasons.sorted(by: { $0.value > $1.value }) {
                parts.append("- \(count)× \"\(reason)\"")
            }
            parts.append("")
        }

        parts.append("Per-field disagreement counts (out of \(digest.totalLabels)):")
        for (k, v) in digest.fieldDisagreementCounts.sorted(by: { ($0.value.total) > ($1.value.total) }) where v.total > 0 {
            parts.append("- \(k): disagree=\(v.disagree), apple-only=\(v.appleOnly), claude-only=\(v.claudeOnly)")
        }
        parts.append("")
        parts.append("Up to \(digest.examples.count) illustrative cases:")
        for ex in digest.examples {
            parts.append("---")
            parts.append("Label: \(ex.slug)")
            parts.append("OCR (truncated):")
            parts.append(ex.ocrExcerpt)
            if let f = ex.appleAFailureReason {
                parts.append("Apple Pass A FAILED: \(f)")
            } else {
                parts.append("Apple Pass A: \(ex.appleA ?? "—")")
            }
            if let f = ex.claudeAFailureReason {
                parts.append("Claude Pass A FAILED: \(f)")
            } else {
                parts.append("Claude Pass A: \(ex.claudeA ?? "—")")
            }
            if !ex.disagreementSummary.isEmpty {
                parts.append("Disagreements: \(ex.disagreementSummary)")
            }
            if let f = ex.applePassBFailureReason {
                parts.append("Apple Pass B FAILED: \(f)")
            } else if let ap = ex.applePassB {
                parts.append("Apple Pass B: \(ap)")
            }
            if let cp = ex.claudePassB {
                parts.append("Claude Pass B: \(cp)")
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Digest

    struct FieldCounts { var disagree: Int; var appleOnly: Int; var claudeOnly: Int
        var total: Int { disagree + appleOnly + claudeOnly } }
    struct Example {
        let slug: String
        let ocrExcerpt: String
        let appleA: String?
        let claudeA: String?
        let appleAFailureReason: String?
        let claudeAFailureReason: String?
        let disagreementSummary: String
        let applePassB: String?
        let claudePassB: String?
        let applePassBFailureReason: String?
    }
    struct Digest {
        let totalLabels: Int
        let appleAOk: Int
        let claudeAOk: Int
        let applePassBFallbacks: Int
        let applePassBGuardTrips: Int
        let claudePassBGuardTrips: Int
        let fieldDisagreementCounts: [String: FieldCounts]
        let appleAFailureReasons: [String: Int]
        let applePassBFailureReasons: [String: Int]
        let examples: [Example]
    }

    private static let maxExamples = 12

    private static func buildDigest(_ results: [RunResult]) -> Digest {
        let total = results.count
        let appleAOk = results.filter { if case .ok = $0.applePassA { return true } else { return false } }.count
        let claudeAOk = results.filter { if case .ok = $0.claudePassA { return true } else { return false } }.count
        var applePBFb = 0, applePBGuard = 0, claudePBGuard = 0
        var appleAFailureReasons: [String: Int] = [:]
        var applePassBFailureReasons: [String: Int] = [:]
        for r in results {
            if case .ok(_, let v, let fb, _) = r.applePassB {
                if fb { applePBFb += 1 }
                if v != nil { applePBGuard += 1 }
            }
            if case .failed(let msg) = r.applePassB { applePassBFailureReasons[msg, default: 0] += 1 }
            if case .failed(let msg) = r.applePassA { appleAFailureReasons[msg, default: 0] += 1 }
            if case .ok(_, let v, _, _) = r.claudePassB, v != nil { claudePBGuard += 1 }
        }
        var counts: [String: FieldCounts] = [:]
        for r in results {
            for f in r.labelDiff.fields {
                var c = counts[f.name] ?? FieldCounts(disagree: 0, appleOnly: 0, claudeOnly: 0)
                switch f.status {
                case .disagree: c.disagree += 1
                case .onlyApple: c.appleOnly += 1
                case .onlyClaude: c.claudeOnly += 1
                default: break
                }
                counts[f.name] = c
            }
        }
        let failures = results.filter { if case .failed = $0.applePassA { return true } else { return false } }
        let nonFailures = results.filter { if case .failed = $0.applePassA { return false } else { return true } }
            .sorted { $0.labelDiff.disagreements.count > $1.labelDiff.disagreements.count }
        let failureBudget = min(maxExamples / 2, failures.count)
        let picked = Array(failures.prefix(failureBudget)) + Array(nonFailures.prefix(maxExamples - failureBudget))
        let examples: [Example] = picked.map { r in
            Example(
                slug: r.imageName,
                ocrExcerpt: String(r.safeOcr.prefix(700)),
                appleA: compactJSON(for: r.applePassA),
                claudeA: compactJSON(for: r.claudePassA),
                appleAFailureReason: failureReason(for: r.applePassA),
                claudeAFailureReason: failureReason(for: r.claudePassA),
                disagreementSummary: r.labelDiff.disagreements.map { "\($0.name): apple=\($0.apple ?? "—") vs claude=\($0.claude ?? "—")" }.joined(separator: "; "),
                applePassB: textIfOk(r.applePassB),
                claudePassB: textIfOk(r.claudePassB),
                applePassBFailureReason: passBFailureReason(for: r.applePassB)
            )
        }
        return Digest(
            totalLabels: total, appleAOk: appleAOk, claudeAOk: claudeAOk,
            applePassBFallbacks: applePBFb, applePassBGuardTrips: applePBGuard,
            claudePassBGuardTrips: claudePBGuard,
            fieldDisagreementCounts: counts,
            appleAFailureReasons: appleAFailureReasons,
            applePassBFailureReasons: applePassBFailureReasons,
            examples: examples
        )
    }

    private static func failureReason(for outcome: RunResult.PassAOutcome) -> String? {
        if case .failed(let m) = outcome { return m }
        return nil
    }
    private static func passBFailureReason(for outcome: RunResult.PassBOutcome) -> String? {
        if case .failed(let m) = outcome { return m }
        return nil
    }
    private static func compactJSON(for outcome: RunResult.PassAOutcome) -> String? {
        guard case .ok(let label) = outcome else { return nil }
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        guard let data = try? enc.encode(label), let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
    private static func textIfOk(_ outcome: RunResult.PassBOutcome) -> String? {
        if case .ok(let text, _, _, _) = outcome { return text }
        return nil
    }
}
