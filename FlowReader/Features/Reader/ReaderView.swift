import SwiftUI
import SwiftData
import WebKit
import UIKit

struct ReaderView: View {
    let book: Book

    @Query private var settingsQuery: [ReaderSettings]
    @Environment(\.modelContext) private var modelContext

    @State private var showControls = false
    @State private var showSettings = false
    @State private var showTOC = false
    @State private var showBookmarks = false
    @State private var showBookmarkAdded = false
    @State private var selectedText: String?
    @State private var brightnessValue: CGFloat?
    @State private var brightnessHideTask: Task<Void, Never>?
    @State private var progress: Float = 0
    @State private var tocItems: [TOCItem] = []
    @State private var webViewRef: WKWebView?

    private var settings: ReaderSettings {
        settingsQuery.first ?? ReaderSettings()
    }

    var body: some View {
        ZStack {
            ReaderWebView(
                book: book,
                settings: settings,
                onProgressChange: { p in progress = p },
                onWebViewReady: { wv in webViewRef = wv },
                onTOCLoaded: { items in tocItems = items },
                onSelectionChange: { text in
                    withAnimation(.easeInOut(duration: 0.15)) { selectedText = text }
                },
                onTap: {
                    if selectedText != nil {
                        clearSelection()
                    } else {
                        withAnimation(.easeInOut(duration: 0.1)) { showControls.toggle() }
                    }
                },
                onBrightnessChange: { b in
                    brightnessValue = b
                    brightnessHideTask?.cancel()
                    brightnessHideTask = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.2)) { brightnessValue = nil }
                        }
                    }
                }
            )
            .ignoresSafeArea()

            if let b = brightnessValue {
                BrightnessGestureView(brightness: b)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if let text = selectedText, !text.isEmpty {
                VStack {
                    Spacer()
                    SelectionToolbar(
                        selectedText: text,
                        bookTitle: book.title,
                        author: book.author,
                        onBookmark: { addBookmarkFromSelection() },
                        onDismiss: { clearSelection() }
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showBookmarkAdded {
                VStack {
                    Text("Закладка добавлена")
                        .font(.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
            }

            if showControls && !showSettings {
                ReaderControlsView(
                    book: book,
                    progress: $progress,
                    onSeek: { p in seek(to: p) },
                    onTocTap: {
                        showControls = false
                        showTOC = true
                    },
                    onBookmarkTap: {
                        showControls = false
                        addBookmark()
                    },
                    onBookmarkLongPress: {
                        showControls = false
                        showBookmarks = true
                    },
                    onSettingsTap: { showSettings = true }
                )
                .transition(.opacity)
            }

            if showSettings, let s = settingsQuery.first {
                // Full-screen touch absorber prevents taps from reaching WKWebView
                ZStack(alignment: .bottom) {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            showSettings = false
                            showControls = false
                        }
                    ReaderSettingsPanel(settings: s) {
                        showSettings = false
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.opacity)
            }
        }
        .onAppear { progress = book.readingProgress }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(book.title)
        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showTOC) {
            TOCView(items: tocItems, currentProgress: progress) { item in
                seekToChapter(index: item.index)
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(book: book) { bookmark in
                seekToBookmark(offset: bookmark.offset)
            }
        }
    }

    // MARK: - Actions

    private func seek(to progress: Float) {
        let js = """
        (function() {
            var total = document.body.scrollHeight - window.innerHeight;
            window.scrollTo(0, total * \(progress));
        })();
        """
        webViewRef?.evaluateJavaScript(js)
    }

    private func addBookmark() {
        let js = """
        (function() {
            var scrollY = window.scrollY;
            var totalHeight = Math.max(1, document.body.scrollHeight - window.innerHeight);
            var elem = document.elementFromPoint(window.innerWidth / 2, window.innerHeight * 0.25);
            var text = '';
            if (elem) {
                text = (elem.innerText || elem.textContent || '').replace(/\\s+/g, ' ').trim();
                if (!text) {
                    var p = elem.closest ? elem.closest('p,h1,h2,h3,section') : null;
                    if (p) text = (p.innerText || p.textContent || '').replace(/\\s+/g, ' ').trim();
                }
            }
            return JSON.stringify({scrollY: scrollY, totalHeight: totalHeight, text: text.substring(0, 100)});
        })();
        """
        let ctx = modelContext
        let bk = book
        webViewRef?.evaluateJavaScript(js) { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let scrollY = obj["scrollY"] as? Double,
                  let totalHeight = obj["totalHeight"] as? Double else { return }
            let text = (obj["text"] as? String) ?? ""
            let offset = Int((scrollY / totalHeight) * 100_000)
            let bookmark = Bookmark(offset: offset, previewText: text.isEmpty ? "Закладка" : text)
            bookmark.book = bk
            ctx.insert(bookmark)
            try? ctx.save()
            withAnimation(.easeInOut(duration: 0.2)) { self.showBookmarkAdded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.3)) { self.showBookmarkAdded = false }
            }
        }
    }

    private func seekToBookmark(offset: Int) {
        seek(to: Float(offset) / 100_000.0)
    }

    private func clearSelection() {
        webViewRef?.evaluateJavaScript("window.getSelection().removeAllRanges();")
        withAnimation(.easeOut(duration: 0.15)) { selectedText = nil }
    }

    private func addBookmarkFromSelection() {
        let offset = Int(progress * 100_000)
        let text = selectedText ?? ""
        let ctx = modelContext
        let bk = book
        let bookmark = Bookmark(offset: offset, previewText: String(text.prefix(100)))
        bookmark.book = bk
        ctx.insert(bookmark)
        try? ctx.save()
        withAnimation(.easeInOut(duration: 0.2)) { showBookmarkAdded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) { self.showBookmarkAdded = false }
        }
    }

    private func seekToChapter(index: Int) {
        let js = """
        (function() {
            var el = document.getElementById('fr-chapter-\(index)');
            if (el) {
                el.scrollIntoView({block: 'start'});
                window.scrollBy(0, -8);
            }
        })();
        """
        webViewRef?.evaluateJavaScript(js)
    }
}

// MARK: - ReaderWebView

struct ReaderWebView: UIViewRepresentable {
    let book: Book
    let settings: ReaderSettings
    var onProgressChange: ((Float) -> Void)? = nil
    var onWebViewReady: ((WKWebView) -> Void)? = nil
    var onTOCLoaded: (([TOCItem]) -> Void)? = nil
    var onSelectionChange: ((String?) -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onBrightnessChange: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            book: book,
            onProgressChange: onProgressChange,
            onSelectionChange: onSelectionChange,
            onTap: onTap,
            onBrightnessChange: onBrightnessChange
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scrollHandler")
        config.userContentController.add(context.coordinator, name: "selectionHandler")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isPagingEnabled = false
        webView.scrollView.bounces = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.backgroundColor = UIColor(hex: settings.theme.backgroundColor)
        webView.isOpaque = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Tap recognizer — works alongside WKWebView's own recognizers
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = context.coordinator
        webView.addGestureRecognizer(tapGesture)

        // Brightness pan recognizer — left 15%, vertical
        let brightnessPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleBrightnessPan(_:))
        )
        brightnessPan.cancelsTouchesInView = false
        brightnessPan.delegate = context.coordinator
        webView.addGestureRecognizer(brightnessPan)
        context.coordinator.brightnessPanGesture = brightnessPan

        loadContent(into: webView, coordinator: context.coordinator)
        onWebViewReady?(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let css = generateCSS(settings: settings)
        let js = """
        (function() {
            var el = document.getElementById('__fr_style');
            if (el) el.textContent = `\(css)`;
        })();
        """
        webView.evaluateJavaScript(js)
        webView.backgroundColor = UIColor(hex: settings.theme.backgroundColor)
    }

    // MARK: - Content loading

    private func loadContent(into webView: WKWebView, coordinator: Coordinator) {
        guard let fileURL = resolveBookURL() else { return }
        switch book.format {
        case .epub: loadEPUB(fileURL: fileURL, into: webView, coordinator: coordinator)
        case .fb2: loadFB2(fileURL: fileURL, into: webView)
        }
    }

    private func resolveBookURL() -> URL? {
        let url = FileStorageService.shared.absoluteBookURL(relativePath: book.filePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadEPUB(fileURL: URL, into webView: WKWebView, coordinator: Coordinator) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let metadata = try EPUBParser().parse(fileURL: fileURL)
                var combinedHTML = ""
                for (index, item) in metadata.spineItems.enumerated() {
                    let anchor = "<div id=\"fr-chapter-\(index)\" style=\"height:0;overflow:hidden\"></div>"
                    combinedHTML += anchor + extractBody(from: item.html)
                }
                let fullHTML = wrapHTML(body: combinedHTML, settings: settings, savedProgress: book.readingProgress)
                let baseURL = metadata.spineItems.first?.baseURL ?? fileURL.deletingLastPathComponent()
                DispatchQueue.main.async {
                    webView.loadHTMLString(fullHTML, baseURL: baseURL)
                    onTOCLoaded?(metadata.tocItems)
                }
            } catch {
                DispatchQueue.main.async {
                    webView.loadHTMLString("<body style='color:red;padding:20px'>Ошибка загрузки EPUB: \(error)</body>", baseURL: nil)
                }
            }
        }
    }

    private func loadFB2(fileURL: URL, into webView: WKWebView) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try FB2Parser().parse(fileURL: fileURL)
                let fullHTML = wrapHTML(body: result.html, settings: settings, savedProgress: book.readingProgress, isFullDocument: true)
                DispatchQueue.main.async {
                    webView.loadHTMLString(fullHTML, baseURL: nil)
                    onTOCLoaded?(result.tocItems)
                }
            } catch {
                DispatchQueue.main.async {
                    webView.loadHTMLString("<body style='color:red;padding:20px'>Ошибка загрузки FB2: \(error)</body>", baseURL: nil)
                }
            }
        }
    }

    // MARK: - HTML helpers

    private func extractBody(from html: String) -> String {
        let lower = html.lowercased()
        if let bodyStart = lower.range(of: "<body"),
           let bodyOpen = lower.range(of: ">", range: bodyStart.upperBound..<lower.endIndex),
           let bodyEnd = lower.range(of: "</body>") {
            return String(html[bodyOpen.upperBound..<bodyEnd.lowerBound])
        }
        return html
    }

    private func wrapHTML(body: String, settings: ReaderSettings, savedProgress: Float, isFullDocument: Bool = false) -> String {
        let css = generateCSS(settings: settings)
        let progressJS = savedProgress > 0 ? """
        window.addEventListener('load', function() {
            setTimeout(function() {
                var total = document.body.scrollHeight - window.innerHeight;
                window.scrollTo(0, total * \(savedProgress));
            }, 100);
        });
        """ : ""

        let scrollJS = """
        window.addEventListener('scroll', function() {
            var total = document.body.scrollHeight - window.innerHeight;
            if (total > 0) {
                var progress = window.scrollY / total;
                window.webkit.messageHandlers.scrollHandler.postMessage(progress);
            }
        }, { passive: true });
        var __frSelTimer = null;
        document.addEventListener('selectionchange', function() {
            clearTimeout(__frSelTimer);
            __frSelTimer = setTimeout(function() {
                var text = window.getSelection().toString().trim();
                window.webkit.messageHandlers.selectionHandler.postMessage(text);
            }, 150);
        });
        """

        if isFullDocument, body.lowercased().contains("<html") {
            var result = body
            let styleTag = "<style id='__fr_style'>\(css)</style>"
            let scriptTag = "<script>\(progressJS)\(scrollJS)</script>"
            if let headEnd = result.range(of: "</head>", options: .caseInsensitive) {
                result.insert(contentsOf: styleTag + scriptTag, at: headEnd.lowerBound)
            }
            return result
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style id="__fr_style">\(css)</style>
        <script>\(progressJS)\(scrollJS)</script>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private func generateCSS(settings: ReaderSettings) -> String {
        """
        * { box-sizing: border-box; }
        html, body {
            margin: 0;
            padding: 0;
            background-color: \(settings.theme.backgroundColor);
            color: \(settings.theme.textColor);
            font-family: '\(settings.fontName)', Georgia, serif;
            font-size: \(Int(settings.fontSize))px;
            line-height: \(settings.lineSpacing.cssValue);
        }
        body {
            padding: \(settings.margins.cssValue);
            padding-bottom: 80px;
            word-break: break-word;
            overflow-wrap: break-word;
        }
        p { margin: 0.4em 0; text-indent: 1.5em; }
        h1, h2, h3, h4 { font-weight: bold; margin: 1em 0 0.4em; text-indent: 0; }
        img { max-width: 100%; height: auto; }
        a { color: inherit; }
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        let book: Book
        weak var webView: WKWebView?
        var onProgressChange: ((Float) -> Void)?
        var onSelectionChange: ((String?) -> Void)?
        var onTap: (() -> Void)?
        var onBrightnessChange: ((CGFloat) -> Void)?
        weak var brightnessPanGesture: UIPanGestureRecognizer?
        private var brightnessDragStart: CGFloat = 0
        private var saveTimer: Timer?

        init(book: Book,
             onProgressChange: ((Float) -> Void)?,
             onSelectionChange: ((String?) -> Void)?,
             onTap: (() -> Void)?,
             onBrightnessChange: ((CGFloat) -> Void)?) {
            self.book = book
            self.onProgressChange = onProgressChange
            self.onSelectionChange = onSelectionChange
            self.onTap = onTap
            self.onBrightnessChange = onBrightnessChange
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "selectionHandler" {
                let text = message.body as? String ?? ""
                onSelectionChange?(text.isEmpty ? nil : text)
                return
            }
            guard message.name == "scrollHandler",
                  let progress = message.body as? Double else { return }
            let p = Float(progress)
            onProgressChange?(p)
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.book.readingProgress = p
            }
        }

        // MARK: UIKit gesture handlers

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onTap?()
        }

        @objc func handleBrightnessPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view, let scrollView = (view as? WKWebView)?.scrollView else { return }
            switch gesture.state {
            case .began:
                brightnessDragStart = UIScreen.main.brightness
                scrollView.isScrollEnabled = false
            case .changed:
                let translation = gesture.translation(in: view)
                let delta = -translation.y / (view.bounds.height * 0.7)
                let b = max(0.05, min(1.0, brightnessDragStart + delta))
                UIScreen.main.brightness = b
                onBrightnessChange?(b)
            case .ended, .cancelled, .failed:
                scrollView.isScrollEnabled = true
            default:
                break
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === brightnessPanGesture || other === brightnessPanGesture {
                return false
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === brightnessPanGesture,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let location = pan.location(in: view)
            let velocity = pan.velocity(in: view)
            return location.x < view.bounds.width * 0.15
                && abs(velocity.y) > abs(velocity.x) * 1.2
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    }
}

// MARK: - UIColor hex init

private extension UIColor {
    convenience init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
