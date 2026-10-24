import SwiftUI

// MARK: - Preview data

enum PreviewData {
    static func snapshot(now: Date = Date()) -> CachedSnapshot {
        CachedSnapshot(
            providers: [
                ProviderUsage(
                    kind: .opencodeGo,
                    state: .ok,
                    plan: "GO",
                    windows: [
                        WindowUsage(label: "5H", usedPercent: 13, resetsAt: now.addingTimeInterval(2 * 3600 + 2400), windowSeconds: 18_000),
                        WindowUsage(label: "WEEK", usedPercent: 8, resetsAt: now.addingTimeInterval(4 * 86_400 + 5 * 3600), windowSeconds: 604_800),
                        WindowUsage(label: "MONTH", usedPercent: 4, resetsAt: now.addingTimeInterval(21 * 86_400), windowSeconds: 2_592_000),
                    ],
                    stats: [],
                    message: nil,
                    updatedAt: now
                ),
                ProviderUsage(
                    kind: .openai,
                    state: .ok,
                    plan: "PRO LITE",
                    windows: [
                        WindowUsage(label: "WEEK", usedPercent: 2, resetsAt: now.addingTimeInterval(6 * 86_400 + 5 * 3600), windowSeconds: 604_800),
                    ],
                    stats: [UsageStat(label: "credits", value: "$0")],
                    message: nil,
                    updatedAt: now
                ),
                ProviderUsage(
                    kind: .cursor,
                    state: .ok,
                    plan: "PRO",
                    windows: [
                        WindowUsage(label: "BILLING CYCLE", usedPercent: 17, resetsAt: now.addingTimeInterval(9 * 86_400 + 3 * 3600), windowSeconds: nil),
                    ],
                    stats: [
                        UsageStat(label: "", value: "$16.51 left"),
                        UsageStat(label: "API", value: "31%"),
                    ],
                    message: nil,
                    updatedAt: now
                ),
            ],
            savedAt: now
        )
    }
}

// MARK: - Widget surfaces

/// Fills the widget with the same near-black / neon language as the app.
struct WidgetBackdrop: View {
    var body: some View {
        ZStack {
            Color(hex: 0x08080A)
            RadialGradient(
                colors: [Color(hex: 0x00E676, opacity: 0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [Color(hex: 0xFFB020, opacity: 0.075), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 280
            )
        }
    }
}

struct UsageWidgetView: View {
    enum Size { case medium, large }

    let snapshot: CachedSnapshot?
    let size: Size
    var monochromeOverride: Bool? = nil

    @Environment(\.widgetRenderingMode) private var renderingMode
    private var monochrome: Bool { monochromeOverride ?? (renderingMode != .fullColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 10)
            header

            if let providers = snapshot?.providers, !providers.isEmpty {
                if size == .large {
                    ForEach(providers) { usage in
                        Spacer(minLength: 8)
                        LargeProviderRow(usage: usage, monochrome: monochrome)
                    }
                } else {
                    ForEach(providers) { usage in
                        Spacer(minLength: 8)
                        MediumProviderRow(usage: usage, monochrome: monochrome)
                    }
                }
                Spacer(minLength: size == .large ? 8 : 12)
            } else {
                Spacer(minLength: 8)
                emptyState
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Palette.text)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("REMAINING")
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Palette.faint)
            Spacer(minLength: 4)
            if let savedAt = snapshot?.savedAt {
                Text(Format.relative(savedAt))
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Waiting for usage data")
                .font(.system(size: 11, weight: .semibold))
            Text("Check the menu bar app and network")
                .font(.system(size: 8.5))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

@ViewBuilder
private func dashboardLink<Content: View>(for usage: ProviderUsage, @ViewBuilder content: () -> Content) -> some View {
    Link(destination: usage.kind.dashboardURL) {
        content()
    }
}

private struct LargeProviderRow: View {
    let usage: ProviderUsage
    let monochrome: Bool

    var body: some View {
        dashboardLink(for: usage) { card }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 7) {
                ProviderGlyph(kind: usage.kind, size: 18)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(usage.kind.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        if let plan = usage.plan, !plan.isEmpty {
                            Text(plan)
                                .font(.system(size: 6.5, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(Palette.faint)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 6)
                percent
            }

            if let primary = usage.primaryWindow {
                NeonBar(
                    fraction: (100 - primary.usedPercent) / 100,
                    accent: usage.accent,
                    height: 6,
                    showsTicks: false,
                    monochrome: monochrome
                )

                HStack(spacing: 4) {
                    if !otherWindows.isEmpty {
                        WindowDistribution(windows: otherWindows, compact: false)
                    } else if let stat = usage.stats.first {
                        SecondaryStat(stat: stat)
                    }
                    if usage.state != .ok {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Palette.warning)
                    }
                    Spacer(minLength: 4)
                    Text("resets \(Format.countdown(primary.resetsAt))")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 0.6)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sortedWindows: [WindowUsage] {
        usage.windows.sorted { ($0.windowSeconds ?? Int.max) < ($1.windowSeconds ?? Int.max) }
    }

    private var otherWindows: [WindowUsage] {
        guard let primary = usage.primaryWindow else { return [] }
        return sortedWindows.filter { $0.label != primary.label }
    }

    private var percent: some View {
        HStack(alignment: .top, spacing: 2) {
            Text("\(usage.remainingPercent ?? 0)")
                .font(.system(size: 32, weight: .semibold))
                .monospacedDigit()
                .tracking(-1.4)
            VStack(alignment: .leading, spacing: 1) {
                Text("%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.faint)
                Text(heroLabel)
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 2)
        }
    }

    private var heroLabel: String {
        switch usage.primaryWindow?.label {
        case "BILLING CYCLE": return "CYCLE"
        default: return usage.primaryWindow?.label ?? ""
        }
    }
}

private struct MediumProviderRow: View {
    let usage: ProviderUsage
    let monochrome: Bool

    var body: some View {
        dashboardLink(for: usage) { card }
    }

    private var card: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 7) {
                ProviderGlyph(kind: usage.kind, size: 15)

                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.kind.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if !otherWindows.isEmpty {
                            WindowDistribution(windows: otherWindows, compact: true)
                        } else if let stat = usage.stats.first {
                            SecondaryStat(stat: stat)
                        }
                        if usage.state != .ok {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 6.5))
                                .foregroundStyle(Palette.warning)
                        }
                    }
                }

                Spacer(minLength: 6)

                HStack(alignment: .top, spacing: 1.5) {
                    Text("\(usage.remainingPercent ?? 0)")
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-0.9)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text("%")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(Palette.faint)
                        Text(heroLabel)
                            .font(.system(size: 6.5, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 2)
                }
            }

            if let primary = usage.primaryWindow {
                NeonBar(
                    fraction: (100 - primary.usedPercent) / 100,
                    accent: usage.accent,
                    height: 3.5,
                    showsTicks: false,
                    monochrome: monochrome
                )
            }
        }
        .contentShape(Rectangle())
    }

    private var sortedWindows: [WindowUsage] {
        usage.windows.sorted { ($0.windowSeconds ?? Int.max) < ($1.windowSeconds ?? Int.max) }
    }

    private var otherWindows: [WindowUsage] {
        guard let primary = usage.primaryWindow else { return [] }
        return sortedWindows.filter { $0.label != primary.label }
    }

    private var heroLabel: String {
        switch usage.primaryWindow?.label {
        case "BILLING CYCLE": return "CYCLE"
        default: return usage.primaryWindow?.label ?? ""
        }
    }
}

private struct SecondaryStat: View {
    let stat: UsageStat

    var body: some View {
        HStack(spacing: 3) {
            if !stat.label.isEmpty {
                Text(stat.label.uppercased())
                    .font(.system(size: 6, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.faint)
            }
            Text(stat.value)
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.muted)
        }
        .lineLimit(1)
    }
}

private struct WindowDistribution: View {
    let windows: [WindowUsage]
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 9) {
            ForEach(windows) { window in
                HStack(spacing: 2.5) {
                    Text(label(for: window))
                        .font(.system(size: compact ? 6 : 6.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Palette.faint)
                    Text("\(Int((100 - window.usedPercent).rounded()))%")
                        .font(.system(size: compact ? 7 : 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .lineLimit(1)
    }

    private func label(for window: WindowUsage) -> String {
        switch window.label {
        case "WEEK": return compact ? "WK" : "WEEK"
        case "MONTH": return compact ? "MO" : "MONTH"
        case "BILLING CYCLE": return compact ? "CYCLE" : "BILLING CYCLE"
        default: return window.label
        }
    }
}

// MARK: - Previews

struct WidgetPreviewCard: View {
    let snapshot: CachedSnapshot?
    let width: CGFloat
    let height: CGFloat
    var monochrome: Bool = false

    var body: some View {
        ZStack {
            WidgetBackdrop()
            UsageWidgetView(
                snapshot: snapshot,
                size: height > 220 ? .large : .medium,
                monochromeOverride: monochrome ? true : nil
            )
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}
