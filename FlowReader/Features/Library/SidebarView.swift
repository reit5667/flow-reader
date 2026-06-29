import SwiftUI
import SwiftData

enum AppSection {
    case library
    case browser
    case settings
}

struct SidebarView: View {
    @Binding var isOpen: Bool
    @Binding var activeSection: AppSection
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]

    private var lastBook: Book? { books.first(where: { $0.lastOpenedAt != nil }) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                sidebarContent
                Spacer()
            }
            .frame(width: 260)
            .background(Color(.systemBackground).ignoresSafeArea())

            // Tap-to-dismiss area
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isOpen = false }
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        // Last book
        if let book = lastBook {
            Button {
                activeSection = .library
                isOpen = false
            } label: {
                LastBookRow(book: book)
            }
            .buttonStyle(.plain)
            Divider().padding(.horizontal, 16)
        }

        // Navigation items
        SidebarItem(icon: "books.vertical", title: "Моя полка") {
            activeSection = .library
            isOpen = false
        }
        SidebarItem(icon: "globe", title: "Интернет") {
            activeSection = .browser
            isOpen = false
        }
        SidebarItem(icon: "gearshape", title: "Настройки") {
            activeSection = .settings
            isOpen = false
        }
    }
}

// MARK: - LastBookRow

private struct LastBookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            CoverThumbnail(path: book.coverImagePath)
            VStack(alignment: .leading, spacing: 2) {
                Text("Последняя книга")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct CoverThumbnail: View {
    let path: String?

    var body: some View {
        Group {
            if let path,
               let uiImage = UIImage(contentsOfFile: FileStorageService.shared.absoluteCoverURL(relativePath: path).path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 44, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - SidebarItem

private struct SidebarItem: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
