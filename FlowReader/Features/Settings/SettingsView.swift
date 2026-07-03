import SwiftUI
import SwiftData

struct SettingsView: View {
    let onOpenSidebar: () -> Void

    @AppStorage("browserStartURL") private var browserStartURL = "https://flibusta.is"
    @Query private var settingsArray: [ReaderSettings]

    private var settings: ReaderSettings? { settingsArray.first }

    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Image("Wordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 40)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Браузер") {
                    HStack {
                        Text("Стартовая страница")
                        Spacer()
                        TextField("URL", text: $browserStartURL)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Зеркала Flibusta:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["https://flibusta.is", "https://flibusta.site", "https://flibs.net"], id: \.self) { mirror in
                                    Button(mirror.replacingOccurrences(of: "https://", with: "")) {
                                        browserStartURL = mirror
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .tint(browserStartURL == mirror ? .accentColor : .secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let settings {
                    readerSection(settings: settings)
                }

                Section("О приложении") {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentMargins(.bottom, 80, for: .scrollContent)
            .navigationTitle("Настройки")
            .tint(DS.Color.accent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onOpenSidebar() } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func readerSection(settings: ReaderSettings) -> some View {
        @Bindable var s = settings

        Section("Ридер — тема") {
            HStack(spacing: 10) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    ThemeButton(theme: theme, isSelected: s.theme == theme) {
                        s.theme = theme
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }

        Section("Ридер — шрифт и размер") {
            HStack(spacing: 16) {
                Button { s.fontSize = max(12, s.fontSize - 1) } label: {
                    Text("A")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Text("\(Int(s.fontSize))pt")
                    .font(.subheadline)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .center)
                Button { s.fontSize = min(28, s.fontSize + 1) } label: {
                    Text("A")
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Georgia", "SF Pro", "Menlo", "Palatino", "Helvetica Neue"], id: \.self) { font in
                        FontButton(fontName: font, isSelected: s.fontName == font) {
                            s.fontName = font
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }

        Section("Ридер — интервал и поля") {
            HStack(spacing: 8) {
                ForEach(LineSpacing.allCases, id: \.self) { spacing in
                    IconToggleButton(icon: spacingIcon(for: spacing), isSelected: s.lineSpacing == spacing) {
                        s.lineSpacing = spacing
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                ForEach(ReaderMargins.allCases, id: \.self) { margin in
                    IconToggleButton(icon: marginIcon(for: margin), isSelected: s.margins == margin) {
                        s.margins = margin
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
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
