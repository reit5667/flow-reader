import SwiftUI
import SwiftData

struct LibraryView: View {
    var onOpenSidebar: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    @State private var coverPickBook: Book? = nil

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(books) { book in
                                NavigationLink(value: book) {
                                    BookCard(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        coverPickBook = book
                                    } label: {
                                        Label("Сменить обложку", systemImage: "photo")
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Библиотека")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onOpenSidebar?()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
            }
            .sheet(item: $coverPickBook) { book in
                BrowserView(
                    onOpenSidebar: {},
                    startURL: googleImagesURL(title: book.title, author: book.author),
                    coverPickMode: true,
                    onCoverPicked: { imageURL in
                        saveCover(for: book, from: imageURL)
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Добавьте первую книгу")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Откройте .epub или .fb2 файл\nчерез приложение Файлы")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func googleImagesURL(title: String, author: String) -> String {
        let query = "\(title) \(author) книга обложка"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://www.google.com/search?tbm=isch&q=\(encoded)"
    }

    private func saveCover(for book: Book, from imageURL: URL) {
        Task {
            do {
                let data: Data
                if imageURL.scheme == "data" {
                    data = try decodeDataURL(imageURL)
                } else {
                    let (downloaded, _) = try await URLSession.shared.data(from: imageURL)
                    data = downloaded
                }
                let relativePath = try FileStorageService.shared.saveCover(
                    data: data,
                    bookId: book.id.uuidString
                )
                await MainActor.run {
                    book.coverImagePath = relativePath
                    try? modelContext.save()
                }
            } catch {
                // Cover save failed silently — book still usable
            }
        }
    }

    private func decodeDataURL(_ url: URL) throws -> Data {
        let raw = url.absoluteString
        guard let commaIdx = raw.firstIndex(of: ",") else {
            throw URLError(.badURL)
        }
        let payload = String(raw[raw.index(after: commaIdx)...])
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }
}

// MARK: - BookCard

private struct BookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverImage(path: book.coverImagePath)
                .overlay(alignment: .bottom) {
                    ProgressBar(value: book.readingProgress)
                }

            Text(book.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Text(book.author)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            if book.readingProgress > 0 {
                Text("\(Int(book.readingProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - CoverImage

private struct CoverImage: View {
    let path: String?

    var body: some View {
        Group {
            if let path, let image = loadImage(from: path) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderCover
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
            }
    }

    private func loadImage(from relativePath: String) -> Image? {
        let url = FileStorageService.shared.absoluteCoverURL(relativePath: relativePath)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: uiImage)
    }
}

// MARK: - ProgressBar

private struct ProgressBar: View {
    let value: Float

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * CGFloat(value), height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 3)
    }
}
