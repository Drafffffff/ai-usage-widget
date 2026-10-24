import Foundation

// MARK: - Local config (0600)

enum LocalConfig {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIUsageWidget", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return base
    }

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func value(_ key: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    static func set(_ key: String, _ value: String?) {
        var root: [String: Any] = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if let value, !value.isEmpty {
            root[key] = value
        } else {
            root.removeValue(forKey: key)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

// MARK: - Local credential discovery

struct CodexCredentials {
    var accessToken: String
    var accountID: String?
}

enum LocalCredentials {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: OpenCode Go

    static func openCodeKey() -> String? {
        if let key = LocalConfig.value("opencodeKey"), !key.isEmpty { return key }
        if let env = ProcessInfo.processInfo.environment["OPENCODE_API_KEY"], !env.isEmpty {
            return clean(env)
        }
        let dataDir = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/share")
        let path = dataDir.appendingPathComponent("opencode/auth.json")
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        for entry in ["opencode-go", "opencode"] {
            guard let value = root[entry] as? [String: Any] else { continue }
            for field in ["key", "apiKey", "token"] {
                if let raw = value[field] as? String, let key = clean(raw), !looksLikeCookie(key) {
                    return key
                }
            }
        }
        return nil
    }

    static func openCodeKeySource() -> String? {
        if LocalConfig.value("opencodeKey") != nil { return "config.json" }
        if let env = ProcessInfo.processInfo.environment["OPENCODE_API_KEY"], !env.isEmpty { return "OPENCODE_API_KEY" }
        if openCodeKey() != nil { return "~/.local/share/opencode/auth.json" }
        return nil
    }

    // MARK: Codex / OpenAI

    static func codexCredentials() -> CodexCredentials? {
        let path = home.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              !token.isEmpty
        else { return nil }
        return CodexCredentials(accessToken: token, accountID: tokens["account_id"] as? String)
    }

    static func codexReady() -> Bool { codexCredentials() != nil }

    // MARK: Cursor

    static var cursorStateDB: URL {
        home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static func cursorToken() -> String? {
        sqliteValue(db: cursorStateDB, key: "cursorAuth/accessToken")
    }

    static func cursorPlan() -> String? {
        sqliteValue(db: cursorStateDB, key: "cursorAuth/stripeMembershipType")
    }

    static func cursorReady() -> Bool { cursorToken() != nil }

    static func sqliteValue(db: URL, key: String) -> String? {
        guard FileManager.default.fileExists(atPath: db.path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            db.path,
            "select value from ItemTable where key = '\(key.replacingOccurrences(of: "'", with: "''"))' limit 1;",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    // MARK: helpers

    private static func clean(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Bearer ", "bearer "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return value.isEmpty ? nil : value
    }

    /// Legacy dashboard cookies are not accepted by the usage endpoint.
    private static func looksLikeCookie(_ value: String) -> Bool {
        value.contains(";") || value.hasPrefix("auth=") || value.hasPrefix("Fe26.")
    }
}
