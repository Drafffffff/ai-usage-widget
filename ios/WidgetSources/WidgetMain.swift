import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: CachedSnapshot?
}

enum SharedSnapshot {
    static let groupID = "group.com.drafff.aiusagewidget.ios"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget.json")
    }

    static func load() -> CachedSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedSnapshot.self, from: data)
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
        let entry = UsageEntry(date: Date(), snapshot: SharedSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
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
        .configurationDisplayName("AI Usage")
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
