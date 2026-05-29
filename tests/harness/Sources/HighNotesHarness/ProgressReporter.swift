import Foundation

/// Writes harness progress to the shared `.progress.json` that `progress.py watch`
/// renders live. One named "bar" per concurrent phase (OCR / Apple / Claude). All
/// writes funnel through this single actor so the overlapped Apple-serial and
/// Claude-concurrent loops never race on the file. Best-effort throughout: any IO
/// error is swallowed — progress reporting must never break or slow a run.
///
/// Schema matches progress.py exactly:
///   { "status": "running"|"done", "updated_at": <epoch>, "note": "...",
///     "bars": { "Apple": { "current", "total", "started_at", "updated_at", "label"? }, … } }
actor ProgressReporter {
    static let shared = ProgressReporter(url: defaultURL())

    private let url: URL
    private var bars: [String: [String: Any]] = [:]
    private var note: String = ""

    init(url: URL) {
        self.url = url
        // Inherit any bars an orchestrating agent already wrote (e.g. an "Overall"
        // step bar via progress.py) so we merge rather than clobber.
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let b = obj["bars"] as? [String: [String: Any]] { bars = b }
            if let n = obj["note"] as? String { note = n }
        }
    }

    static func defaultURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["HN_PROGRESS_FILE"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        // tests/harness/.progress.json — alongside the harness package root.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // HighNotesHarness
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // tests/harness
            .appendingPathComponent(".progress.json")
    }

    func setNote(_ s: String) {
        note = s
        write(status: "running")
    }

    func update(phase: String, current: Int, total: Int, label: String? = nil) {
        let now = Date().timeIntervalSince1970
        var bar = bars[phase] ?? [:]
        let prevTotal = bar["total"] as? Int
        let prevCurrent = bar["current"] as? Int ?? 0
        // Reset the clock when a bar (re)starts or its total changes → sane ETA.
        if bar["started_at"] == nil || prevTotal != total || current < prevCurrent {
            bar["started_at"] = now
        }
        bar["current"] = current
        bar["total"] = total
        bar["updated_at"] = now
        if let label { bar["label"] = label }
        bars[phase] = bar
        write(status: "running")
    }

    func finish() { write(status: "done") }

    private func write(status: String) {
        let obj: [String: Any] = [
            "status": status,
            "updated_at": Date().timeIntervalSince1970,
            "note": note,
            "bars": bars,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return }
        try? data.write(to: url, options: .atomic)  // temp-file + rename under the hood
    }
}
