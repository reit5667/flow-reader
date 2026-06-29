import SwiftUI
import SwiftData

struct BookmarksView: View {
    let book: Book
    let onSelect: (Bookmark) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var allBookmarks: [Bookmark]

    private var bookmarks: [Bookmark] {
        allBookmarks.filter { $0.book?.id == book.id }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(bookmarks) { bookmark in
                    Button {
                        onSelect(bookmark)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.previewText.isEmpty ? "Закладка" : bookmark.previewText)
                                .font(.body)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            HStack {
                                Text("\(bookmark.offset / 1000)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete(perform: deleteBookmarks)
            }
            .listStyle(.plain)
            .overlay {
                if bookmarks.isEmpty {
                    ContentUnavailableView("Нет закладок", systemImage: "bookmark")
                }
            }
            .navigationTitle("Закладки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(bookmarks[index])
        }
        try? modelContext.save()
    }
}
