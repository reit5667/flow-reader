import SwiftUI
import WebKit
import SwiftData

@Observable
final class BrowserState {
    var addressText: String = "https://flibusta.is"
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stopLoading() { webView?.stopLoading() }

    func navigate(to string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "https://" + s
        }
        guard let url = URL(string: s) else { return }
        webView?.load(URLRequest(url: url))
        addressText = s
    }
}

struct BrowserView: View {
    @Environment(\.modelContext) private var modelContext

    let onOpenSidebar: () -> Void

    @State private var browserState = BrowserState()
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                BrowserWebViewRepresentable(
                    state: browserState,
                    onFileDownloaded: handleDownload,
                    onImportError: showError
                )
                .ignoresSafeArea(edges: .bottom)

                if showToast {
                    Text(toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onOpenSidebar() } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .principal) {
                    addressBar
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { browserState.goBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!browserState.canGoBack)
                    Spacer()
                    Button { browserState.goForward() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!browserState.canGoForward)
                }
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 6) {
            TextField("Адрес", text: $browserState.addressText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .onSubmit { browserState.navigate(to: browserState.addressText) }
                .frame(maxWidth: .infinity)
            Button {
                if browserState.isLoading { browserState.stopLoading() } else { browserState.reload() }
            } label: {
                Image(systemName: browserState.isLoading ? "xmark" : "arrow.clockwise")
                    .frame(width: 20)
            }
        }
    }

    private func handleDownload(tempURL: URL) {
        do {
            try ImportService.shared.importBook(from: tempURL, context: modelContext)
            toast("Книга добавлена в библиотеку")
        } catch {
            toast("Ошибка импорта: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func showError(_ message: String) {
        toast("Ошибка: \(message)")
    }

    private func toast(_ message: String) {
        toastMessage = message
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - UIViewRepresentable

struct BrowserWebViewRepresentable: UIViewRepresentable {
    let state: BrowserState
    let onFileDownloaded: (URL) -> Void
    let onImportError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onFileDownloaded: onFileDownloaded, onImportError: onImportError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        state.webView = webView
        if let url = URL(string: "https://flibusta.is") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onFileDownloaded = onFileDownloaded
        context.coordinator.onImportError = onImportError
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        private let state: BrowserState
        var onFileDownloaded: (URL) -> Void
        var onImportError: (String) -> Void
        private var downloadDestination: URL?

        init(state: BrowserState, onFileDownloaded: @escaping (URL) -> Void, onImportError: @escaping (String) -> Void) {
            self.state = state
            self.onFileDownloaded = onFileDownloaded
            self.onImportError = onImportError
        }

        // MARK: Navigation policy — intercept by URL extension

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if let url = navigationAction.request.url, isBookURL(url) {
                decisionHandler(.download, preferences)
            } else {
                decisionHandler(.allow, preferences)
            }
        }

        // Intercept by MIME type when URL extension is absent

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let mimeType = navigationResponse.response.mimeType ?? ""
            if isBookMIMEType(mimeType) {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        // Hook WKDownload from action interception

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        // Hook WKDownload from response interception

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // MARK: WKDownloadDelegate

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            var filename = suggestedFilename
            let mimeType = response.mimeType ?? ""
            if mimeType.contains("epub") && !filename.hasSuffix(".epub") {
                filename += ".epub"
            } else if (mimeType.contains("fictionbook") || mimeType.contains("fb2")) && !filename.hasSuffix(".fb2") {
                filename += ".fb2"
            }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_" + filename)
            downloadDestination = dest
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let dest = downloadDestination else { return }
            downloadDestination = nil
            DispatchQueue.main.async { self.onFileDownloaded(dest) }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestination = nil
            DispatchQueue.main.async { self.onImportError(error.localizedDescription) }
        }

        // MARK: Navigation state

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.state.isLoading = true
                self.state.canGoBack = webView.canGoBack
                self.state.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.state.isLoading = false
                self.state.canGoBack = webView.canGoBack
                self.state.canGoForward = webView.canGoForward
                if let url = webView.url {
                    self.state.addressText = url.absoluteString
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.state.isLoading = false
                self.state.canGoBack = webView.canGoBack
                self.state.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.state.isLoading = false }
        }

        // MARK: Helpers

        private func isBookURL(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ext == "epub" || ext == "fb2"
        }

        private func isBookMIMEType(_ mimeType: String) -> Bool {
            let lower = mimeType.lowercased()
            return lower.contains("epub") || lower.contains("fictionbook")
        }
    }
}
