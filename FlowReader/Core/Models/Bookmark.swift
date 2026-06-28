import Foundation
import SwiftData

@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID
    var offset: Int
    var previewText: String
    var createdAt: Date
    var book: Book?

    init(offset: Int, previewText: String) {
        self.id = UUID()
        self.offset = offset
        self.previewText = previewText
        self.createdAt = Date()
    }
}
