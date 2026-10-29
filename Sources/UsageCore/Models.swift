import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case opencodeGo = "opencode-go"
    case claude = "claude"
    case openai = "openai"
    case cursor = "cursor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opencodeGo: return "OpenCode Go"
        case .claude: return "Claude"
        case .openai: return "OpenAI Codex"
        case .cursor: return "Cursor"
        }
    }

    var settingsName: String {
        switch self {
        case .opencodeGo: return "OpenCode Go"
        case .claude: return "Anthropic Claude (Pro/Max)"
        case .openai: return "OpenAI (ChatGPT / Codex)"
        case .cursor: return "Cursor"
        }
    }

    var dashboardURL: URL {
        switch self {
        case .opencodeGo: return URL(string: "https://opencode.ai/console")!
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
        case .openai: return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .cursor: return URL(string: "https://cursor.com/dashboard?tab=usage")!
        }
    }
}

enum ProviderState: String, Codable {
    case loading
    case ok
    case needsAuth
    case error
}

struct WindowUsage: Codable, Hashable, Identifiable {
    var label: String
    /// Percent of the window already consumed, 0...100.
    var usedPercent: Double
    var resetsAt: Date?
    var windowSeconds: Int?

    var id: String { label }
}

struct UsageStat: Codable, Hashable, Identifiable {
    var label: String
    var value: String

    var id: String { label + "=" + value }
}

struct ProviderUsage: Codable, Identifiable, Hashable {
    var kind: ProviderKind
    var state: ProviderState
    var plan: String?
    var windows: [WindowUsage]
    var stats: [UsageStat]
    var message: String?
    var updatedAt: Date?

    var id: String { kind.rawValue }

    var primaryWindow: WindowUsage? {
        // OpenCode Go and Claude Code: the 5-hour window is the daily-driver budget.
        if (kind == .opencodeGo || kind == .claude),
           let fiveHour = windows.first(where: { $0.windowSeconds == 18_000 || $0.label == "5H" }) {
            return fiveHour
        }
        return windows.max(by: { $0.usedPercent < $1.usedPercent })
    }

    /// Remaining percent of the tightest window.
    var remainingPercent: Int? {
        guard let primary = primaryWindow else { return nil }
        return Int((100 - min(100, max(0, primary.usedPercent))).rounded())
    }

    var subtitle: String? {
        if let plan, !plan.isEmpty { return plan }
        return nil
    }

    var otherWindows: [WindowUsage] {
        guard let primary = primaryWindow else { return [] }
        return windows.filter { $0.label != primary.label }
    }

    static func placeholder(_ kind: ProviderKind) -> ProviderUsage {
        ProviderUsage(kind: kind, state: .loading, plan: nil, windows: [], stats: [], message: nil, updatedAt: nil)
    }
}

struct CachedSnapshot: Codable {
    var providers: [ProviderUsage]
    var savedAt: Date
    /// LAN endpoint the iOS app and widget can read without opening the app.
    var syncURL: String? = nil
}

enum Format {
    /// "3d 4h", "5h 12m", "48m"
    static func countdown(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3600)
            let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        let days = Int(seconds / 86_400)
        let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600)
        return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }

    static func money(cents: Double) -> String {
        let dollars = cents / 100
        if abs(dollars.rounded() - dollars) < 0.005 {
            return "$\(Int(dollars.rounded()))"
        }
        return String(format: "$%.2f", dollars)
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}

enum Parse {
    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter.date(from: raw)
    }

    static func date(ms: Double?) -> Date? {
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    static func date(unix: Double?) -> Date? {
        guard let unix, unix > 0 else { return nil }
        return Date(timeIntervalSince1970: unix)
    }
}
