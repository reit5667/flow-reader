import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var appState = appState

        Text("FlowReader")
            .font(.largeTitle)
            .onChange(of: appState.pendingImportURL) { _, url in
                guard let url else { return }
                handleImport(url: url)
                appState.pendingImportURL = nil
            }
            .alert("Ошибка импорта", isPresented: $appState.showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appState.importError ?? "")
            }
    }

    private func handleImport(url: URL) {
        do {
            try ImportService.shared.importBook(from: url, context: modelContext)
        } catch {
            appState.importError = error.localizedDescription
            appState.showImportError = true
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
