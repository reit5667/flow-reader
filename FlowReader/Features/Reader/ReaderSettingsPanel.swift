import SwiftUI
import SwiftData

struct ReaderSettingsPanel: View {
    @Bindable var settings: ReaderSettings
    let onClose: () -> Void

    private let fonts = ["Georgia", "SF Pro", "Menlo", "Palatino", "Helvetica Neue"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("Настройки чтения")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }

                Divider()

                // Theme
                VStack(alignment: .leading, spacing: 8) {
                    Text("Тема")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(ReaderTheme.allCases, id: \.self) { theme in
                            ThemeButton(theme: theme, isSelected: settings.theme == theme) {
                                settings.theme = theme
                            }
                        }
                        Spacer()
                    }
                }

                // Font size
                VStack(alignment: .leading, spacing: 8) {
                    Text("Размер шрифта")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button {
                            settings.fontSize = max(12, settings.fontSize - 1)
                        } label: {
                            Text("A")
                                .font(.system(size: 14))
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text("\(Int(settings.fontSize))pt")
                            .font(.subheadline)
                            .monospacedDigit()
                            .frame(width: 48, alignment: .center)
                        Button {
                            settings.fontSize = min(28, settings.fontSize + 1)
                        } label: {
                            Text("A")
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                }

                // Font family
                VStack(alignment: .leading, spacing: 8) {
                    Text("Шрифт")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(fonts, id: \.self) { font in
                                FontButton(fontName: font, isSelected: settings.fontName == font) {
                                    settings.fontName = font
                                }
                            }
                        }
                    }
                }

                // Line spacing
                VStack(alignment: .leading, spacing: 8) {
                    Text("Межстрочный интервал")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(LineSpacing.allCases, id: \.self) { spacing in
                            IconToggleButton(
                                icon: spacingIcon(for: spacing),
                                isSelected: settings.lineSpacing == spacing
                            ) {
                                settings.lineSpacing = spacing
                            }
                        }
                        Spacer()
                    }
                }

                // Margins
                VStack(alignment: .leading, spacing: 8) {
                    Text("Поля")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(ReaderMargins.allCases, id: \.self) { margin in
                            IconToggleButton(
                                icon: marginIcon(for: margin),
                                isSelected: settings.margins == margin
                            ) {
                                settings.margins = margin
                            }
                        }
                        Spacer()
                    }
                }

                // Page mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Режим листания")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        IconToggleButton(
                            icon: "scroll",
                            isSelected: settings.isPageMode != true
                        ) {
                            settings.isPageMode = false
                        }
                        IconToggleButton(
                            icon: "book.pages",
                            isSelected: settings.isPageMode == true
                        ) {
                            settings.isPageMode = true
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(.regularMaterial)
    }

    private func spacingIcon(for spacing: LineSpacing) -> String {
        switch spacing {
        case .compact: return "text.alignleft"
        case .normal:  return "line.3.horizontal"
        case .wide:    return "text.justify"
        }
    }

    private func marginIcon(for margin: ReaderMargins) -> String {
        switch margin {
        case .narrow: return "rectangle.compress.vertical"
        case .medium: return "rectangle"
        case .wide:   return "rectangle.expand.vertical"
        }
    }
}

// MARK: - ThemeButton

struct ThemeButton: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: theme.backgroundColor))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
                    )
                Text("A")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: theme.textColor))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FontButton

struct FontButton: View {
    let fontName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(fontName == "SF Pro" ? "SF" : fontName)
                .font(.custom(fontName == "SF Pro" ? ".AppleSystemUIFont" : fontName, size: 15))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - IconToggleButton

struct IconToggleButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 44, height: 36)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
