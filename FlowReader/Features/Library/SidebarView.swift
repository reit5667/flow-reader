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
            .background(DS.Color.surface.ignoresSafeArea())
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(DS.Color.separator)
                    .frame(width: 1)
                    .ignoresSafeArea()
            }

            // Tap-to-dismiss area
            Color.black.opacity(0.4)
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
            Rectangle()
                .fill(DS.Color.separator)
                .frame(height: 1)
                .padding(.horizontal, 16)
        }

        // Navigation items
        SidebarItem(icon: "books.vertical", title: "Моя полка",
                    isActive: activeSection == .library) {
            activeSection = .library
            isOpen = false
        }
        SidebarItem(icon: "globe", title: "Интернет",
                    isActive: activeSection == .browser) {
            activeSection = .browser
            isOpen = false
        }
        SidebarItem(icon: "gearshape", title: "Настройки",
                    isActive: activeSection == .settings) {
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
            VStack(alignment: .leading, spacing: 3) {
                Text("Последняя книга")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Color.textTertiary)
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                Text(book.author.isEmpty ? "Неизвестный автор" : book.author)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
                DS.Color.surfaceElevated
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundStyle(DS.Color.textTertiary)
                    }
            }
        }
        .frame(width: 40, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - SidebarItem

private struct SidebarItem: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(isActive ? DS.Color.accent : DS.Color.textSecondary)
                Text(title)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? DS.Color.accent : DS.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isActive ? DS.Color.accentSubtle : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
