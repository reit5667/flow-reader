import Foundation
import SwiftData

enum ReaderTheme: String, Codable, CaseIterable {
    case white
    case sepia
    case dark
    case black

    var backgroundColor: String {
        switch self {
        case .white: return "#FFFFFF"
        case .sepia: return "#F5E6C8"
        case .dark: return "#1C1C1E"
        case .black: return "#000000"
        }
    }

    var textColor: String {
        switch self {
        case .white: return "#1A1A1A"
        case .sepia: return "#3B2A1A"
        case .dark: return "#E5E5EA"
        case .black: return "#FFFFFF"
        }
    }
}

enum LineSpacing: String, Codable, CaseIterable {
    case compact
    case normal
    case wide

    var cssValue: String {
        switch self {
        case .compact: return "1.4"
        case .normal: return "1.7"
        case .wide: return "2.1"
        }
    }
}

enum ReaderMargins: String, Codable, CaseIterable {
    case narrow
    case medium
    case wide

    var cssValue: String {
        switch self {
        case .narrow: return "12px"
        case .medium: return "24px"
        case .wide: return "40px"
        }
    }
}

enum ReaderOrientation: String, Codable, CaseIterable {
    case auto
    case portrait
    case landscape
}

@Model
final class ReaderSettings {
    var theme: ReaderTheme
    var fontName: String
    var fontSize: Float
    var lineSpacing: LineSpacing
    var margins: ReaderMargins
    var orientation: ReaderOrientation

    init() {
        self.theme = .dark
        self.fontName = "Georgia"
        self.fontSize = 18
        self.lineSpacing = .normal
        self.margins = .medium
        self.orientation = .auto
    }
}
