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

    static var widgetLastGoodFile: URL {
        appSupportDirectory.appendingPathComponent("AIUsageWidget/widget-last-good.json")
    }

    static var hostLastGoodFile: URL {
        home.appendingPathComponent("Library/Application Support/AIUsageWidget/widget-last-good.json")
    }

    static var containerLastGoodFile: URL {
        containerRoot.appendingPathComponent("Library/Application Support/AIUsageWidget/widget-last-good.json")
    }

    /// Shared folder in the user's iCloud Drive, read by the iOS app.
    static var iCloudDirectory: URL? {
        let root = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        return root.appendingPathComponent("AIUsageWidget", isDirectory: true)
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
        let containerExists = manager.fileExists(atPath: containerRoot.path)
        if containerExists {
            write(data, to: containerFile)
        }

        if let iCloud = iCloudDirectory {
            write(data, to: iCloud.appendingPathComponent("widget.json"))
        }

        // Never leave the widget without a fallback: keep the last snapshot
        // that actually contained providers.
        if !snapshot.providers.isEmpty {
            write(data, to: hostLastGoodFile)
            write(data, to: widgetLastGoodFile)
            if containerExists {
                write(data, to: containerLastGoodFile)
            }
        }
    }

    static func load() -> CachedSnapshot? {
        let manager = FileManager.default
        let candidates = [
            widgetFile, containerFile, hostFile,
            widgetLastGoodFile, containerLastGoodFile, hostLastGoodFile,
        ]
        var emptySnapshot: CachedSnapshot?
        for url in candidates {
            guard manager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let snapshot = decode(data)
            else { continue }
            if !snapshot.providers.isEmpty { return snapshot }
            if emptySnapshot == nil { emptySnapshot = snapshot }
        }
        return emptySnapshot
    }

    private static func write(_ data: Data, to url: URL) {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
