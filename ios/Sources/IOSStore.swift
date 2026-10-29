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
    private let groupID = "group.com.drafff.aiusagewidget.ios"
    private var lanTask: Task<Void, Never>?

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
        if let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) {
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
                    fallbackToGroup(message: "无法访问同步文件夹")
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
                let decoded = try decoder.decode(CachedSnapshot.self, from: data)

                // iCloud can lag behind the shared container or the LAN snapshot.
                if let groupSnapshot = loadFromGroup(), groupSnapshot.savedAt > decoded.savedAt {
                    apply(groupSnapshot, rawData: nil, source: "app-group (newer)")
                } else {
                    apply(decoded, rawData: data, source: "iCloud")
                }

                if stale,
                   let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                }
            } catch {
                let ns = error as NSError
                note("FAILED \(ns.domain) \(ns.code) \(ns.localizedDescription)")
                fallbackToGroup(message: "读取失败 \(ns.code)")
            }
        } else {
            note("no bookmark")
            fallbackToGroup(message: "尚未选择同步文件夹")
        }
    }

    private func fallbackToGroup(message: String) {
        if let cached = loadFromGroup() {
            apply(cached, rawData: nil, source: "app-group")
        } else {
            lastError = message
        }
    }

    private func apply(_ snapshot: CachedSnapshot, rawData: Data?, source: String, refreshLAN: Bool = true) {
        self.snapshot = snapshot
        lastRead = Date()
        lastError = nil

        if let rawData, let url = groupURL("widget.json") {
            try? rawData.write(to: url, options: .atomic)
        }
        if let endpoint = snapshot.syncURL {
            writeEndpoint(endpoint)
        }

        NotificationScheduler.shared.sync(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        note("\(source) providers=\(snapshot.providers.count)")

        if refreshLAN { scheduleLANRefresh() }
    }

    private func scheduleLANRefresh() {
        guard lanTask == nil else { return }
        guard let endpoint = snapshot?.syncURL ?? readEndpoint(),
              let url = URL(string: endpoint)
        else { return }

        lanTask = Task { [weak self] in
            let result = await Self.fetchLAN(url)
            guard let self else { return }
            self.lanTask = nil
            if let (remote, data) = result {
                if remote.savedAt > (self.snapshot?.savedAt ?? .distantPast) {
                    self.apply(remote, rawData: data, source: "LAN", refreshLAN: false)
                } else {
                    self.note("LAN snapshot not newer")
                }
            } else {
                self.note("LAN fetch failed")
            }
        }
    }

    private static func fetchLAN(_ url: URL) async -> (CachedSnapshot, Data)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
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

    private func groupURL(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(name)
    }

    private func writeEndpoint(_ endpoint: String) {
        guard let url = groupURL("endpoint.txt") else { return }
        try? endpoint.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readEndpoint() -> String? {
        guard let url = groupURL("endpoint.txt"),
              let value = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadFromGroup() -> CachedSnapshot? {
        guard let url = groupURL("widget.json"),
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
