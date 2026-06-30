import Foundation

@Observable
final class AppState {
    var pendingImportURL: URL?
    var importError: String?
    var showImportError: Bool = false
    var isReading: Bool = false
}
