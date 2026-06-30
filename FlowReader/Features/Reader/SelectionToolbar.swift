import SwiftUI
import UIKit

struct SelectionToolbar: View {
    let selectedText: String
    let bookTitle: String
    let author: String
    let onBookmark: () -> Void
    let onDismiss: () -> Void

    private var shareText: String {
        "\(selectedText)\n— \(author), \(bookTitle)"
    }

    private var shortTitle: String {
        let parts = bookTitle.components(separatedBy: CharacterSet(charactersIn: "!,.:;"))
        let first = parts.first?.trimmingCharacters(in: .whitespaces) ?? bookTitle
        let words = first.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return words.count <= 5 ? first : words.prefix(5).joined(separator: " ")
    }

    private var quoteFormatted: String {
        "\(selectedText)\n— \(author), \(shortTitle) #read"
    }

    private func sendToFlowtaker() {
        let botUsername = "flowtakerbot"
        // Always copy to clipboard — tg:// doesn't reliably pre-fill bot messages
        UIPasteboard.general.string = quoteFormatted

        if let tgURL = URL(string: "tg://resolve?domain=\(botUsername)"),
           UIApplication.shared.canOpenURL(tgURL) {
            UIApplication.shared.open(tgURL)
        } else if let tgWeb = URL(string: "https://t.me/\(botUsername)") {
            UIApplication.shared.open(tgWeb)
        }
        onDismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Spacer()

                ShareLink(item: shareText) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                Divider().frame(height: 28)

                Button(action: sendToFlowtaker) {
                    Label("Flowtaker", systemImage: "paperplane")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                Divider().frame(height: 28)

                Button(action: {
                    onBookmark()
                    onDismiss()
                }) {
                    Label("Закладка", systemImage: "bookmark")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                Spacer()
            }
            .background(.regularMaterial)
        }
    }
}
