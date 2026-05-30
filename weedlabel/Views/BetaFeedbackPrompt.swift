#if BETA
import SwiftUI
import MessageUI

// BetaFeedbackPrompt — BETA BUILDS ONLY (compiled out of the App Store build).
//
// Shown as a sheet after a scan result renders, when sharing is enabled (opt-out,
// on by default). Collects a 👍/👎 + optional note, then hands a pre-filled mail
// composer (or share-sheet fallback) to the tester. Nothing sends without a tap.

struct BetaFeedbackPrompt: View {
    let ocrText: String
    let label: CannabisLabel
    let summary: SummaryOutcome?
    let corrections: [String]
    let image: UIImage?
    var onDismiss: () -> Void = {}

    @State private var rating: Int = 0
    @State private var note: String = ""
    @State private var showingMail = false
    @State private var showingShare = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 38, height: 5)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("How did we do?")
                    .font(.title3.weight(.bold))
                Text("Beta only — share this scan so we can sharpen the AI. You'll see exactly what's sent before it goes.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            HStack(spacing: 16) {
                thumb(value: 1, symbol: "hand.thumbsup.fill", tint: .green)
                thumb(value: -1, symbol: "hand.thumbsdown.fill", tint: .orange)
            }

            TextField("What was right or wrong? (optional)", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .focused($noteFocused)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            Button(action: share) {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("Share scan")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }

            Button("Not now") { onDismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showingMail) {
            MailComposeView(content: content) { _ in
                showingMail = false
                onDismiss()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: content.shareItems()) {
                showingShare = false
                onDismiss()
            }
            .ignoresSafeArea()
        }
    }

    private var content: FeedbackMailContent {
        ScanFeedback(ocrText: ocrText,
                     label: label,
                     summary: summary,
                     corrections: corrections,
                     rating: rating,
                     note: note).mailContent(image: image)
    }

    private func share() {
        noteFocused = false
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
        } else {
            showingShare = true
        }
    }

    private func thumb(value: Int, symbol: String, tint: Color) -> some View {
        Button {
            rating = (rating == value) ? 0 : value
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(rating == value ? .white : tint)
                .frame(width: 64, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(rating == value ? tint : tint.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }
}

/// UIKit bridge for the pre-filled mail composer.
struct MailComposeView: UIViewControllerRepresentable {
    let content: FeedbackMailContent
    let onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([content.recipient])
        vc.setSubject(content.subject)
        vc.setMessageBody(content.body, isHTML: false)
        vc.addAttachmentData(content.jsonData, mimeType: "application/json", fileName: content.jsonFilename)
        if let jpeg = content.jpegData {
            vc.addAttachmentData(jpeg, mimeType: "image/jpeg", fileName: content.jpegFilename)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish(result)
        }
    }
}

/// UIKit bridge for the share-sheet fallback (used when Mail isn't configured).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
