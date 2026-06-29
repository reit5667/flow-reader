import SwiftUI

struct SelectionToolbar: View {
    let selectedText: String
    let bookTitle: String
    let author: String
    let onBookmark: () -> Void
    let onDismiss: () -> Void

    private var shareText: String {
        "\"\(selectedText)\"\n— \(author), \(bookTitle)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Spacer()

                ShareLink(item: shareText) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }

                Divider().frame(height: 28)

                Button(action: {
                    onBookmark()
                    onDismiss()
                }) {
                    Label("Закладка", systemImage: "bookmark")
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }

                Spacer()
            }
            .background(.regularMaterial)
        }
    }
}
