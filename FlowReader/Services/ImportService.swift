import Foundation
import SwiftData

enum ImportError: LocalizedError {
    case unsupportedFormat
    case fileTooLarge
    case unreadableFile
    case fileCorrupted(String)
    case noBookInArchive

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Формат не поддерживается. Используйте EPUB, FB2 или ZIP-архив с FB2."
        case .fileTooLarge: return "Файл слишком большой. Максимальный размер — 100 МБ."
        case .unreadableFile: return "Не удалось прочитать файл."
        case .fileCorrupted(let detail): return "Файл повреждён: \(detail)"
        case .noBookInArchive: return "В архиве не найдено файлов EPUB или FB2."
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

        if url.pathExtension.lowercased() == "zip" {
            return try importFromZip(url: url, context: context)
        }

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

    // MARK: - ZIP import

    private func importFromZip(url: URL, context: ModelContext) throws -> Book {
        let data = try Data(contentsOf: url)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try extractZIP(data: data, to: tempDir)

        // Find first .fb2 or .epub inside the archive
        let enumerator = FileManager.default.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var bookURL: URL?
        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "fb2" || ext == "epub" {
                bookURL = fileURL
                break
            }
        }

        guard let foundURL = bookURL else {
            throw ImportError.noBookInArchive
        }

        guard let format = bookFormat(for: foundURL) else {
            throw ImportError.unsupportedFormat
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: foundURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        guard fileSize <= maxFileSizeBytes else {
            throw ImportError.fileTooLarge
        }

        let relativePath = try FileStorageService.shared.saveBook(from: foundURL)
        let savedURL = FileStorageService.shared.absoluteBookURL(relativePath: relativePath)
        let titleFromFilename = foundURL.deletingPathExtension().lastPathComponent
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

    private func extractZIP(data: Data, to destDir: URL) throws {
        var offset = 0
        let bytes = [UInt8](data)
        let count = bytes.count

        while offset + 30 < count {
            guard bytes[offset] == 0x50, bytes[offset+1] == 0x4B,
                  bytes[offset+2] == 0x03, bytes[offset+3] == 0x04 else { break }

            let compression = UInt16(bytes[offset+8]) | (UInt16(bytes[offset+9]) << 8)
            let compressedSize = Int(
                UInt32(bytes[offset+18]) | (UInt32(bytes[offset+19]) << 8)
                | (UInt32(bytes[offset+20]) << 16) | (UInt32(bytes[offset+21]) << 24)
            )
            let uncompressedSize = Int(
                UInt32(bytes[offset+22]) | (UInt32(bytes[offset+23]) << 8)
                | (UInt32(bytes[offset+24]) << 16) | (UInt32(bytes[offset+25]) << 24)
            )
            let filenameLen = Int(UInt16(bytes[offset+26]) | (UInt16(bytes[offset+27]) << 8))
            let extraLen   = Int(UInt16(bytes[offset+28]) | (UInt16(bytes[offset+29]) << 8))

            let filenameStart = offset + 30
            let filenameEnd   = filenameStart + filenameLen
            guard filenameEnd <= count else { break }

            let filenameBytes = Array(bytes[filenameStart..<filenameEnd])
            guard let filename = String(bytes: filenameBytes, encoding: .utf8) ?? String(bytes: filenameBytes, encoding: .windowsCP1251) else {
                offset = filenameEnd + extraLen + compressedSize
                continue
            }

            let dataStart = filenameEnd + extraLen
            let dataEnd   = dataStart + compressedSize
            guard dataEnd <= count else { break }

            if !filename.hasSuffix("/") {
                let fileURL = destDir.appendingPathComponent(filename)
                try? FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let compressed = Data(bytes[dataStart..<dataEnd])
                let fileData: Data
                if compression == 8 {
                    fileData = try (compressed as NSData).decompressed(using: .zlib) as Data
                    _ = uncompressedSize
                } else {
                    fileData = compressed
                }
                try fileData.write(to: fileURL)
            }

            offset = dataEnd
        }
    }
}
