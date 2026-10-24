import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    static let ink = Color(hex: 0x070708)
    static let card = Color.white.opacity(0.035)
    static let hairline = Color.white.opacity(0.07)
    static let text = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.44)
    static let faint = Color.white.opacity(0.26)
    static let warning = Color(hex: 0xFFB020)
}

extension ProviderKind {
    var accent: Color {
        switch self {
        case .opencodeGo: return Color(hex: 0x00E676)
        case .openai: return Color(hex: 0x5AC8FA)
        case .cursor: return Color(hex: 0xFFB020)
        }
    }
}

extension ProviderUsage {
    var accent: Color { kind.accent }
}
