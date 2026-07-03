import SwiftUI

enum DS {
    enum Color {
        static let background      = SwiftUI.Color(hex: "0D0D0D")
        static let surface         = SwiftUI.Color(hex: "1A1A1A")
        static let surfaceElevated = SwiftUI.Color(hex: "242424")
        static let accent          = SwiftUI.Color(hex: "C8A96E")
        static let accentSubtle    = SwiftUI.Color(hex: "C8A96E").opacity(0.12)
        static let textPrimary     = SwiftUI.Color(hex: "F0F0F0")
        static let textSecondary   = SwiftUI.Color(hex: "ADADAD")
        static let textTertiary    = SwiftUI.Color(hex: "6B6B6B")
        static let separator       = SwiftUI.Color(hex: "2C2C2C")
        static let danger          = SwiftUI.Color(hex: "FF453A")
    }
}

extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
