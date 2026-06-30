import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showUI = true
    @State private var activeSection: AppSection = .library
    @AppStorage("browserStartURL") private var browserStartURL = "https://flibusta.is"

    var body: some View {
        @Bindable var appState = appState

        mainContent
            .preferredColorScheme(.dark)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showUI && !appState.isReading {
                    AppTabBar(activeSection: $activeSection)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.08), value: showUI && !appState.isReading)
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
            LibraryView(
                showUI: showUI,
                onToggleUI: {
                    withAnimation(.easeInOut(duration: 0.08)) { showUI.toggle() }
                }
            )
        case .browser:
            BrowserView(onOpenSidebar: {}, startURL: browserStartURL)
                .onAppear { showUI = true }
        case .settings:
            SettingsView(onOpenSidebar: {})
                .onAppear { showUI = true }
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

// MARK: - AppTabBar

struct AppTabBar: View {
    @Binding var activeSection: AppSection

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Color.separator)
                .frame(height: 0.5)
            HStack(spacing: 0) {
                AppTabBarItem(
                    icon: "books.vertical",
                    label: "Библиотека",
                    isActive: activeSection == .library
                ) { activeSection = .library }
                AppTabBarItem(
                    icon: "globe",
                    label: "Браузер",
                    isActive: activeSection == .browser
                ) { activeSection = .browser }
                AppTabBarItem(
                    icon: "gearshape",
                    label: "Настройки",
                    isActive: activeSection == .settings
                ) { activeSection = .settings }
            }
            .frame(height: 49)
        }
        .background(.ultraThinMaterial)
    }
}

private struct AppTabBarItem: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isActive ? DS.Color.accent : DS.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
