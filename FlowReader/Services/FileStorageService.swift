import Foundation

final class FileStorageService {
    static let shared = FileStorageService()

    private let booksDirectory: URL
    private let coversDirectory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksDirectory = documents.appendingPathComponent("Books", isDirectory: true)
        coversDirectory = documents.appendingPathComponent("Covers", isDirectory: true)
        createDirectoriesIfNeeded()
    }

    // MARK: - Books

    func saveBook(data: Data, filename: String) throws -> String {
        let safeFilename = sanitizeFilename(filename)
        let fileURL = booksDirectory.appendingPathComponent(safeFilename)
        try data.write(to: fileURL, options: .atomic)
        return relativePath(from: fileURL)
    }

    func saveBook(from sourceURL: URL) throws -> String {
        let filename = sanitizeFilename(sourceURL.lastPathComponent)
        let destURL = booksDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        return relativePath(from: destURL)
    }

    func deleteBook(relativePath: String) throws {
        let fileURL = absoluteURL(from: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func absoluteBookURL(relativePath: String) -> URL {
        absoluteURL(from: relativePath)
    }

    // MARK: - Covers

    func saveCover(data: Data, bookId: String) throws -> String {
        // Remove previous covers for this book so coverImagePath always changes
        if let existing = try? FileManager.default.contentsOfDirectory(atPath: coversDirectory.path) {
            for name in existing where name.hasPrefix(bookId) {
                try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent(name))
            }
        }
        let filename = "\(bookId)_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = coversDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return relativePath(from: fileURL)
    }

    func deleteCover(relativePath: String) throws {
        let fileURL = absoluteURL(from: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func absoluteCoverURL(relativePath: String) -> URL {
        absoluteURL(from: relativePath)
    }

    // MARK: - Helpers

    private func createDirectoriesIfNeeded() {
        [booksDirectory, coversDirectory].forEach { url in
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    // Stores paths relative to Documents/ for backup compatibility
    private func relativePath(from absoluteURL: URL) -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return absoluteURL.path.replacingOccurrences(of: documents.path + "/", with: "")
    }

    private func absoluteURL(from relativePath: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(relativePath)
    }

    func expectedRelativePath(for sourceURL: URL) -> String {
        let filename = sanitizeFilename(sourceURL.lastPathComponent)
        return relativePath(from: booksDirectory.appendingPathComponent(filename))
    }

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: illegal).joined(separator: "_")
    }
}
