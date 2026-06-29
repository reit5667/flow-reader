import Foundation
import SwiftData

enum ImportError: LocalizedError {
    case unsupportedFormat
    case fileTooLarge
    case unreadableFile
    case fileCorrupted(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Формат не поддерживается. Используйте EPUB или FB2."
        case .fileTooLarge: return "Файл слишком большой. Максимальный размер — 100 МБ."
        case .unreadableFile: return "Не удалось прочитать файл."
        case .fileCorrupted(let detail): return "Файл повреждён: \(detail)"
        }
    }
}

final class ImportService {
    static let shared = ImportService()
    private let maxFileSizeBytes: Int = 100 * 1024 * 1024

    private init() {}

    @discardableResult
    func importBook(from url: URL, context: ModelContext) throws -> Book {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let format = bookFormat(for: url) else {
            throw ImportError.unsupportedFormat
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0
        guard fileSize <= maxFileSizeBytes else {
            throw ImportError.fileTooLarge
        }

        let relativePath = try FileStorageService.shared.saveBook(from: url)
        let savedURL = FileStorageService.shared.absoluteBookURL(relativePath: relativePath)
        let titleFromFilename = url.deletingPathExtension().lastPathComponent
        let book = Book(title: titleFromFilename, author: "Неизвестен", filePath: relativePath, format: format)

        do {
            try validateAndEnrichMetadata(book: book, fileURL: savedURL, format: format)
        } catch {
            try? FileStorageService.shared.deleteBook(relativePath: relativePath)
            throw ImportError.fileCorrupted(error.localizedDescription)
        }

        context.insert(book)
        try context.save()
        return book
    }

    private func validateAndEnrichMetadata(book: Book, fileURL: URL, format: BookFormat) throws {
        switch format {
        case .epub:
            let meta = try EPUBParser().parseMetadataOnly(fileURL: fileURL)
            if !meta.title.isEmpty && meta.title != "Unknown" { book.title = meta.title }
            if !meta.author.isEmpty && meta.author != "Unknown" { book.author = meta.author }
            if let coverData = meta.coverData {
                book.coverImagePath = try? FileStorageService.shared.saveCover(
                    data: coverData, bookId: book.id.uuidString
                )
            }
        case .fb2:
            let result = try FB2Parser().parse(fileURL: fileURL)
            let meta = result.metadata
            if !meta.title.isEmpty && meta.title != "Unknown" { book.title = meta.title }
            if !meta.author.isEmpty && meta.author != "Unknown" { book.author = meta.author }
            if let coverData = meta.coverData {
                book.coverImagePath = try? FileStorageService.shared.saveCover(
                    data: coverData, bookId: book.id.uuidString
                )
            }
        }
    }

    private func bookFormat(for url: URL) -> BookFormat? {
        switch url.pathExtension.lowercased() {
        case "epub": return .epub
        case "fb2": return .fb2
        default: return nil
        }
    }
}
