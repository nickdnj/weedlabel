#if BETA
import Foundation
import UIKit

// BetaFeedback — TESTER FEEDBACK, BETA BUILDS ONLY.
//
// This entire file is wrapped in `#if BETA` and is never compiled into the App
// Store Release build (see docs/SPEC-beta-feedback.md). It exists so opted-in
// TestFlight testers can share a scan — OCR text, the parsed label, any
// corrections they made, the AI summary, a 👍/👎 + note, and the label photo —
// so we can improve extraction. Sharing is opt-OUT in beta (on by default), but
// nothing is ever sent without an explicit tap in the mail/share composer.
//
// No backend, no secrets: the payload rides out over the tester's own mail
// client. When Mail isn't configured, the view layer falls back to a share sheet.

enum BetaFeedback {
    /// Where shared scans land (a dedicated public-facing inbox, not personal mail).
    static let recipient = "vistter2@gmail.com"
    /// Opt-out switch (default ON in beta). Read via @AppStorage.
    static let shareEnabledKey = "beta.feedback.shareEnabled"
    /// First-run disclosure flag (shown once, not a gate).
    static let noticeSeenKey = "beta.feedback.noticeSeen.v1"
}

/// The structured scan record attached as `feedback.json`. The label photo is a
/// separate JPEG attachment, not embedded here, to keep the JSON small/readable.
struct ScanFeedback: Codable, Sendable {
    var ocrText: String
    var label: CannabisLabel
    var summaryText: String
    var summaryDidFallback: Bool
    /// Human-readable corrections the tester applied this session (the eval gold).
    var corrections: [String]
    /// 1 = 👍, -1 = 👎, 0 = unset.
    var rating: Int
    var note: String
    // Triage metadata.
    var appVersion: String
    var buildNumber: String
    var iosVersion: String
    var deviceModel: String
    var scannedAt: Date

    @MainActor
    init(ocrText: String,
         label: CannabisLabel,
         summary: SummaryOutcome?,
         corrections: [String],
         rating: Int,
         note: String,
         scannedAt: Date = Date()) {
        self.ocrText = ocrText
        self.label = label
        self.summaryText = summary?.text ?? ""
        self.summaryDidFallback = summary?.didFallback ?? false
        self.corrections = corrections
        self.rating = rating
        self.note = note
        let info = Bundle.main.infoDictionary
        self.appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        self.buildNumber = info?["CFBundleVersion"] as? String ?? "?"
        self.iosVersion = UIDevice.current.systemVersion
        self.deviceModel = ScanFeedback.deviceModelIdentifier()
        self.scannedAt = scannedAt
    }

    func jsonData() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(self)) ?? Data()
    }

    /// Hardware identifier like "iPhone17,1" — more useful for triage than the
    /// generic "iPhone" from UIDevice.
    private static func deviceModelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let id = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}

/// Everything the view layer needs to present a pre-filled mail composer (or the
/// share-sheet fallback). Built off the device, used by the UIKit wrappers.
struct FeedbackMailContent {
    let recipient: String
    let subject: String
    let body: String
    let jsonData: Data
    let jsonFilename: String
    let jpegData: Data?
    let jpegFilename: String

    /// Items for a `UIActivityViewController` fallback when Mail is unavailable.
    func shareItems(scratch: FileManager = .default) -> [Any] {
        var items: [Any] = [subject + "\n\n" + body]
        let dir = scratch.temporaryDirectory
        let jsonURL = dir.appendingPathComponent(jsonFilename)
        if (try? jsonData.write(to: jsonURL)) != nil { items.append(jsonURL) }
        if let jpegData {
            let jpegURL = dir.appendingPathComponent(jpegFilename)
            if (try? jpegData.write(to: jpegURL)) != nil { items.append(jpegURL) }
        }
        return items
    }
}

extension ScanFeedback {
    func mailContent(image: UIImage?) -> FeedbackMailContent {
        let ratingStr = rating > 0 ? "👍" : (rating < 0 ? "👎" : "—")
        let subject = "Pocketbud beta — scan feedback (v\(appVersion) build \(buildNumber))"
        let body = """
        \(note.isEmpty ? "(no note)" : note)

        — sent from Pocketbud beta
        rating: \(ratingStr)
        strain: \(label.strainName.isEmpty ? "(unread)" : label.strainName)
        device: \(deviceModel) · iOS \(iosVersion)
        """
        return FeedbackMailContent(
            recipient: BetaFeedback.recipient,
            subject: subject,
            body: body,
            jsonData: jsonData(),
            jsonFilename: "feedback.json",
            jpegData: image?.jpegData(compressionQuality: 0.7),
            jpegFilename: "label.jpg"
        )
    }
}
#endif
