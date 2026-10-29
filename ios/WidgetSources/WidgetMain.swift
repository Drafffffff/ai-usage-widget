import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: CachedSnapshot?
}

enum SharedSnapshot {
    static let groupID = "group.com.drafff.aiusagewidget.ios"

    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static var fileURL: URL? {
        groupURL?.appendingPathComponent("widget.json")
    }

    static var endpoint: URL? {
        if let url = groupURL?.appendingPathComponent("endpoint.txt"),
           let value = try? String(contentsOf: url, encoding: .utf8),
           let endpoint = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return endpoint
        }
        if let value = load()?.syncURL {
            return URL(string: value)
        }
        return nil
    }

    static func load() -> CachedSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedSnapshot.self, from: data)
    }

    static func store(_ data: Data) {
        guard let url = fileURL else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func fetch(_ url: URL) async -> (CachedSnapshot, Data)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try decoder.decode(CachedSnapshot.self, from: data), data)
        } catch {
            return nil
        }
    }
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: PreviewData.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = context.isPreview ? PreviewData.snapshot() : SharedSnapshot.load()
        completion(UsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let cached = SharedSnapshot.load()
        guard let endpoint = SharedSnapshot.endpoint else {
            completion(Timeline(
                entries: [UsageEntry(date: Date(), snapshot: cached)],
                policy: .after(Date().addingTimeInterval(15 * 60))
            ))
            return
        }

        Task {
            let remote = await SharedSnapshot.fetch(endpoint)
            if let remote {
                SharedSnapshot.store(remote.1)
            }
            let snapshot = remote?.0 ?? cached
            completion(Timeline(
                entries: [UsageEntry(date: Date(), snapshot: snapshot)],
                policy: .after(Date().addingTimeInterval(15 * 60))
            ))
        }
    }
}

struct UsageEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(
            snapshot: entry.snapshot,
            size: family == .systemLarge ? .large : .medium,
            monochromeOverride: false
        )
        .containerBackground(for: .widget) {
            WidgetBackdrop()
        }
    }
}

struct AIUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageWidgetIOS", provider: UsageProvider()) { entry in
            UsageEntryView(entry: entry)
        }
        .configurationDisplayName("Headroom")
        .description("Remaining OpenCode Go, OpenAI and Cursor usage.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct AIUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUsageWidget()
    }
}
