import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: CachedSnapshot?
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: PreviewData.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: Date(), snapshot: PreviewData.snapshot()))
        } else {
            completion(UsageEntry(date: Date(), snapshot: WidgetData.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snapshot = WidgetData.load()
        let entry = UsageEntry(date: Date(), snapshot: snapshot)
        let next = snapshot == nil
            ? Date().addingTimeInterval(5 * 60)
            : Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(
            snapshot: entry.snapshot,
            size: family == .systemLarge ? .large : .medium
        )
        .containerBackground(for: .widget) {
            WidgetBackdrop()
        }
        .widgetURL(URL(string: "aiusagewidget://settings"))
    }
}

struct AIUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageWidget", provider: UsageTimelineProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
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
