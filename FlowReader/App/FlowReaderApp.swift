import SwiftUI
import SwiftData

@main
struct FlowReaderApp: App {
    @State private var appState = AppState()

    let container: ModelContainer = {
        let schema = Schema([Book.self, Bookmark.self, ReaderSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(appState)
                .onOpenURL { url in
                    appState.pendingImportURL = url
                }
        }
    }
}
