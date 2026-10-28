import AppKit
import SwiftUI

enum DebugTools {
    static func dump() {
        Task {
            let usages = await UsageFetcher.fetchAll(ProviderKind.allCases)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(usages), let text = String(data: data, encoding: .utf8) {
                print(text)
            } else {
                print("[]")
            }
            exit(0)
        }
        dispatchMain()
    }

    static func widgetSelfTest() {
        let manager = FileManager.default
        print("appSupport: \(WidgetData.widgetFile.path) exists=\(manager.fileExists(atPath: WidgetData.widgetFile.path))")
        print("host:       \(WidgetData.hostFile.path) exists=\(manager.fileExists(atPath: WidgetData.hostFile.path))")
        print("container:  \(WidgetData.containerFile.path) exists=\(manager.fileExists(atPath: WidgetData.containerFile.path))")
        guard let snapshot = WidgetData.load() else {
            print("snapshot: none")
            exit(1)
        }
        print("snapshot: \(snapshot.providers.count) providers, saved \(snapshot.savedAt)")
        for provider in snapshot.providers {
            print("- \(provider.kind.rawValue) plan=\(provider.plan ?? "-") remaining=\(provider.remainingPercent ?? -1)% windows=\(provider.windows.map { $0.label }.joined(separator: ","))")
        }
        exit(0)
    }

    static func preview(directory: String, live: Bool, cached: Bool, monochrome: Bool) {
        PreviewFlags.disableLinks = true
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let snapshot: CachedSnapshot
            if live {
                let providers = await UsageFetcher.fetchAll(ProviderKind.allCases)
                snapshot = CachedSnapshot(providers: providers, savedAt: Date())
            } else if cached {
                snapshot = WidgetData.load() ?? PreviewData.snapshot()
            } else {
                snapshot = PreviewData.snapshot()
            }

            let target = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

            let suffix = monochrome ? "-mono" : ""
            let specs: [(String, CGFloat, CGFloat)] = [
                ("widget-medium\(suffix).png", 338, 158),
                ("widget-large\(suffix).png", 338, 354),
            ]
            for (name, width, height) in specs {
                let content = ZStack {
                    Color(hex: 0x8E8E90)
                    WidgetPreviewCard(snapshot: snapshot, width: width, height: height, monochrome: monochrome)
                }
                .frame(width: width + 48, height: height + 48)
                guard let png = render(content, scale: 2) else {
                    FileHandle.standardError.write(Data("preview: render failed for \(name)\n".utf8))
                    exit(1)
                }
                try? png.write(to: target.appendingPathComponent(name))
                print(target.appendingPathComponent(name).path)
            }
            exit(0)
        }
        NSApp.run()
    }

    static func settingsPreview(path: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let store = Store()
            let content = ZStack {
                Color(hex: 0x8E8E90)
                SettingsView(store: store)
            }
            .frame(width: 470, height: 514)
            guard let png = render(content, scale: 2) else {
                FileHandle.standardError.write(Data("settings-preview: render failed\n".utf8))
                exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            print(path)
            exit(0)
        }
        NSApp.run()
    }

    static func icon(path: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let content = AppIconArtwork()
                .frame(width: 1024, height: 1024)
            guard let png = render(content, scale: 1, opaque: false) else {
                FileHandle.standardError.write(Data("icon: render failed\n".utf8))
                exit(1)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                print(path)
            } catch {
                FileHandle.standardError.write(Data("icon: \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }
        NSApp.run()
    }

    @MainActor private static func render(_ view: some View, scale: CGFloat, opaque: Bool = true) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = opaque
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

private struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 228, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x101014), Color(hex: 0x050506)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 228, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 6)
                )
                .frame(width: 880, height: 880)

            VStack(alignment: .leading, spacing: 52) {
                iconBar(fraction: 0.86, color: Color(hex: 0x00E676))
                iconBar(fraction: 0.62, color: Color(hex: 0x5AC8FA))
                iconBar(fraction: 0.38, color: Color(hex: 0xFFB020))
            }
            .frame(width: 500)

            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color(hex: 0x00E676))
                        .frame(width: 26, height: 26)
                        .shadow(color: Color(hex: 0x00E676).opacity(0.8), radius: 16)
                        .padding(.top, 238)
                        .padding(.trailing, 246)
                }
                Spacer()
            }
        }
        .frame(width: 1024, height: 1024)
    }

    private func iconBar(fraction: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.08))
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 500 * fraction)
                .shadow(color: color.opacity(0.55), radius: 24)
        }
        .frame(width: 500, height: 54)
    }
}
