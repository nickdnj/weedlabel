import UIKit

// LogImageStore — on-device storage for the scanned-label images shown in the
// Log Book. Mirrors the FileLogStore pattern: plain files in Documents, no
// backend (the "100% on-device" claim holds — nothing leaves the device).
//
// Lifecycle is tied to the LogEntry: an image is written when the user saves a
// scan (ScanModel.saveToLogBook) and deleted when the entry is deleted
// (FileLogStore.delete/removeAll). Two files per entry: a downscaled full image
// for the detail screen and a small thumbnail for the list, so scrolling the
// Log Book doesn't decode multi-megapixel JPEGs per row.

enum LogImageStore {
    /// Longest edge of the stored "full" image. Labels are read at OCR time; the
    /// saved copy is only for human review, so a moderate cap keeps storage and
    /// decode cost down while staying legible.
    private static let fullMaxEdge: CGFloat = 1400
    private static let thumbMaxEdge: CGFloat = 240
    private static let fullQuality: CGFloat = 0.7
    private static let thumbQuality: CGFloat = 0.6

    /// `Documents/images/`, created on demand.
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL { directory.appendingPathComponent(filename) }

    /// Thumbnail filename derived from the full filename ("<id>.jpg" → "<id>_thumb.jpg").
    static func thumbName(for full: String) -> String {
        full.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
    }

    /// Write the full + thumbnail JPEGs for an entry. Returns the full filename
    /// to store on the LogEntry, or nil if encoding/writing failed (saving the
    /// entry still proceeds image-less).
    @discardableResult
    static func save(_ image: UIImage, id: UUID) -> String? {
        let full = "\(id.uuidString).jpg"
        guard let fullData = downscaled(image, maxEdge: fullMaxEdge).jpegData(compressionQuality: fullQuality) else {
            return nil
        }
        do {
            try fullData.write(to: url(for: full), options: [.atomic])
        } catch {
            return nil
        }
        // Thumbnail is best-effort — a missing thumb just falls back to the full.
        if let thumbData = downscaled(image, maxEdge: thumbMaxEdge).jpegData(compressionQuality: thumbQuality) {
            try? thumbData.write(to: url(for: thumbName(for: full)), options: [.atomic])
        }
        return full
    }

    /// Write the full original photo for an entry (no thumbnail — it's only shown
    /// on demand on the detail screen). Filename "<id>_orig.jpg".
    @discardableResult
    static func saveOriginal(_ image: UIImage, id: UUID) -> String? {
        let name = "\(id.uuidString)_orig.jpg"
        guard let data = downscaled(image, maxEdge: fullMaxEdge).jpegData(compressionQuality: fullQuality) else {
            return nil
        }
        do {
            try data.write(to: url(for: name), options: [.atomic])
            return name
        } catch {
            return nil
        }
    }

    static func loadFull(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    static func loadThumbnail(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: thumbName(for: filename)).path)
            ?? loadFull(filename)
    }

    /// Remove both files for an entry (called on delete).
    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
        try? FileManager.default.removeItem(at: url(for: thumbName(for: filename)))
    }

    // MARK: - Helpers

    /// Aspect-preserving downscale so the longest edge is ≤ maxEdge. Never
    /// upscales (returns the original if already small enough).
    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1  // target is already in pixels
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
