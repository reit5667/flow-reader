import Foundation
import SwiftData

enum BookFormat: String, Codable {
    case epub
    case fb2
}

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var filePath: String
    var coverImagePath: String?
    var format: BookFormat
    var addedAt: Date
    var lastOpenedAt: Date?
    var readingProgress: Float
    var currentOffset: Int

    @Relationship(deleteRule: .cascade) var bookmarks: [Bookmark]

    init(
        title: String,
        author: String,
        filePath: String,
        format: BookFormat,
        coverImagePath: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.filePath = filePath
        self.format = format
        self.coverImagePath = coverImagePath
        self.addedAt = Date()
        self.lastOpenedAt = nil
        self.readingProgress = 0
        self.currentOffset = 0
        self.bookmarks = []
    }
}
