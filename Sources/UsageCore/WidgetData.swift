import Foundation

/// Snapshot exchange between the menu-bar host and the WidgetKit extension.
///
/// The widget runs sandboxed (required by pluginkit) and can only read its own
/// container. The host is not sandboxed, so it writes the same JSON to its own
/// Application Support folder and to the widget container once that exists.
enum WidgetData {
    static let widgetBundleID = "com.drafff.aiusagewidget.widget"

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Resolves to the widget container when read from inside the extension.
    static var widgetFile: URL {
        appSupportDirectory.appendingPathComponent("AIUsageWidget/widget.json")
    }

    /// Host-side copy, used by previews and as a fallback.
    static var hostFile: URL {
        home.appendingPathComponent("Library/Application Support/AIUsageWidget/widget.json")
    }

    static var containerRoot: URL {
        home.appendingPathComponent("Library/Containers/\(widgetBundleID)/Data")
    }

    static var containerFile: URL {
        containerRoot.appendingPathComponent("Library/Application Support/AIUsageWidget/widget.json")
    }

    static func encode(_ snapshot: CachedSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> CachedSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedSnapshot.self, from: data)
    }

    static func write(_ snapshot: CachedSnapshot) {
        guard let data = encode(snapshot) else { return }
        write(data, to: hostFile)
        write(data, to: widgetFile)

        let manager = FileManager.default
        if manager.fileExists(atPath: containerRoot.path) {
            write(data, to: containerFile)
        }
    }

    static func load() -> CachedSnapshot? {
        let manager = FileManager.default
        for url in [widgetFile, containerFile, hostFile] {
            if manager.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let snapshot = decode(data) {
                return snapshot
            }
        }
        return nil
    }

    private static func write(_ data: Data, to url: URL) {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
