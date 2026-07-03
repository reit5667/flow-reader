# PRD: FlowReader — Редизайн UI (Design System v2)

**Дата:** 2026-07-03  
**Статус:** Активный  
**Scope:** Визуальный редизайн всех экранов под новый бренд

---

## Обзор

Привести весь UI FlowReader в соответствие с новой айдентикой: иконка (открытая книга, gold/black) и wordmark (Flow[gold] + Reader[серый]). Переработать Design System — цвета, типографику, карточки, навигацию, панели.

---

## Дизайн-токены (Design System v2)

### Цвета

| Токен | Hex | Использование |
|---|---|---|
| `background` | `#0D0D0D` | Основной фон всех экранов |
| `surface` | `#1A1A1A` | Карточки, шиты, панели |
| `surfaceElevated` | `#242424` | Поверх surface (поиск, кнопки) |
| `accent` | `#C8A96E` | CTA, акценты, иконка, "Flow" в wordmark |
| `accentSubtle` | `rgba(200,169,110,0.12)` | Фон выбранных элементов |
| `textPrimary` | `#F0F0F0` | Основной текст |
| `textSecondary` | `#ADADAD` | "Reader" в wordmark, вторичный текст |
| `textTertiary` | `#6B6B6B` | Плейсхолдеры, метки |
| `separator` | `#2C2C2C` | Разделители, рамки |
| `destructive` | `#FF453A` | Удаление |

### Типографика

| Стиль | Параметры |
|---|---|
| `largeTitle` | SF Pro Display Bold, 28pt |
| `title` | SF Pro Display Semibold, 20pt |
| `body` | SF Pro Text Regular, 16pt |
| `caption` | SF Pro Text Regular, 12pt, textTertiary |

### Форма элементов

| Элемент | Radius |
|---|---|
| Обложка книги | 8pt |
| Карточка/панель | 12pt |
| Кнопки-пилюли | 20pt (полный) |
| Поле поиска | 10pt |

### Анимации

- Все переходы: fade ≤80мс
- Смена темы ридера: мгновенно
- Появление UI: ease-in-out 80мс

---

## Экраны для редизайна

### 1. Библиотека (LibraryView)

**Текущее состояние:** 3 колонки, #0F0F0F фон, карточки с прогресс-баром  
**Нужно:**
- Фон `#0D0D0D`
- 2 колонки (вместо 3) — обложки крупнее, читабельнее
- Карточка: обложка 2:3, radius 8; под ней название (1 строка, semibold 13pt textPrimary) + автор (1 строка, 11pt textTertiary); прогресс-бар 2px, цвет accent
- Метка "%" прогресса справа от бара (11pt textTertiary)
- Плейсхолдер без обложки: gradient surface→surfaceElevated + первая буква названия 28pt accent
- AddBookCard: штрихованная рамка accent, иконка `plus` accent, текст "Добавить книгу" textTertiary
- Строка поиска: фон surfaceElevated, placeholder textTertiary, tint accent
- Wordmark (уже добавлен) — оставить как есть

**Acceptance criteria:**
- Сетка 2 колонки, spacing 12pt горизонтальный и вертикальный
- Обложки кликабельны, контекстное меню работает
- Поиск и фильтр работают

### 2. Сайдбар (SidebarView)

**Текущее состояние:** 260px overlay, blur background  
**Нужно:**
- Фон `#1A1A1A` (сплошной, без blur)
- Граница справа: 1px separator
- Пункты меню: иконка accent + текст textPrimary; активный пункт — фон accentSubtle, текст accent
- Последняя книга: обложка 40x56 radius 6, название 13pt semibold, автор 11pt textTertiary; фон surface, radius 8
- Разделитель separator между секциями

**Acceptance criteria:**
- Свайп влево закрывает
- Корректная safe area снизу

### 3. Ридер — панель управления (ReaderControlsView)

**Текущее состояние:** нижний шит с drag handle, слайдер, 3 кнопки  
**Нужно:**
- Фон `#1A1A1A`, drag handle separator
- Слайдер: thumb цвет accent, track фон separator
- Прогресс в % рядом со слайдером (textTertiary)
- Кнопки: иконка textSecondary, при нажатии — accent
- Кнопка настроек: `slider.horizontal.3` (уже есть)

**Acceptance criteria:**
- Слайдер перематывает позицию
- Все кнопки открывают нужные шиты

### 4. Ридер — панель настроек (ReaderSettingsPanel)

**Текущее состояние:** серый фон, цветные кнопки AccentColor  
**Нужно:**
- Фон `#1A1A1A`
- Кнопки темы: border separator, выбранная — border accent, фон accentSubtle
- Кнопки шрифта: фон surfaceElevated, выбранная — border accent, текст accent
- Кнопки иконок (интервал/поля/режим): аналогично
- Заголовки секций: caption textTertiary

**Acceptance criteria:**
- Все настройки применяются live
- Выбранное состояние визуально чёткое

### 5. Настройки (SettingsView)

**Текущее состояние:** стандартный Form iOS  
**Нужно:**
- Wordmark уже добавлен — проверить что выглядит хорошо
- Заголовки секций Form: uppercase caption textTertiary (стандартный iOS, это уже так)
- Акцент `.tint(Color(hex: "#C8A96E"))` для всего NavigationStack
- Кнопки зеркал: выбранное — border accent

**Acceptance criteria:**
- Wordmark виден и не обрезается
- Tint применён к кнопкам и ссылкам

### 6. DS.swift — обновление токенов

**Текущее состояние:** `#0F0F0F` background, `#1C1C1E` surface, `#C8A96E` accent  
**Нужно:** Привести к новой палитре из Design Tokens выше

**Acceptance criteria:**
- Все экраны автоматически подхватят новые цвета через DS.*

---

## Модель данных
Изменений нет — только визуальный слой.

---

## Технические ограничения

- iOS 17+, SwiftUI + UIKit гибрид
- WKWebView в ридере — CSS темы менять отдельно через `generateCSS`
- `DS.swift` — централизованный Design System, обновлять в первую очередь
- После изменений `DS.swift` перебилдить — все экраны подхватят автоматически

---

## Этапы / Milestones

| Этап | Задачи | Приоритет |
|---|---|---|
| 1. DS Foundation | Обновить DS.swift токены | Critical |
| 2. Library | 2 колонки, новые карточки | High |
| 3. Sidebar | Новый стиль | High |
| 4. Reader UI | Controls + Settings panel | Medium |
| 5. Settings | Tint + проверка wordmark | Low |

---

## Потенциальные проблемы

- **BookCard spacing:** при переходе 3→2 колонки карточки станут шире — проверить что текст не обрезается
- **Placeholder:** цвет градиента должен отличаться от фона — иначе пустые слоты сольются
- **Контраст:** accent (#C8A96E) на surface (#1A1A1A) — проверить WCAG AA
- **ReaderSettingsPanel** использует `.regularMaterial` — заменить на явный цвет DS

---

## Будущие улучшения (не в этом спринте)

- Анимированный переход при открытии книги (обложка → ридер)
- Dark/light тема библиотеки (сейчас только dark)
- Кастомные цвета для карточек книг
