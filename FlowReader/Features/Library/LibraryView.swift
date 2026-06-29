import SwiftUI
import SwiftData

struct LibraryView: View {
    var onOpenSidebar: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    @State private var navPath = NavigationPath()
    @State private var coverPickBook: Book? = nil
    @State private var infoBook: Book? = nil
    @State private var bookToDelete: Book? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack(path: $navPath) {
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
                                        navPath.append(book)
                                    } label: {
                                        Label("Открыть", systemImage: "book")
                                    }
                                    Button {
                                        infoBook = book
                                    } label: {
                                        Label("Информация", systemImage: "info.circle")
                                    }
                                    Button {
                                        coverPickBook = book
                                    } label: {
                                        Label("Сменить обложку", systemImage: "photo")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        bookToDelete = book
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
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
                    Button { onOpenSidebar?() } label: {
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
                    onCoverPicked: { imageURL in saveCover(for: book, from: imageURL) }
                )
            }
            .sheet(item: $infoBook) { book in
                BookInfoView(book: book)
            }
            .alert("Удалить книгу?", isPresented: $showDeleteConfirm, presenting: bookToDelete) { book in
                Button("Удалить", role: .destructive) { deleteBook(book) }
                Button("Отмена", role: .cancel) {}
            } message: { book in
                Text("\"\(book.title)\" будет удалена из библиотеки.")
            }
        }
    }

    // MARK: - Actions

    private func deleteBook(_ book: Book) {
        try? FileStorageService.shared.deleteBook(relativePath: book.filePath)
        if let coverPath = book.coverImagePath {
            try? FileStorageService.shared.deleteCover(relativePath: coverPath)
        }
        modelContext.delete(book)
        try? modelContext.save()
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
            } catch {}
        }
    }

    private func decodeDataURL(_ url: URL) throws -> Data {
        let raw = url.absoluteString
        guard let commaIdx = raw.firstIndex(of: ",") else { throw URLError(.badURL) }
        let payload = String(raw[raw.index(after: commaIdx)...])
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }

    private func googleImagesURL(title: String, author: String) -> String {
        let query = "\(title) \(author) книга обложка"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://www.google.com/search?tbm=isch&q=\(encoded)"
    }

    // MARK: - Empty state

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
}

// MARK: - BookInfoView

private struct BookInfoView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss

    private var fileSize: String {
        let url = FileStorageService.shared.absoluteBookURL(relativePath: book.filePath)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    infoRow(label: "Название", value: book.title)
                    infoRow(label: "Автор", value: book.author)
                    infoRow(label: "Формат", value: book.format.rawValue.uppercased())
                }
                Section {
                    infoRow(label: "Размер", value: fileSize)
                    infoRow(label: "Добавлена", value: Self.dateFormatter.string(from: book.addedAt))
                    if let opened = book.lastOpenedAt {
                        infoRow(label: "Открывалась", value: Self.dateFormatter.string(from: opened))
                    }
                    infoRow(label: "Прочитано", value: "\(Int(book.readingProgress * 100))%")
                }
            }
            .navigationTitle("Информация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
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
