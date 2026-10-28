import Foundation
import CommonCrypto
import CryptoKit

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

struct ClaudeCredentials {
    var accessToken: String
    var subscriptionType: String?
    var expiresAt: Date?
}

struct ClaudeAppSession {
    var sessionKey: String
    var organization: String
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

    // MARK: Claude desktop app

    static var claudeCookiesDB: URL {
        home.appendingPathComponent("Library/Application Support/Claude/Cookies")
    }

    static func claudeAppSession() -> ClaudeAppSession? {
        guard let values = claudeCookieValues(),
              let session = values["sessionKey"], !session.isEmpty,
              let organization = values["lastActiveOrg"], !organization.isEmpty
        else { return nil }
        return ClaudeAppSession(sessionKey: session, organization: organization)
    }

    static func claudeAppReady() -> Bool {
        FileManager.default.fileExists(atPath: claudeCookiesDB.path)
            && keychainExists(service: "Claude Safe Storage")
    }

    private static func claudeCookieValues() -> [String: String]? {
        guard FileManager.default.fileExists(atPath: claudeCookiesDB.path) else { return nil }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-cookies-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: temp) }
        do { try FileManager.default.copyItem(at: claudeCookiesDB, to: temp) } catch { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            temp.path,
            "select host_key, name, hex(encrypted_value) from cookies where name in ('sessionKey','lastActiveOrg') and host_key in ('.claude.ai','claude.ai');",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else { return nil }

        guard let passwordData = keychainPassword(service: "Claude Safe Storage"),
              let password = String(data: passwordData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let key = pbkdf2(password: password, salt: "saltysalt", iterations: 1003)
        else { return nil }

        var values: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let host = String(parts[0])
            let name = String(parts[1])
            let hex = String(parts[2])
            if let value = decryptCookie(host: host, hex: hex, key: key) {
                values[name] = value
            }
        }
        return values
    }

    private static func decryptCookie(host: String, hex: String, key: Data) -> String? {
        guard let encrypted = dataFromHex(hex), encrypted.count > 3,
              encrypted.prefix(3) == Data("v10".utf8)
        else { return nil }
        guard var plain = aes128CBCDecrypt(Data(encrypted.dropFirst(3)), key: key) else { return nil }

        // Chromium prefixes the plaintext with SHA256(host_key).
        let hostHash = Data(SHA256.hash(data: Data(host.utf8)))
        if plain.count > 32, plain.prefix(32) == hostHash {
            plain = Data(plain.dropFirst(32))
        }
        return String(data: plain, encoding: .utf8)
    }

    private static func pbkdf2(password: String, salt: String, iterations: UInt32) -> Data? {
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        var derived = [UInt8](repeating: 0, count: 16)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes, passwordBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            iterations,
            &derived, derived.count
        )
        return status == kCCSuccess ? Data(derived) : nil
    }

    private static func aes128CBCDecrypt(_ ciphertext: Data, key: Data) -> Data? {
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var outputLength = 0
        let status = ciphertext.withUnsafeBytes { input in
            key.withUnsafeBytes { keyBytes in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress, key.count,
                    iv,
                    input.baseAddress, ciphertext.count,
                    &output, output.count,
                    &outputLength
                )
            }
        }
        return status == kCCSuccess ? Data(output.prefix(outputLength)) : nil
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    // MARK: Claude Code

    static var claudeCredentialsFile: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }

    static func claudeCredentials() -> ClaudeCredentials? {
        var data: Data?
        if FileManager.default.fileExists(atPath: claudeCredentialsFile.path) {
            data = try? Data(contentsOf: claudeCredentialsFile)
        }
        if data == nil {
            data = keychainPassword(service: "Claude Code-credentials")
        }
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }

        let rawExpiry = (oauth["expiresAt"] as? NSNumber)?.doubleValue
        let expiry: Date? = rawExpiry.map { value in
            Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
        }
        return ClaudeCredentials(
            accessToken: token,
            subscriptionType: oauth["subscriptionType"] as? String,
            expiresAt: expiry
        )
    }

    static func claudeReady() -> Bool {
        if FileManager.default.fileExists(atPath: claudeCredentialsFile.path) { return true }
        return keychainExists(service: "Claude Code-credentials")
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

    private static func keychainExists(service: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); return false }
        return process.terminationStatus == 0
    }

    private static func keychainPassword(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

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
