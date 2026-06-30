import SwiftUI
import SwiftData

enum BookFilter: String, CaseIterable {
    case all        = "Все"
    case inProgress = "Читаю"
    case notStarted = "Не начато"
    case completed  = "Завершено"
    case favorites  = "Избранное"
}

struct LibraryView: View {
    var showUI: Bool = false
    var onToggleUI: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    @State private var navPath = NavigationPath()
    @State private var coverPickBook: Book? = nil
    @State private var infoBook: Book? = nil
    @State private var bookToDelete: Book? = nil
    @State private var showDeleteConfirm = false
    @State private var searchText = ""
    @State private var activeFilter: BookFilter = .all
    @State private var showFilterSheet = false

    private var filteredBooks: [Book] {
        var result = books
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch activeFilter {
        case .all:        break
        case .inProgress: result = result.filter { $0.readingProgress > 0 && $0.readingProgress < 1 }
        case .notStarted: result = result.filter { $0.readingProgress == 0 }
        case .completed:  result = result.filter { $0.readingProgress >= 1 }
        case .favorites:  result = result.filter { $0.isFavorite == true }
        }
        return result
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                DS.Color.background
                    .ignoresSafeArea()
                    .onTapGesture { onToggleUI?() }

                if books.isEmpty {
                    emptyState
                } else {
                    bookGrid
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
                BookInfoView(book: book) {
                    navPath.append(book)
                }
            }
            .alert("Удалить книгу?", isPresented: $showDeleteConfirm, presenting: bookToDelete) { book in
                Button("Удалить", role: .destructive) { deleteBook(book) }
                Button("Отмена", role: .cancel) {}
            } message: { book in
                Text("\"\(book.title)\" будет удалена из библиотеки.")
            }
            .confirmationDialog("Фильтр", isPresented: $showFilterSheet, titleVisibility: .visible) {
                ForEach(BookFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) { activeFilter = filter }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    // MARK: - Book grid

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredBooks) { book in
                    NavigationLink(value: book) {
                        BookCard(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { navPath.append(book) } label: {
                            Label("Открыть", systemImage: "book")
                        }
                        Button { infoBook = book } label: {
                            Label("Информация", systemImage: "info.circle")
                        }
                        Button { coverPickBook = book } label: {
                            Label("Сменить обложку", systemImage: "photo")
                        }
                        Button {
                            book.isFavorite = !(book.isFavorite == true)
                            try? modelContext.save()
                        } label: {
                            Label(
                                book.isFavorite == true ? "Убрать из избранного" : "В избранное",
                                systemImage: book.isFavorite == true ? "bookmark.slash" : "bookmark"
                            )
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
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleUI?() }
            )
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showUI {
                searchBarView
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.08), value: showUI)
            }
        }
    }

    // MARK: - Search bar

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.Color.textSecondary)
                .font(.system(size: 15))

            TextField("Поиск по названию или автору", text: $searchText)
                .foregroundStyle(DS.Color.textPrimary)
                .tint(DS.Color.accent)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Button { showFilterSheet = true } label: {
                Image(systemName: activeFilter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(activeFilter == .all ? DS.Color.textSecondary : DS.Color.accent)
                    .font(.system(size: 18))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Color.background)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(DS.Color.separator)
            Text("Библиотека пуста")
                .font(.system(size: 17))
                .foregroundStyle(DS.Color.textSecondary)
            Text("Поделитесь файлом EPUB или FB2 с FlowReader")
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { onToggleUI?() }
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
}

// MARK: - BookInfoView

struct BookInfoView: View {
    let book: Book
    var onStartReading: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        CoverImage(title: book.title, path: book.coverImagePath)
                            .frame(width: 160)
                            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)

                        VStack(spacing: 4) {
                            Text(book.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(DS.Color.textPrimary)
                                .multilineTextAlignment(.center)
                            Text(book.author.isEmpty ? "Неизвестный автор" : book.author)
                                .font(.system(size: 15))
                                .foregroundStyle(DS.Color.textSecondary)
                        }

                        VStack(spacing: 0) {
                            infoRow("Формат", book.format.rawValue.uppercased())
                            Divider().overlay(DS.Color.separator)
                            infoRow("Добавлена", Self.dateFormatter.string(from: book.addedAt))
                            if let pageCount = book.pageCount {
                                Divider().overlay(DS.Color.separator)
                                infoRow("Страниц", "\(pageCount)")
                            }
                            Divider().overlay(DS.Color.separator)
                            infoRow("Прочитано", "\(Int(book.readingProgress * 100))%")
                        }
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            dismiss()
                            onStartReading?()
                        } label: {
                            Text("Продолжить чтение")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(DS.Color.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(DS.Color.accent, lineWidth: 1.5)
                                }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("О книге")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(DS.Color.accent)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(DS.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(DS.Color.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - BookCard

struct BookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(title: book.title, path: book.coverImagePath)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                .overlay(alignment: .topTrailing) {
                    if book.isFavorite == true {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Color.accent)
                            .padding(6)
                    }
                }

            Text(book.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(DS.Color.textPrimary)

            Text(book.author.isEmpty ? "Неизвестный автор" : book.author)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(DS.Color.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Color.surfaceElevated)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Color.accent)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, book.readingProgress))))
                }
            }
            .frame(height: 3)

            HStack(spacing: 0) {
                Text("\(Int(book.readingProgress * 100))%")
                if let pages = book.pageCount {
                    Text(" · \(pages) стр")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(DS.Color.textSecondary)
        }
    }
}

// MARK: - CoverImage

struct CoverImage: View {
    let title: String
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var placeholderCover: some View {
        let colors: [Color] = [
            Color(hex: "2D4A7A"),
            Color(hex: "5D3A7D"),
            Color(hex: "7D3A4A"),
            Color(hex: "2A6B50"),
            Color(hex: "7D5A2A"),
            Color(hex: "2A5A7D"),
        ]
        let index = abs(title.hashValue) % colors.count
        LinearGradient(
            colors: [colors[index], DS.Color.surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Text(title.prefix(1).uppercased())
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func loadImage(from relativePath: String) -> Image? {
        let url = FileStorageService.shared.absoluteCoverURL(relativePath: relativePath)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: uiImage)
    }
}
