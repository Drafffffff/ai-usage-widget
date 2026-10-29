import Foundation
import WidgetKit

@MainActor
final class Store: ObservableObject {
    @Published var providers: [ProviderUsage] = []
    @Published var refreshing = false
    @Published var enabledKinds: Set<ProviderKind> {
        didSet {
            persistEnabledKinds()
            syncProviders()
            publishWidgetSnapshot()
        }
    }

    var openSettings: () -> Void = {}

    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var lastRefresh: Date?
    private let defaults = UserDefaults.standard

    init() {
        if let stored = defaults.array(forKey: "enabledKinds") as? [String] {
            enabledKinds = Set(stored.compactMap(ProviderKind.init(rawValue:)))
        } else {
            enabledKinds = Set(ProviderKind.allCases)
        }
        if enabledKinds.isEmpty { enabledKinds = Set(ProviderKind.allCases) }

        if defaults.object(forKey: "didEnableClaude") == nil {
            enabledKinds.insert(.claude)
            defaults.set(true, forKey: "didEnableClaude")
            persistEnabledKinds()
        }

        let cached = Dictionary(
            uniqueKeysWithValues: (WidgetData.load()?.providers ?? []).map { ($0.kind, $0) }
        )
        providers = ProviderKind.allCases
            .filter { enabledKinds.contains($0) }
            .map { cached[$0] ?? ProviderUsage.placeholder($0) }
    }

    func refresh() {
        guard refreshTask == nil else { return }
        let kinds = ProviderKind.allCases.filter { enabledKinds.contains($0) }
        guard !kinds.isEmpty else { return }
        refreshing = true

        refreshTask = Task { [weak self] in
            let fetched = await UsageFetcher.fetchAll(kinds)
            guard let self else { return }
            self.apply(fetched)
            self.refreshing = false
            self.refreshTask = nil
        }
    }

    func setEnabled(_ kind: ProviderKind, _ enabled: Bool) {
        if enabled { enabledKinds.insert(kind) } else { enabledKinds.remove(kind) }
        if enabled, providers.first(where: { $0.kind == kind })?.windows.isEmpty != false {
            refresh()
        }
    }

    func saveOpenCodeKey(_ key: String) {
        LocalConfig.set("opencodeKey", key.trimmingCharacters(in: .whitespacesAndNewlines))
        refresh()
    }

    var openCodeKeySource: String? { LocalCredentials.openCodeKeySource() }

    /// Writes the current data for the WidgetKit extension and asks it to reload.
    func publishWidgetSnapshot() {
        let visible = providers.filter {
            enabledKinds.contains($0.kind) && !$0.windows.isEmpty
        }

        // A failed refresh must never blank a widget that already has data.
        if visible.isEmpty, !enabledKinds.isEmpty {
            if let existing = WidgetData.load(), !existing.providers.isEmpty {
                return
            }
        }
        guard lastRefresh != nil || !visible.isEmpty || enabledKinds.isEmpty else { return }

        let snapshot = CachedSnapshot(providers: visible, savedAt: Date(), syncURL: LocalServer.url)
        WidgetData.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Private

    private func apply(_ fetched: [ProviderUsage]) {
        let previous = Dictionary(uniqueKeysWithValues: providers.map { ($0.kind, $0) })
        var merged: [ProviderUsage] = []
        for kind in ProviderKind.allCases where enabledKinds.contains(kind) {
            guard var usage = fetched.first(where: { $0.kind == kind }) else { continue }
            if usage.state != .ok,
               let old = previous[kind],
               !old.windows.isEmpty {
                // Keep the last good numbers visible, but flag the failure.
                usage.windows = old.windows
                usage.plan = usage.plan ?? old.plan
                usage.stats = old.stats
                usage.updatedAt = old.updatedAt
            }
            merged.append(usage)
        }
        providers = merged
        lastRefresh = Date()
        publishWidgetSnapshot()

        // Retry quickly after a transient failure instead of waiting 5 minutes.
        if merged.contains(where: { $0.state == .error }) {
            scheduleRetry()
        } else {
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.refresh()
        }
    }

    private func syncProviders() {
        let order = ProviderKind.allCases.filter { enabledKinds.contains($0) }
        let known = Dictionary(uniqueKeysWithValues: providers.map { ($0.kind, $0) })
        providers = order.map { known[$0] ?? ProviderUsage.placeholder($0) }
    }

    private func persistEnabledKinds() {
        defaults.set(
            ProviderKind.allCases.filter { enabledKinds.contains($0) }.map(\.rawValue),
            forKey: "enabledKinds"
        )
    }
}
