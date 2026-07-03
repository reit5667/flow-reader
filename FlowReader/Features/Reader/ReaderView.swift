import SwiftUI
import SwiftData
import WebKit
import UIKit

struct ReaderView: View {
    let book: Book

    @Query private var settingsQuery: [ReaderSettings]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var isLoading = true
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

    // Value-type snapshot — forces updateUIView when any setting changes.
    // Without this, SwiftUI sees the same ReaderSettings reference and may skip updateUIView,
    // leaving coordinator.isOverlayActive stale and CSS never updated.
    private var cssRevision: String {
        let s = settings
        return "\(s.theme.rawValue)-\(Int(s.fontSize))-\(s.fontName)-\(s.lineSpacing.rawValue)-\(s.margins.rawValue)-\(s.isPageMode == true)"
    }

    var body: some View {
        ZStack {
            ReaderWebView(
                book: book,
                settings: settings,
                cssRevision: cssRevision,
                onProgressChange: { p in progress = p },
                onWebViewReady: { wv in webViewRef = wv },
                onTOCLoaded: { items in tocItems = items },
                onSelectionChange: { text in
                    selectedText = text
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
                },
                onLoadingChanged: { loading in
                    withAnimation(.easeOut(duration: 0.2)) { isLoading = loading }
                },
                onFontSizeChange: { size in
                    settingsQuery.first?.fontSize = size
                },
                isOverlayActive: showControls
            )
            .ignoresSafeArea()
            .onAppear { appState.isReading = true }
            .onDisappear { appState.isReading = false }

            if isLoading {
                Color(UIColor.systemBackground).opacity(0.9)
                    .ignoresSafeArea()
                    .overlay(ProgressView())
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

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

            if showControls {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.1)) { showControls = false }
                    }
                ReaderControlsView(
                    book: book,
                    progress: progress,
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
                    onSettingsTap: {
                        showControls = false
                        showSettings = true
                    }
                )
                .transition(.opacity)
            }
        }
        .background(NavigationBackSwipeEnabler())
        .onAppear {
            progress = book.readingProgress
            if settingsQuery.isEmpty {
                let defaults = ReaderSettings()
                modelContext.insert(defaults)
                try? modelContext.save()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(book.title)
        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(settings.theme.navBarBackground, for: .navigationBar)
        .toolbarColorScheme(settings.theme.navBarColorScheme, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            if let s = settingsQuery.first {
                ReaderSettingsPanel(settings: s) { showSettings = false }
                    .presentationDetents([.height(440)])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(DS.Color.surface)
            }
        }
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
        guard let webView = webViewRef else { return }
        if settings.isPageMode == true {
            webView.evaluateJavaScript("document.body.scrollWidth - window.innerWidth") { result, _ in
                let total: Double
                if let n = result as? NSNumber { total = n.doubleValue }
                else if let d = result as? Double { total = d }
                else { return }
                guard total > 0 else { return }
                let raw = CGFloat(progress) * CGFloat(total)
                let pageW = webView.scrollView.bounds.width
                let x = pageW > 0 ? round(raw / pageW) * pageW : raw
                webView.scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: true)
            }
        } else {
            webView.evaluateJavaScript("document.body.scrollHeight - window.innerHeight") { result, _ in
                let total: Double
                if let n = result as? NSNumber { total = n.doubleValue }
                else if let d = result as? Double { total = d }
                else { return }
                guard total > 0 else { return }
                let y = CGFloat(progress) * CGFloat(total)
                webView.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: true)
            }
        }
    }

    private func addBookmark() {
        let offset = Int(progress * 100_000)
        let bookmark = Bookmark(offset: offset, previewText: "Закладка")
        bookmark.book = book
        modelContext.insert(bookmark)
        try? modelContext.save()
        withAnimation(.easeInOut(duration: 0.2)) { showBookmarkAdded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) { self.showBookmarkAdded = false }
        }
        // Fetch preview text async (non-blocking)
        webViewRef?.evaluateJavaScript("""
            (function(){var e=document.elementFromPoint(window.innerWidth/2,window.innerHeight*0.3);
            return e?(e.innerText||e.textContent||'').replace(/\\s+/g,' ').trim().substring(0,100):'';})()
        """) { result, _ in
            guard let text = result as? String, !text.isEmpty else { return }
            bookmark.previewText = text
            try? self.modelContext.save()
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
        let preview = (selectedText ?? "").prefix(100)
        let bookmark = Bookmark(offset: offset, previewText: preview.isEmpty ? "Закладка" : String(preview))
        bookmark.book = book
        modelContext.insert(bookmark)
        try? modelContext.save()
        withAnimation(.easeInOut(duration: 0.2)) { showBookmarkAdded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) { self.showBookmarkAdded = false }
        }
    }

    private func seekToChapter(index: Int) {
        let js: String
        if settings.isPageMode == true {
            js = """
            (function() {
                var el = document.getElementById('fr-chapter-\(index)');
                if (el) {
                    el.scrollIntoView({behavior: 'instant', block: 'start'});
                    var pageW = window.innerWidth;
                    window.scrollTo(Math.round(window.scrollX / pageW) * pageW, 0);
                }
            })();
            """
        } else {
            js = """
            (function() {
                var el = document.getElementById('fr-chapter-\(index)');
                if (el) {
                    el.scrollIntoView({block: 'start'});
                    window.scrollBy(0, -8);
                }
            })();
            """
        }
        webViewRef?.evaluateJavaScript(js)
    }
}

// MARK: - ReaderWebView

struct ReaderWebView: UIViewRepresentable {
    let book: Book
    let settings: ReaderSettings
    // Value-type snapshot of settings — SwiftUI diffs this string to detect
    // setting changes and call updateUIView even though settings is a reference type.
    var cssRevision: String = ""
    var onProgressChange: ((Float) -> Void)? = nil
    var onWebViewReady: ((WKWebView) -> Void)? = nil
    var onTOCLoaded: (([TOCItem]) -> Void)? = nil
    var onSelectionChange: ((String?) -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onBrightnessChange: ((CGFloat) -> Void)? = nil
    var onLoadingChanged: ((Bool) -> Void)? = nil
    var onFontSizeChange: ((Float) -> Void)? = nil
    // Suppress WKWebView UIKit tap while controls overlay is visible.
    var isOverlayActive: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(
            book: book,
            onProgressChange: onProgressChange,
            onSelectionChange: onSelectionChange,
            onTap: onTap,
            onBrightnessChange: onBrightnessChange,
            onLoadingChanged: onLoadingChanged,
            onFontSizeChange: onFontSizeChange
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scrollHandler")
        config.userContentController.add(context.coordinator, name: "selectionHandler")

        let webView = WKWebView(frame: .zero, configuration: config)
        let initialPageMode = settings.isPageMode == true
        webView.scrollView.isPagingEnabled = initialPageMode
        webView.scrollView.bounces = !initialPageMode
        webView.scrollView.alwaysBounceVertical = !initialPageMode
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.backgroundColor = UIColor(hex: settings.theme.backgroundColor)
        webView.tintColor = selectionTintColor(for: settings)
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

        // Long press recognizer — blocks controls from opening on long press
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = false
        longPress.delegate = context.coordinator
        webView.addGestureRecognizer(longPress)

        // Brightness pan recognizer — left 15%, vertical
        let brightnessPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleBrightnessPan(_:))
        )
        brightnessPan.cancelsTouchesInView = false
        brightnessPan.delegate = context.coordinator
        webView.addGestureRecognizer(brightnessPan)
        context.coordinator.brightnessPanGesture = brightnessPan

        // Pinch to change font size — disable default WKWebView pinch zoom first
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGesture.delegate = context.coordinator
        webView.addGestureRecognizer(pinchGesture)

        context.coordinator.currentFontSize = settings.fontSize
        context.coordinator.lastIsPageMode = settings.isPageMode == true

        loadContent(into: webView, coordinator: context.coordinator)
        onWebViewReady?(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let css = generateCSS(settings: settings)
        let isPageMode = settings.isPageMode == true
        let modeChanged = isPageMode != context.coordinator.lastIsPageMode
        context.coordinator.lastIsPageMode = isPageMode
        context.coordinator.currentFontSize = settings.fontSize
        let scrollListenerJS = isPageMode ? """
        window.removeEventListener('scroll', window.__frScrollHandler);
        window.__frScrollHandler = function() {
            var total = document.body.scrollWidth - window.innerWidth;
            if (total > 0) {
                window.webkit.messageHandlers.scrollHandler.postMessage(window.scrollX / total);
            }
        };
        window.addEventListener('scroll', window.__frScrollHandler, { passive: true });
        """ : """
        window.removeEventListener('scroll', window.__frScrollHandler);
        window.__frScrollHandler = function() {
            var total = document.body.scrollHeight - window.innerHeight;
            if (total > 0) {
                window.webkit.messageHandlers.scrollHandler.postMessage(window.scrollY / total);
            }
        };
        window.addEventListener('scroll', window.__frScrollHandler, { passive: true });
        """
        let js = """
        (function() {
            var el = document.getElementById('__fr_style');
            if (!el) {
                el = document.createElement('style');
                el.id = '__fr_style';
                if (document.head) document.head.appendChild(el);
            }
            if (el) el.textContent = `\(css)`;
            \(scrollListenerJS)
        })();
        """
        webView.evaluateJavaScript(js)
        webView.scrollView.isPagingEnabled = isPageMode
        webView.scrollView.bounces = !isPageMode
        webView.scrollView.alwaysBounceVertical = !isPageMode
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.backgroundColor = UIColor(hex: settings.theme.backgroundColor)
        webView.tintColor = selectionTintColor(for: settings)
        context.coordinator.isOverlayActive = isOverlayActive
        context.coordinator.isPageMode = isPageMode

        if modeChanged {
            let savedProgress = context.coordinator.lastKnownProgress
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak webView] in
                guard let webView = webView else { return }
                if isPageMode {
                    webView.evaluateJavaScript("document.body.scrollWidth - window.innerWidth") { result, _ in
                        let total: Double
                        if let n = result as? NSNumber { total = n.doubleValue }
                        else if let d = result as? Double { total = d }
                        else { return }
                        guard total > 0 else { return }
                        let raw = CGFloat(savedProgress) * CGFloat(total)
                        let pageW = webView.scrollView.bounds.width
                        let x = pageW > 0 ? round(raw / pageW) * pageW : raw
                        webView.scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: false)
                    }
                } else {
                    webView.evaluateJavaScript("document.body.scrollHeight - window.innerHeight") { result, _ in
                        let total: Double
                        if let n = result as? NSNumber { total = n.doubleValue }
                        else if let d = result as? Double { total = d }
                        else { return }
                        guard total > 0 else { return }
                        let y = CGFloat(savedProgress) * CGFloat(total)
                        webView.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                    }
                }
            }
        }
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
        let isPageMode = settings.isPageMode == true

        let progressJS: String
        if savedProgress > 0 {
            progressJS = isPageMode ? """
            window.addEventListener('load', function() {
                setTimeout(function() {
                    var total = document.body.scrollWidth - window.innerWidth;
                    var raw = total * \(savedProgress);
                    var pageW = window.innerWidth;
                    window.scrollTo(Math.round(raw / pageW) * pageW, 0);
                }, 200);
            });
            """ : """
            window.addEventListener('load', function() {
                setTimeout(function() {
                    var total = document.body.scrollHeight - window.innerHeight;
                    window.scrollTo(0, total * \(savedProgress));
                }, 100);
            });
            """
        } else {
            progressJS = ""
        }

        let scrollJS = isPageMode ? """
        window.__frScrollHandler = function() {
            var total = document.body.scrollWidth - window.innerWidth;
            if (total > 0) {
                window.webkit.messageHandlers.scrollHandler.postMessage(window.scrollX / total);
            }
        };
        window.addEventListener('scroll', window.__frScrollHandler, { passive: true });
        var __frSelTimer = null;
        document.addEventListener('selectionchange', function() {
            clearTimeout(__frSelTimer);
            __frSelTimer = setTimeout(function() {
                var text = window.getSelection().toString().trim();
                window.webkit.messageHandlers.selectionHandler.postMessage(text);
            }, 300);
        });
        """ : """
        window.__frScrollHandler = function() {
            var total = document.body.scrollHeight - window.innerHeight;
            if (total > 0) {
                window.webkit.messageHandlers.scrollHandler.postMessage(window.scrollY / total);
            }
        };
        window.addEventListener('scroll', window.__frScrollHandler, { passive: true });
        var __frSelTimer = null;
        document.addEventListener('selectionchange', function() {
            clearTimeout(__frSelTimer);
            __frSelTimer = setTimeout(function() {
                var text = window.getSelection().toString().trim();
                window.webkit.messageHandlers.selectionHandler.postMessage(text);
            }, 300);
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

    private func selectionTintColor(for settings: ReaderSettings) -> UIColor {
        settings.theme.isLight
            ? UIColor(red: 0, green: 0.39, blue: 1.0, alpha: 1.0)
            : UIColor(red: 0.9, green: 0.9, blue: 1.0, alpha: 1.0)
    }

    private func generateCSS(settings: ReaderSettings) -> String {
        let selectionBg = settings.theme.isLight ? "rgba(0, 100, 255, 0.5)" : "rgba(255,255,255,0.45)"
        let linkColor = settings.theme.isLight ? "#0055CC" : "#5B9EF4"
        let isPageMode = settings.isPageMode == true
        let m = settings.margins.pixelValue

        let bodyLayout = isPageMode ? """
        html { height: 100%; overflow-y: hidden; }
        body {
            height: 100%;
            margin: 0;
            padding: 0;
            word-break: break-word;
            overflow-wrap: break-word;
            -webkit-column-width: 100vw;
            -webkit-column-gap: 0px;
            -webkit-column-fill: auto;
        }
        body > * {
            padding-left: \(m)px;
            padding-right: \(m)px;
        }
        body > p, body > div, body > section, body > article {
            padding-top: 0;
            padding-bottom: 0;
        }
        body > *:first-child { margin-top: 16px; }
        """ : """
        body {
            padding: \(settings.margins.cssValue);
            padding-bottom: 80px;
            word-break: break-word;
            overflow-wrap: break-word;
        }
        """

        return """
        * { box-sizing: border-box; }
        html, body {
            margin: 0;
            padding: 0;
            background-color: \(settings.theme.backgroundColor);
            color: \(settings.theme.textColor);
            font-family: '\(settings.fontName)', Georgia, serif;
            font-size: \(Int(settings.fontSize))px;
            line-height: \(settings.lineSpacing.cssValue);
            -webkit-user-select: text;
        }
        \(bodyLayout)
        ::selection { background-color: \(selectionBg) !important; }
        ::-webkit-selection { background-color: \(selectionBg) !important; }
        p { margin: 0.4em 0; text-indent: 1.5em; }
        h1, h2, h3, h4 { font-weight: bold; margin: 1em 0 0.4em; text-indent: 0; text-align: center; }
        img { max-width: 100%; height: auto; display: block; margin: 1em auto; }
        a { color: \(linkColor); text-decoration: underline; }
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
        var onLoadingChanged: ((Bool) -> Void)?
        var onFontSizeChange: ((Float) -> Void)?
        var isOverlayActive = false
        var isPageMode = false
        var isLongPressActive = false
        var lastKnownProgress: Float = 0
        var lastIsPageMode: Bool = false
        var currentFontSize: Float = 18
        var pinchStartFontSize: Float = 18
        weak var brightnessPanGesture: UIPanGestureRecognizer?
        private var brightnessDragStart: CGFloat = 0
        private var saveTimer: Timer?

        init(book: Book,
             onProgressChange: ((Float) -> Void)?,
             onSelectionChange: ((String?) -> Void)?,
             onTap: (() -> Void)?,
             onBrightnessChange: ((CGFloat) -> Void)?,
             onLoadingChanged: ((Bool) -> Void)?,
             onFontSizeChange: ((Float) -> Void)?) {
            self.book = book
            self.onProgressChange = onProgressChange
            self.onSelectionChange = onSelectionChange
            self.onTap = onTap
            self.onBrightnessChange = onBrightnessChange
            self.onLoadingChanged = onLoadingChanged
            self.onFontSizeChange = onFontSizeChange
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
            lastKnownProgress = p
            onProgressChange?(p)
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.book.readingProgress = p
            }
        }

        // MARK: UIKit gesture handlers

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !isOverlayActive, !isLongPressActive else { return }
            guard let view = gesture.view else { return }
            let x = gesture.location(in: view).x
            let w = view.bounds.width

            if isPageMode {
                if x < w * 0.3 {
                    turnPage(forward: false)
                } else if x > w * 0.7 {
                    turnPage(forward: true)
                } else {
                    onTap?()
                }
            } else {
                // Edges (~20% each side) are dead zones — only center opens controls
                if x >= w * 0.2 && x <= w * 0.8 {
                    onTap?()
                }
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                isLongPressActive = true
            case .ended, .cancelled, .failed:
                // Small delay so any pending tap handler sees the flag before it clears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.isLongPressActive = false
                }
            default:
                break
            }
        }

        private func turnPage(forward: Bool) {
            guard let sv = webView?.scrollView else { return }
            if isPageMode {
                let w = sv.bounds.width
                let x = forward
                    ? min(sv.contentOffset.x + w, max(0, sv.contentSize.width - w))
                    : max(sv.contentOffset.x - w, 0)
                sv.setContentOffset(CGPoint(x: x, y: sv.contentOffset.y), animated: true)
            } else {
                let h = sv.bounds.height
                let y = forward
                    ? min(sv.contentOffset.y + h, max(0, sv.contentSize.height - h))
                    : max(sv.contentOffset.y - h, 0)
                sv.setContentOffset(CGPoint(x: 0, y: y), animated: true)
            }
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

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartFontSize = currentFontSize
            case .changed:
                let newSize = Float(max(12, min(28, Int((pinchStartFontSize * Float(gesture.scale)).rounded()))))
                if newSize != currentFontSize {
                    onFontSizeChange?(newSize)
                }
            default:
                break
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Brightness pan must coexist with WKWebView's scroll gesture.
            // Scroll is disabled via isScrollEnabled=false in .began, so no conflict.
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.onLoadingChanged?(false) }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial HTML load and in-page anchor navigation
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            // External http/https links — open in Safari
            if let scheme = url.scheme, scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                // In-page anchors and other schemes — let WebView handle
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - NavigationBackSwipeEnabler

// When navigationBar is hidden, iOS disables interactivePopGestureRecognizer.
// This UIViewControllerRepresentable re-enables it so swipe-back still works.
private struct NavigationBackSwipeEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        vc.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        vc.navigationController?.interactivePopGestureRecognizer?.delegate = nil
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
