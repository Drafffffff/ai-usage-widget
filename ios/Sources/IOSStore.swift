import Foundation
import WidgetKit

@MainActor
final class IOSStore: ObservableObject {
    @Published private(set) var snapshot: CachedSnapshot?
    @Published private(set) var folderName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRead: Date?
    @Published private(set) var debugText = ""

    private let bookmarkKey = "syncFolderBookmark"
    private let folderNameKey = "syncFolderName"
    private let bookmarkKindKey = "syncBookmarkKind"

    init() {
        folderName = UserDefaults.standard.string(forKey: folderNameKey)
        reload()
    }

    func chooseFolder(_ url: URL) {
        saveBookmark(url, kind: "folder")
    }

    func chooseFile(_ url: URL) {
        saveBookmark(url, kind: "file")
    }

    private func saveBookmark(_ url: URL, kind: String) {
        note("choose \(kind) \(url.path)")
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            note("started=\(started) exists=\(FileManager.default.fileExists(atPath: url.path))")
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)

            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                _ = try? FileManager.default.contentsOfDirectory(
                    at: coordinated,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            }
            if let coordinationError { throw coordinationError }

            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
            UserDefaults.standard.set(kind, forKey: bookmarkKindKey)
            folderName = url.lastPathComponent
            note("bookmark saved (\(bookmark.count) bytes)")
            reload()
        } catch {
            let ns = error as NSError
            note("choose FAILED \(ns.domain) \(ns.code) \(ns.localizedDescription)")
            lastError = "选择失败 \(ns.code)：\(ns.localizedDescription)"
        }
    }

    func reload() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            note("no bookmark")
            if let cached = loadFromGroup() {
                snapshot = cached
                lastError = nil
                lastRead = Date()
                WidgetCenter.shared.reloadAllTimelines()
                note("loaded app-group fallback")
            } else {
                lastError = "尚未选择同步文件夹"
            }
            return
        }

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            note("resolved stale=\(stale) \(url.path)")
            let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            note("ubiquitous=\(values?.isUbiquitousItem ?? false) download=\(values?.ubiquitousItemDownloadingStatus?.rawValue ?? "-")")
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)

            guard url.startAccessingSecurityScopedResource() else {
                note("startAccessing failed")
                lastError = "无法访问同步文件夹（请重新选择）"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let kind = UserDefaults.standard.string(forKey: bookmarkKindKey) ?? "folder"
            let data: Data
            if kind == "file" {
                data = try readCoordinated(url)
            } else {
                data = try readSnapshotData(in: url)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(CachedSnapshot.self, from: data)
            lastRead = Date()
            lastError = nil

            if let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.drafff.aiusagewidget.ios"
            ) {
                try? data.write(to: group.appendingPathComponent("widget.json"), options: .atomic)
                WidgetCenter.shared.reloadAllTimelines()
            }
            NSLog("AIUsageIOS sync: loaded \(snapshot?.providers.count ?? 0) providers")

            if stale,
               let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
        } catch {
            let ns = error as NSError
            note("FAILED \(ns.domain) \(ns.code) \(ns.localizedDescription)")
            if let cached = loadFromGroup() {
                snapshot = cached
                lastError = "显示最近同步数据"
                lastRead = Date()
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                lastError = "读取失败 \(ns.code)：\(ns.localizedDescription)"
            }
        }
    }

    private func loadFromGroup() -> CachedSnapshot? {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.drafff.aiusagewidget.ios"
        )?.appendingPathComponent("widget.json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedSnapshot.self, from: data)
    }

    private func note(_ text: String) {
        NSLog("AIUsageIOS sync: \(text)")
        var lines = debugText.split(separator: "\n").map(String.init)
        lines.append(text)
        if lines.count > 6 { lines.removeFirst(lines.count - 6) }
        debugText = lines.joined(separator: "\n")
    }

    private func readCoordinated(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try Data(contentsOf: coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw NSError(domain: "AIUsageIOS", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取 widget.json"])
        }
        return try result.get()
    }

    private func readSnapshotData(in folder: URL) throws -> Data {
        let manager = FileManager.default
        var candidates = [folder.appendingPathComponent("widget.json")]
        if folder.lastPathComponent != "AIUsageWidget" {
            candidates.append(folder.appendingPathComponent("AIUsageWidget/widget.json"))
        }

        var lastError: Error?
        for file in candidates {
            note("candidate \(file.path) exists=\(manager.fileExists(atPath: file.path))")
            do {
                let data = try readCoordinated(file)
                note("read \(data.count) bytes")
                return data
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }

        throw NSError(
            domain: "AIUsageIOS", code: 404,
            userInfo: [NSLocalizedDescriptionKey: "所选文件夹里没有 widget.json（请选 AIUsageWidget 文件夹）"]
        )
    }
}
