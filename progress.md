# FlowReader — Agent Progress Log

## Текущий статус
**Активная задача:** не выбрана  
**Следующая задача:** TASK-018

## Лог сессий

<!-- Агенты пишут сюда summary после каждой завершённой задачи -->
<!-- Формат: ### TASK-XXX — [дата] [краткое описание что сделано] -->

### TASK-017 — 2026-06-29 — BrowserView с перехватом загрузок EPUB/FB2
- `Features/Browser/BrowserView.swift`: WKWebView-браузер, стартовая страница flibusta.is
- Адресная строка + кнопки назад/вперёд/стоп-перезагрузить
- `WKNavigationDelegate.decidePolicyFor` перехватывает URL с расширением .epub/.fb2
- `decidePolicyForNavigationResponse` перехватывает по MIME-типу (epub, fictionbook)
- `WKDownloadDelegate`: пишет во временный файл с правильным расширением → `ImportService.importBook`
- Toast "Книга добавлена в библиотеку" после успешного импорта
- ContentView: заглушка `.browser` заменена на `BrowserView`
- Build succeeded ✅

### BUGFIX — 2026-06-29

Тестирование выявило критические баги, исправлены в той же сессии:
- **Тап/жест яркости не работали** — WKWebView съедал SwiftUI-жесты. Переделано на UIKit: UITapGestureRecognizer + UIPanGestureRecognizer добавлены прямо на WKWebView в makeUIView. BrightnessGestureView стал чисто визуальным индикатором (без жестов). UIGestureRecognizerDelegate: gestureRecognizerShouldBegin фильтрует панорамирование по зоне (левые 15%) и направлению (|dy|>|dx|*1.2).
- **Сайдбар съехал за статус-бар** — `.ignoresSafeArea()` был на VStack. Перенесён только на background: `.background(Color(.systemBackground).ignoresSafeArea())`.
- **Браузер/Настройки — нет кнопки назад** — добавлен NavigationStack с toolbar-кнопкой ☰ открывающей сайдбар для обоих разделов.
- **Название книги на английском, нет обложки** — ImportService теперь сразу после сохранения файла вызывает EPUBParser.parseMetadataOnly() / FB2Parser.parse(), обновляет book.title/author/coverImagePath. Добавлен parseMetadataOnly() в EPUBParser (unzip+OPF без чтения spine HTML).

### TASK-016 — 2026-06-29

SelectionToolbar.swift: ShareLink(item: форматированная цитата) + Bookmark кнопка. ShareLink: "«текст»\n— Автор, Название".
JS selectionchange (debounce 150ms) → postMessage(text) → Coordinator.onSelectionChange → ReaderView.selectedText.
ReaderWebView: onSelectionChange callback, "selectionHandler" registered in userContentController. Coordinator: обновлён init, handleMessage.
ReaderView: selectedText state, SelectionToolbar в ZStack (slide from bottom), onTapGesture: if selection active → clearSelection(). clearSelection(): JS removeAllRanges() + selectedText=nil. addBookmarkFromSelection(): Bookmark(offset=progress*100_000, previewText=selectedText[:100]).

### TASK-015 — 2026-06-28

BookmarksView: NavigationStack + List, ForEach(bookmarks) с .onDelete (свайп влево), превью текста (2 строки), % позиции (offset/1000) + дата/время. Фильтрация по book.id через @Query all + computed property. ContentUnavailableView при пустом.
Bookmark.offset хранит progress*100_000 (Int) — стабильно при смене размера шрифта. Display %: offset/1000.
addBookmark(): JS читает scrollY + totalHeight + elementFromPoint текст → JSON → Bookmark(offset, previewText) → bookmark.book = book → ctx.insert. Тост "Закладка добавлена" анимированный (появляется top, исчезает через 1.5с).
seekToBookmark: seek(to: Float(offset)/100_000).
ReaderControlsView: добавлен onBookmarkLongPress, .simultaneousGesture(LongPressGesture 0.5s) на кнопке bookmark.
ReaderView: showBookmarks state, .sheet BookmarksView, onBookmarkTap→addBookmark, onBookmarkLongPress→showBookmarks=true. xcodegen regenerated.

### TASK-014 — 2026-06-28

TOCItem struct (Identifiable, id=index) в TOCView.swift. TOCView: NavigationStack + List, текущая глава отмечена chevron.right + accentColor (апроксимация: progress * count), тап → onSelect + dismiss, кнопка "Готово", ContentUnavailableView при пустом списке.
EPUBParser: EPUBSpineItem(html, baseURL) — HTML читается внутри parse() до defer-cleanup (фикс bug: раньше URL-ы указывали на удалённый temp dir). NCXParser: парсит toc.ncx, navPoint title + src, матчит по filename на spine index. Fallback: "Глава N". OPFParser: ncxHref через media-type "application/x-dtbncx+xml".
FB2Parser: sectionDepth/sectionCounter, id="fr-chapter-N" в top-level секциях, inSectionTitle — первый title каждой секции идёт в tocItems. FB2ParseResult получил tocItems.
ReaderWebView: onTOCLoaded callback. loadEPUB: div-якорь fr-chapter-N перед каждым spine item. loadFB2: передаёт tocItems. ReaderView: showTOC state, seekToChapter(index) через JS getElementById + scrollIntoView, .sheet с TOCView. onTocTap: showControls=false + showTOC=true. xcodegen regenerated.

### TASK-013 — 2026-06-28

BrightnessGestureView: отдельный файл в Features/Reader/. Прозрачный оверлей на левые 15% экрана (GeometryReader + Color.clear с contentShape). DragGesture(minimumDistance: 8): активируется только при dy > dx*1.2 (вертикальный жест). Delta яркости пропорциональна 70% высоты экрана. UIScreen.main.brightness меняется в реальном времени. BrightnessIndicatorView: sun.max.fill / sun.min иконка + вертикальный прогресс-бар (4px × 80pt), полупрозрачный тёмный контейнер, прижат к левому краю. Индикатор появляется при начале жеста, скрывается через 1.5с после окончания (Task + sleep). ReaderView: BrightnessGestureView добавлен в ZStack между WebView и контрольными панелями. xcodegen regenerated.

### TASK-012 — 2026-06-28

ReaderSettingsPanel: тема (4 кружка с цветом + A), размер A-/A+ (12–28pt), шрифт (горизонтальный скролл, 5 вариантов), межстрочный интервал (3 иконки), поля (3 иконки). @Bindable ReaderSettings — все изменения мгновенны через updateUIView в ReaderWebView. ReaderView: showSettings state, панель как оверлей поверх всего, кнопка X закрывает. ThemeButton/FontButton/IconToggleButton с highlighted состоянием.

### TASK-011 — 2026-06-28

ReaderControlsView: оверлей поверх WKWebView (не сдвигает контент). Название + автор книги, Slider прогресса (0..1) с live seek через JS scrollTo, % прочитанного, 3 кнопки (TOC, Bookmark, Settings — заглушки). Тап по экрану показывает/скрывает шит (opacity animation 100ms). ReaderView: @State showControls + progress, колбэки onProgressChange и onWebViewReady от ReaderWebView, WKWebView ref для seek-команд. TASK-010 закрыта: FB2 уже работал через TASK-009.

### TASK-009 — 2026-06-28

ReaderView + ReaderWebView (UIViewRepresentable). EPUB: EPUBParser → spine HTML конкатенируется, body-контент извлекается, оборачивается в единый документ. FB2: готовый HTML из FB2Parser, CSS инжектируется в <head>. CSS из ReaderSettings: цвета, шрифт, размер, line-height, отступы. Прогресс: JS scroll listener → WKScriptMessageHandler → обновление book.readingProgress (дебаунс 1с). Восстановление позиции: window.scrollTo при load (100ms delay). updateUIView обновляет CSS без перезагрузки страницы. LibraryView: NavigationLink теперь открывает ReaderView.

### TASK-008 — 2026-06-28

SidebarView: оверлей 260px, без slide-анимации (opacity transition). Последняя книга (lastOpenedAt != nil) с обложкой-тумбнейлом сверху, затем 3 пункта меню (Моя полка, Интернет, Настройки). Тап вне сайдбара закрывает. ContentView переработан: ZStack с mainContent + SidebarView оверлей, свайп вправо от левого края (startX < 30, translation > 60) открывает, свайп влево закрывает. AppSection enum управляет активным разделом. LibraryView получил onOpenSidebar callback и кнопку ≡ в тулбаре.

### TASK-007 — 2026-06-28

LibraryView: NavigationStack + LazyVGrid 3 колонки. BookCard: CoverImage (aspect 2:3, placeholder если нет обложки), название (2 строки), автор (1 строка), % прогресса. ProgressBar (3px accent) поверх обложки. Сортировка по lastOpenedAt descending через @Query. Пустое состояние с иконкой и текстом. NavigationLink → заглушка ReaderView (TASK-008). ContentView обновлён: вместо Text("FlowReader") — LibraryView().

### TASK-006 — 2026-06-28

FB2Parser: XMLParserDelegate, стейт-машина по elementStack. Конвертирует section/title/p/emphasis/strong/epigraph/poem/stanza/cite/subtitle/empty-line → HTML. Сноски (<a type="note">) → <sup class="note-ref">. Бинарные блоки (<binary>) → base64 decode → Data. Обложка по id из <coverpage><image>. Экранирование HTML-символов. Возвращает FB2ParseResult(metadata, html) с полным HTML-документом (CSS встроен). xcodegen regenerated.

### TASK-005 — 2026-06-28

EPUBParser: минимальный ZIP-экстрактор (PKZip local headers, deflate через NSData.decompressed), парсинг META-INF/container.xml → путь к OPF, парсинг OPF через XMLParser (title, author, manifest, spine, cover). Возвращает EPUBMetadata(title, author, coverData?, spineItems[URL]). Дополнительные зависимости не нужны — только Foundation. xcodegen regenerated.

### TASK-004 — 2026-06-28

Share Sheet / Open In импорт EPUB и FB2.
ImportService: валидация формата по расширению, проверка размера (≤100MB), копирование через FileStorageService, создание Book в SwiftData (title из имени файла, author "Неизвестен" до парсинга).
AppState (@Observable): хранит pendingImportURL и ошибки импорта.
FlowReaderApp: .onOpenURL → appState.pendingImportURL.
ContentView: .onChange(of: pendingImportURL) → ImportService → alert при ошибке.
Info.plist с UTI для EPUB и FB2 уже был прописан в TASK-001. BUILD SUCCEEDED.

### TASK-003 — 2026-06-28

FileStorageService (singleton). Методы: saveBook(data:filename:), saveBook(from:), deleteBook(relativePath:), absoluteBookURL(relativePath:), saveCover(data:bookId:), deleteCover(relativePath:), absoluteCoverURL(relativePath:).
Папки Documents/Books/ и Documents/Covers/ создаются при инициализации.
Пути хранятся относительными (от Documents/) для совместимости с iCloud-бэкапами.
Sanitize filename убирает символы /\?%*|"<>:. BUILD SUCCEEDED.

### TASK-002 — 2026-06-28

SwiftData модели: Book, Bookmark, ReaderSettings.
Book: id (UUID unique), title, author, filePath, coverImagePath?, format (epub/fb2), addedAt, lastOpenedAt?, readingProgress (Float), currentOffset (Int), bookmarks (cascade delete).
Bookmark: id, offset, previewText, createdAt, book?.
ReaderSettings: theme (white/sepia/dark/black), fontName, fontSize, lineSpacing, margins, orientation. Дефолты: dark, Georgia, 18pt, normal, medium, auto.
Enums содержат CSS-значения для рендеринга. ModelContainer подключён в FlowReaderApp. BUILD SUCCEEDED.

### TASK-001 — 2026-06-28

Инициализирован Xcode проект FlowReader (bundle id: com.flowreader.app, iOS 17+).
Установлен xcodegen, создан project.yml. Структура папок: App/, Features/{Library,Reader,Browser,Settings}/, Core/{Models,Extensions}/, Services/, Resources/.
Info.plist включает CFBundleDocumentTypes для EPUB (org.idpf.epub-container) и FB2 (public.fb2) + UTImportedTypeDeclarations для FB2.
BUILD SUCCEEDED на симуляторе iPhone 17 Pro.
