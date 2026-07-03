import SwiftUI
import WebKit
import SwiftData

@Observable
final class BrowserState {
    var addressText: String
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    weak var webView: WKWebView?

    init(startURL: String = "https://flibusta.is") {
        self.addressText = startURL
    }

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
    @Environment(\.dismiss) private var dismiss

    let onOpenSidebar: () -> Void
    var coverPickMode: Bool = false
    var onCoverPicked: ((URL) -> Void)? = nil

    @State private var browserState: BrowserState
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var pendingCoverURL: URL? = nil
    @State private var showCoverConfirm = false
    @State private var showMirrorHint = false

    init(onOpenSidebar: @escaping () -> Void,
         startURL: String = "https://flibusta.is",
         coverPickMode: Bool = false,
         onCoverPicked: ((URL) -> Void)? = nil) {
        self.onOpenSidebar = onOpenSidebar
        self.coverPickMode = coverPickMode
        self.onCoverPicked = onCoverPicked
        self._browserState = State(wrappedValue: BrowserState(startURL: startURL))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                BrowserWebViewRepresentable(
                    state: browserState,
                    coverPickMode: coverPickMode,
                    onFileDownloaded: handleDownload,
                    onImportError: showError,
                    onCoverImageURL: handleCoverImageURL,
                    onNavigationFailed: { showMirrorHint = true }
                )
                .ignoresSafeArea(edges: .bottom)

                if showMirrorHint {
                    VStack(spacing: 8) {
                        Text("Не удалось загрузить страницу")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Попробуйте сменить зеркало в Настройках")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Закрыть") { showMirrorHint = false }
                            .font(.caption)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
                if coverPickMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Закрыть") { dismiss() }
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
        .alert("Использовать как обложку?", isPresented: $showCoverConfirm) {
            Button("Использовать") {
                if let url = pendingCoverURL {
                    onCoverPicked?(url)
                    dismiss()
                }
            }
            Button("Отмена", role: .cancel) { pendingCoverURL = nil }
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

    private func handleCoverImageURL(_ url: URL) {
        pendingCoverURL = url
        showCoverConfirm = true
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
    let coverPickMode: Bool
    let onFileDownloaded: (URL) -> Void
    let onImportError: (String) -> Void
    let onCoverImageURL: (URL) -> Void
    var onNavigationFailed: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            coverPickMode: coverPickMode,
            onFileDownloaded: onFileDownloaded,
            onImportError: onImportError,
            onCoverImageURL: onCoverImageURL,
            onNavigationFailed: onNavigationFailed
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        if coverPickMode {
            let script = WKUserScript(
                source: coverPickJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
            config.userContentController.add(
                WeakScriptMessageHandler(context.coordinator),
                name: "coverImage"
            )
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        if coverPickMode { webView.allowsLinkPreview = false }
        state.webView = webView

        if let url = URL(string: state.addressText) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onFileDownloaded = onFileDownloaded
        context.coordinator.onImportError = onImportError
        context.coordinator.onCoverImageURL = onCoverImageURL
        context.coordinator.onNavigationFailed = onNavigationFailed
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "coverImage")
    }

    // Prevents WKUserContentController retain cycle
    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        weak var coordinator: Coordinator?
        init(_ coordinator: Coordinator) { self.coordinator = coordinator }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            coordinator?.handleScriptMessage(message)
        }
    }

    // Long-press on <img> → posts {src} to Swift; blocks native iOS callout
    private var coverPickJS: String {
        """
        (function() {
            var style = document.createElement('style');
            style.textContent = 'img { -webkit-touch-callout: none !important; user-select: none !important; }';
            (document.head || document.documentElement).appendChild(style);

            document.addEventListener('contextmenu', function(e) {
                if (e.target.closest('img')) e.preventDefault();
            }, false);

            var timer;
            document.addEventListener('touchstart', function(e) {
                var img = e.target.closest('img');
                if (!img || !img.src) return;
                timer = setTimeout(function() {
                    window.webkit.messageHandlers.coverImage.postMessage(img.src);
                }, 600);
            }, {passive: true});
            document.addEventListener('touchend', function() { clearTimeout(timer); }, {passive: true});
            document.addEventListener('touchmove', function() { clearTimeout(timer); }, {passive: true});
        })();
        """
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        private let state: BrowserState
        private let coverPickMode: Bool
        var onFileDownloaded: (URL) -> Void
        var onImportError: (String) -> Void
        var onCoverImageURL: (URL) -> Void
        var onNavigationFailed: (() -> Void)?
        private var downloadDestination: URL?

        init(state: BrowserState, coverPickMode: Bool,
             onFileDownloaded: @escaping (URL) -> Void,
             onImportError: @escaping (String) -> Void,
             onCoverImageURL: @escaping (URL) -> Void,
             onNavigationFailed: (() -> Void)?) {
            self.state = state
            self.coverPickMode = coverPickMode
            self.onFileDownloaded = onFileDownloaded
            self.onImportError = onImportError
            self.onCoverImageURL = onCoverImageURL
            self.onNavigationFailed = onNavigationFailed
        }

        func handleScriptMessage(_ message: WKScriptMessage) {
            guard let src = message.body as? String, let url = URL(string: src) else { return }
            DispatchQueue.main.async { self.onCoverImageURL(url) }
        }

        // MARK: Navigation policy

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if !coverPickMode, let url = navigationAction.request.url, isBookURL(url) {
                decisionHandler(.download, preferences)
            } else {
                decisionHandler(.allow, preferences)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if !coverPickMode, isBookMIMEType(navigationResponse.response.mimeType ?? "") {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // MARK: WKDownloadDelegate

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            var filename = suggestedFilename
            let mimeType = response.mimeType ?? ""
            if mimeType.contains("epub") && !filename.hasSuffix(".epub") { filename += ".epub" }
            else if (mimeType.contains("fictionbook") || mimeType.contains("fb2")) && !filename.hasSuffix(".fb2") { filename += ".fb2" }
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
                if let url = webView.url { self.state.addressText = url.absoluteString }
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
            DispatchQueue.main.async {
                self.state.isLoading = false
                let nsError = error as NSError
                // Show mirror hint for network errors (not for user-cancelled navigations)
                if nsError.domain == NSURLErrorDomain && nsError.code != NSURLErrorCancelled {
                    self.onNavigationFailed?()
                }
            }
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
