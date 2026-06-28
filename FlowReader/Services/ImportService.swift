import Foundation
import SwiftData

enum ImportError: LocalizedError {
    case unsupportedFormat
    case fileTooLarge
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Формат не поддерживается. Используйте EPUB или FB2."
        case .fileTooLarge: return "Файл слишком большой. Максимальный размер — 100 МБ."
        case .unreadableFile: return "Не удалось прочитать файл."
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
        let title = url.deletingPathExtension().lastPathComponent
        let book = Book(title: title, author: "Неизвестен", filePath: relativePath, format: format)

        context.insert(book)
        try context.save()

        return book
    }

    private func bookFormat(for url: URL) -> BookFormat? {
        switch url.pathExtension.lowercased() {
        case "epub": return .epub
        case "fb2": return .fb2
        default: return nil
        }
    }
}
