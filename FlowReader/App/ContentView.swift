import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var sidebarOpen = false
    @State private var activeSection: AppSection = .library

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .leading) {
            // Main content
            mainContent
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            if value.startLocation.x < 30 && value.translation.width > 60 {
                                sidebarOpen = true
                            } else if value.translation.width < -60 {
                                sidebarOpen = false
                            }
                        }
                )

            // Sidebar overlay
            if sidebarOpen {
                SidebarView(isOpen: $sidebarOpen, activeSection: $activeSection)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: sidebarOpen)
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

    @ViewBuilder
    private var mainContent: some View {
        switch activeSection {
        case .library:
            LibraryView(onOpenSidebar: { sidebarOpen = true })
        case .browser:
            BrowserView(onOpenSidebar: { sidebarOpen = true })
        case .settings:
            NavigationStack {
                Color.clear
                    .navigationTitle("Настройки")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { sidebarOpen = true } label: {
                                Image(systemName: "line.3.horizontal")
                            }
                        }
                    }
            }
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
