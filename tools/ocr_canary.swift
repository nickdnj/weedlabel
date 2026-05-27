// ocr_canary.swift — runs Vision text recognition against a JPEG and
// prints the recognized text + detected barcodes. Used to validate the OCR
// leg of the pipeline against canary images in assets/validation/ without
// needing an iOS device.
//
//   swift /Users/nickdemarco/Workspaces/weedlabel/tools/ocr_canary.swift \
//     /Users/nickdemarco/Workspaces/weedlabel/assets/validation/zips-blue-candy-rain.jpeg

import Foundation
import Vision
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ocr_canary.swift <image> [orientation: up|left|right|down]\n".utf8))
    exit(2)
}
let path = args[1]
let url = URL(fileURLWithPath: path)

let orientation: CGImagePropertyOrientation = {
    let arg = args.count >= 3 ? args[2].lowercased() : "up"
    switch arg {
    case "up": return .up
    case "down": return .down
    case "left": return .left
    case "right": return .right
    default: return .up
    }
}()
FileHandle.standardError.write(Data("orientation: \(orientation.rawValue)\n".utf8))

guard let image = NSImage(contentsOf: url),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cg = rep.cgImage else {
    FileHandle.standardError.write(Data("failed to load image at \(path)\n".utf8))
    exit(1)
}

let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])

// Text
let textRequest = VNRecognizeTextRequest()
textRequest.recognitionLevel = .accurate
textRequest.usesLanguageCorrection = true
textRequest.recognitionLanguages = ["en-US"]

// Barcodes
let barcodeRequest = VNDetectBarcodesRequest()

do {
    try handler.perform([textRequest, barcodeRequest])
} catch {
    FileHandle.standardError.write(Data("vision request failed: \(error)\n".utf8))
    exit(1)
}

// Sort observations top-to-bottom, then left-to-right, to approximate reading order.
let observations = (textRequest.results ?? [])
let sorted = observations.sorted { a, b in
    let aTop = 1.0 - a.boundingBox.maxY
    let bTop = 1.0 - b.boundingBox.maxY
    if abs(aTop - bTop) > 0.01 { return aTop < bTop }
    return a.boundingBox.minX < b.boundingBox.minX
}

print("=== OCR TEXT (\(sorted.count) lines) ===")
for obs in sorted {
    guard let candidate = obs.topCandidates(1).first else { continue }
    print(candidate.string)
}

// Bounding boxes — used to diagnose two-column layout problems. Vision's
// coordinate space is [0,1] origin bottom-left.
print("\n=== BBOXES (y_top, y_bot, x_left, x_right, text) ===")
for obs in sorted {
    guard let candidate = obs.topCandidates(1).first else { continue }
    let bb = obs.boundingBox
    let yTop = 1.0 - bb.maxY
    let yBot = 1.0 - bb.minY
    let xL = bb.minX
    let xR = bb.maxX
    print(String(format: "%.4f %.4f %.4f %.4f | %@", yTop, yBot, xL, xR, candidate.string))
}

let barcodes = barcodeRequest.results ?? []
print("\n=== BARCODES (\(barcodes.count)) ===")
for b in barcodes {
    print("[\(b.symbology.rawValue)] \(b.payloadStringValue ?? "<no payload>")")
}
