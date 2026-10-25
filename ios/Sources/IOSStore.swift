import Foundation

@MainActor
final class IOSStore: ObservableObject {
    @Published private(set) var snapshot: CachedSnapshot?
    @Published private(set) var folderName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRead: Date?

    private let bookmarkKey = "syncFolderBookmark"
    private let folderNameKey = "syncFolderName"

    init() {
        folderName = UserDefaults.standard.string(forKey: folderNameKey)
        reload()
    }

    func choose(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
            folderName = url.lastPathComponent
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reload() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            lastError = "尚未选择同步文件夹"
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
            guard url.startAccessingSecurityScopedResource() else {
                lastError = "无法访问同步文件夹"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url.appendingPathComponent("widget.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(CachedSnapshot.self, from: data)
            lastRead = Date()
            lastError = nil

            if stale,
               let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
