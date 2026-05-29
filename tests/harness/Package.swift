// swift-tools-version: 6.0
import PackageDescription

// HighNotesHarness — local macOS 26 eval harness for the HighNotes (weedlabel)
// extraction/summary chain. Single executable target; all production code is
// symlinked into Sources/HighNotesHarness/Shared/ so we test PRODUCTION code,
// not a copy. No external dependencies — Vision + FoundationModels ship with
// the OS, and the Claude client is hand-rolled URLSession.
let package = Package(
    name: "highnotesharness",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "HighNotesHarness",
            path: "Sources/HighNotesHarness"
        )
    ]
)
