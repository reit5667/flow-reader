import SwiftUI
import UIKit

struct SelectionToolbar: View {
    let selectedText: String
    let bookTitle: String
    let author: String
    let onBookmark: () -> Void
    let onDismiss: () -> Void

    private var shareText: String {
        "\"\(selectedText)\"\n— \(author), \(bookTitle)"
    }

    private var obsidianContent: String {
        "> \"\(selectedText)\"\n> — \(author), *\(bookTitle)*\n\n#reader"
    }

    private func sendToObsidian() {
        guard let encoded = obsidianContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "obsidian://new?vault=Obsidian%20Vault&content=\(encoded)") else { return }
        UIApplication.shared.open(url)
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

                Button(action: sendToObsidian) {
                    Label("Obsidian", systemImage: "square.and.pencil")
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
