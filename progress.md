# FlowReader — Agent Progress Log

## Текущий статус
**Активная задача:** не выбрана  
**Следующая задача:** TASK-005 (functional, critical) — EPUB парсер

## Лог сессий

<!-- Агенты пишут сюда summary после каждой завершённой задачи -->
<!-- Формат: ### TASK-XXX — [дата] [краткое описание что сделано] -->

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
