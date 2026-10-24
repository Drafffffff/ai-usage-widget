import Foundation

enum UsageError: LocalizedError {
    case missingCredentials(String)
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let message): return message
        case .http(let status, let body):
            let snippet = body.isEmpty ? "" : " — \(body.prefix(120))"
            return "HTTP \(status)\(snippet)"
        case .badResponse(let message): return message
        }
    }
}

private struct HTTP {
    static func json(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Int, Any) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        if status == 401 || status == 403 { throw UsageError.http(status, text) }
        guard (200..<300).contains(status) else { throw UsageError.http(status, text) }
        let json = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        return (status, json)
    }
}

enum UsageFetcher {
    static func fetchAll(_ kinds: [ProviderKind]) async -> [ProviderUsage] {
        await withTaskGroup(of: ProviderUsage.self) { group in
            for kind in kinds {
                group.addTask { await fetch(kind) }
            }
            var results: [ProviderKind: ProviderUsage] = [:]
            for await usage in group { results[usage.kind] = usage }
            return kinds.compactMap { results[$0] }
        }
    }

    static func fetch(_ kind: ProviderKind) async -> ProviderUsage {
        do {
            switch kind {
            case .opencodeGo: return try await openCodeGo()
            case .openai: return try await codex()
            case .cursor: return try await cursor()
            }
        } catch let error as UsageError {
            return failure(kind, error)
        } catch {
            return failure(kind, .badResponse(error.localizedDescription))
        }
    }

    private static func failure(_ kind: ProviderKind, _ error: UsageError) -> ProviderUsage {
        var message = error.localizedDescription
        var needsAuth = false
        switch error {
        case .missingCredentials:
            needsAuth = true
        case .http(let status, _) where status == 401 || status == 403:
            needsAuth = true
            switch kind {
            case .opencodeGo: message = "API Key 无效，请在设置中更新"
            case .openai: message = "Codex 登录已过期，请运行 codex login"
            case .cursor: message = "Cursor 登录已过期，请打开 Cursor"
            }
        default:
            break
        }
        return ProviderUsage(
            kind: kind,
            state: needsAuth ? .needsAuth : .error,
            plan: nil,
            windows: [],
            stats: [],
            message: message,
            updatedAt: nil
        )
    }

    // MARK: - OpenCode Go

    private static func openCodeGo() async throws -> ProviderUsage {
        guard let key = LocalCredentials.openCodeKey() else {
            throw UsageError.missingCredentials("需要 OpenCode Go API Key，请打开设置填入")
        }
        let url = URL(string: "https://opencode.ai/zen/go/v1/usage")!
        let (_, json) = try await HTTP.json(url, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json",
            "User-Agent": "ai-usage-widget/1.0",
        ])

        guard let root = json as? [String: Any],
              let usage = root["usage"] as? [String: Any]
        else { throw UsageError.badResponse("OpenCode 返回了无法识别的数据") }

        let specs: [(String, String, Int)] = [
            ("rolling", "5H", 18_000),
            ("weekly", "WEEK", 604_800),
            ("monthly", "MONTH", 2_592_000),
        ]
        var windows: [WindowUsage] = []
        for (field, label, seconds) in specs {
            guard let entry = usage[field] as? [String: Any],
                  let percent = number(entry["percent"])
            else { continue }
            let status = (entry["status"] as? String) ?? "ok"
            guard status == "ok" || status == "rate-limited" else { continue }
            let reset = Parse.date(entry["resetsAt"] as? String)
                ?? Parse.date(entry["resets_at"] as? String)
                ?? Parse.date(entry["renewsAt"] as? String)
            windows.append(WindowUsage(
                label: label,
                usedPercent: status == "rate-limited" ? 100 : clamp(percent),
                resetsAt: reset,
                windowSeconds: seconds
            ))
        }
        guard !windows.isEmpty else {
            throw UsageError.badResponse("OpenCode 没有返回任何用量窗口")
        }

        var plan: String? = nil
        for field in ["plan", "plan_type", "planType", "subscription"] {
            if let value = root[field] as? String, !value.isEmpty { plan = value.uppercased(); break }
        }

        return ProviderUsage(
            kind: .opencodeGo,
            state: .ok,
            plan: plan,
            windows: windows,
            stats: [],
            message: nil,
            updatedAt: Date()
        )
    }

    // MARK: - Codex / OpenAI

    private static func codex() async throws -> ProviderUsage {
        guard let credentials = LocalCredentials.codexCredentials() else {
            throw UsageError.missingCredentials("未找到 Codex 登录，请先运行 codex login")
        }
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var headers: [String: String] = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "Accept": "application/json",
            "User-Agent": "codex_cli_rs/0.160.0",
            "originator": "codex_cli_rs",
            "OpenAI-Beta": "codex-1",
        ]
        if let accountID = credentials.accountID { headers["chatgpt-account-id"] = accountID }

        let (_, json) = try await HTTP.json(url, headers: headers)
        guard let root = json as? [String: Any] else {
            throw UsageError.badResponse("Codex 返回了无法识别的数据")
        }

        var windows: [WindowUsage] = []
        if let rateLimit = root["rate_limit"] as? [String: Any] {
            for field in ["primary_window", "secondary_window"] {
                guard let entry = rateLimit[field] as? [String: Any],
                      let used = number(entry["used_percent"])
                else { continue }
                let seconds = Int(number(entry["limit_window_seconds"]) ?? 0)
                let reset = Parse.date(unix: number(entry["reset_at"]))
                    ?? (number(entry["reset_after_seconds"]).map { Date().addingTimeInterval($0) })
                windows.append(WindowUsage(
                    label: windowLabel(seconds: seconds),
                    usedPercent: clamp(used),
                    resetsAt: reset,
                    windowSeconds: seconds > 0 ? seconds : nil
                ))
            }
        }

        var stats: [UsageStat] = []
        if let credits = root["credits"] as? [String: Any] {
            if (credits["unlimited"] as? Bool) == true {
                stats.append(UsageStat(label: "credits", value: "unlimited"))
            } else if let balanceString = credits["balance"] as? String,
                      let balance = Double(balanceString) {
                stats.append(UsageStat(label: "credits", value: Format.money(cents: balance * 100)))
            }
        }

        guard !windows.isEmpty else {
            throw UsageError.badResponse("该账号没有返回 Codex 用量窗口")
        }

        let plan = (root["plan_type"] as? String).map(prettyPlan)
        return ProviderUsage(
            kind: .openai,
            state: .ok,
            plan: plan,
            windows: windows,
            stats: stats,
            message: nil,
            updatedAt: Date()
        )
    }

    // MARK: - Cursor

    private static func cursor() async throws -> ProviderUsage {
        guard let token = LocalCredentials.cursorToken() else {
            throw UsageError.missingCredentials("未找到 Cursor 登录，请先登录 Cursor 应用")
        }
        let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
        let (_, json) = try await HTTP.json(url, method: "POST", headers: [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
        ], body: Data("{}".utf8))

        guard let root = json as? [String: Any] else {
            throw UsageError.badResponse("Cursor 返回了无法识别的数据")
        }
        guard let planUsage = root["planUsage"] as? [String: Any],
              let limit = number(planUsage["limit"]), limit > 0
        else {
            throw UsageError.badResponse("该 Cursor 账号没有个人用量配额")
        }

        let remaining = number(planUsage["remaining"]) ?? max(0, limit - (number(planUsage["includedSpend"]) ?? 0))
        let used = number(planUsage["includedSpend"]) ?? number(planUsage["totalSpend"]) ?? max(0, limit - remaining)
        let percentUsed = clamp(used / limit * 100)
        let cycleEnd = Parse.date(ms: number(root["billingCycleEnd"]))

        var stats: [UsageStat] = [
            UsageStat(label: "", value: "\(Format.money(cents: remaining)) left"),
        ]
        if let api = number(planUsage["apiPercentUsed"]) {
            stats.append(UsageStat(label: "API", value: Format.percent(api)))
        }
        if let auto = number(planUsage["autoPercentUsed"]), auto > 0 {
            stats.append(UsageStat(label: "Auto", value: Format.percent(auto)))
        }

        var plan = LocalCredentials.cursorPlan()?.uppercased()
        if plan == nil { plan = "PRO" }

        return ProviderUsage(
            kind: .cursor,
            state: .ok,
            plan: plan,
            windows: [
                WindowUsage(label: "BILLING CYCLE", usedPercent: percentUsed, resetsAt: cycleEnd, windowSeconds: nil),
            ],
            stats: stats,
            message: nil,
            updatedAt: Date()
        )
    }

    // MARK: - Helpers

    private static func windowLabel(seconds: Int) -> String {
        switch seconds {
        case 18_000: return "5H"
        case 604_800: return "WEEK"
        case 2_592_000: return "MONTH"
        case 86_400: return "DAY"
        case 0: return "LIMIT"
        default: return "\(max(1, seconds / 3600))H"
        }
    }

    private static func prettyPlan(_ raw: String) -> String {
        switch raw.lowercased() {
        case "prolite": return "PRO LITE"
        case "pro": return "PRO"
        case "plus": return "PLUS"
        case "free": return "FREE"
        case "team": return "TEAM"
        case "business": return "BUSINESS"
        default: return raw.uppercased()
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value.isFinite ? value : nil
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}
