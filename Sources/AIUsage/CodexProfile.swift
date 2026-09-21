import CryptoKit
import Foundation

/// Values the fetcher needs from Codex account settings without importing
/// Preferences into the pure profile/catalog tests.
struct CodexPollingContext {
    var configuredPaths: [String] = []
    var rememberedPaths: Set<String> = []
    var ignoredPaths: Set<String> = []
    /// Filled by the store after process discovery.
    var discoveredPaths: [String] = []
    var label: (String) -> String? = { _ in nil }
}

/// Codex CLI homes and the stable provider identities derived from them.
/// Credentials remain in each profile's auth.json and are only read.
enum CodexProfile {
    static let defaultRelativePath = "~/.codex"
    static let defaultID = "Codex"
    static let idPrefix = "Codex-"
    static let authFileName = "auth.json"

    enum Source: Int, Comparable {
        case discovered = 0
        case configured = 1
        case `default` = 2

        static func < (lhs: Source, rhs: Source) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Entry: Equatable, Identifiable {
        var normalizedPath: String
        var providerID: String
        var source: Source
        /// Higher wins when two profiles contain the same access token.
        var preferenceRank: Int

        var id: String { providerID }
        var authPath: String {
            URL(fileURLWithPath: normalizedPath)
                .appendingPathComponent(authFileName)
                .path
        }
    }

    struct AuthSnapshot: Equatable {
        let accessToken: String
        let accountID: String
    }

    static var defaultNormalizedPath: String {
        normalizedPath(defaultRelativePath)
    }

    static func normalizedPath(_ raw: String) -> String {
        let expanded = (raw as NSString).expandingTildeInPath
        let absolute: String
        if (expanded as NSString).isAbsolutePath {
            absolute = expanded
        } else {
            absolute = (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent(expanded)
        }
        return normalizePOSIXPath(absolute)
    }

    static func providerID(for normalizedPath: String) -> String {
        if normalizedPath == defaultNormalizedPath { return defaultID }
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return idPrefix + suffix
    }

    static func defaultLabel(
        planType: String?,
        customLabel: String?,
        profilePath: String
    ) -> String {
        if let custom = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        guard let raw = planType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return profilePath == defaultNormalizedPath ? "Codex Personal" : profileDirectoryName(profilePath)
        }
        let plan = raw.lowercased()
        if plan.contains("enterprise") { return "Codex Enterprise" }
        if plan.contains("team") || plan.contains("business") { return "Codex Team" }
        if plan.contains("plus") || plan.contains("pro") || plan.contains("personal") || plan == "free" {
            return "Codex Personal"
        }
        return profileDirectoryName(profilePath)
    }

    static func catalog(
        configuredPaths: [String],
        rememberedPaths: Set<String>,
        discoveredPaths: [String],
        ignoredPaths: Set<String>
    ) -> [Entry] {
        var byPath: [String: Entry] = [:]

        func insert(path raw: String, source: Source, rank: Int) {
            let path = normalizedPath(raw)
            guard !ignoredPaths.contains(path) else { return }
            let entry = Entry(
                normalizedPath: path,
                providerID: providerID(for: path),
                source: source,
                preferenceRank: rank
            )
            if let existing = byPath[path] {
                if entry.source > existing.source
                    || (entry.source == existing.source && entry.preferenceRank > existing.preferenceRank) {
                    byPath[path] = entry
                }
            } else {
                byPath[path] = entry
            }
        }

        insert(path: defaultRelativePath, source: .default, rank: 2)
        for path in configuredPaths { insert(path: path, source: .configured, rank: 1) }
        for path in rememberedPaths { insert(path: path, source: .configured, rank: 0) }
        for path in discoveredPaths { insert(path: path, source: .discovered, rank: 0) }

        return byPath.values.sorted { lhs, rhs in
            if lhs.normalizedPath == defaultNormalizedPath { return true }
            if rhs.normalizedPath == defaultNormalizedPath { return false }
            return lhs.normalizedPath.localizedStandardCompare(rhs.normalizedPath) == .orderedAscending
        }
    }

    static func collapseDuplicateTokens(
        _ entries: [Entry],
        auth: (Entry) -> AuthSnapshot?
    ) -> [Entry] {
        var seen = [String: Entry]()
        var result: [Entry] = []
        for entry in entries {
            guard let snapshot = auth(entry) else { continue }
            let fingerprint = tokenFingerprint(snapshot.accessToken)
            if let existing = seen[fingerprint] {
                if prefers(entry, over: existing) {
                    seen[fingerprint] = entry
                    result.removeAll { $0.providerID == existing.providerID }
                    result.append(entry)
                }
            } else {
                seen[fingerprint] = entry
                result.append(entry)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.normalizedPath == defaultNormalizedPath { return true }
            if rhs.normalizedPath == defaultNormalizedPath { return false }
            return lhs.normalizedPath.localizedStandardCompare(rhs.normalizedPath) == .orderedAscending
        }
    }

    static func parseAuth(_ data: Data) -> AuthSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty
        else { return nil }
        return AuthSnapshot(
            accessToken: accessToken,
            accountID: (tokens["account_id"] as? String) ?? ""
        )
    }

    static func settingsDetail(entry: Entry, hasCredential: Bool, appStore: Bool) -> String {
        if hasCredential { return entry.normalizedPath }
        if appStore {
            return "\(entry.normalizedPath) — add this profile folder below, then run Codex with CODEX_HOME set to sign in."
        }
        return "\(entry.normalizedPath) — run Codex with CODEX_HOME=\(entry.normalizedPath) and sign in."
    }

    private static func profileDirectoryName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Codex" : name
    }

    private static func prefers(_ lhs: Entry, over rhs: Entry) -> Bool {
        if lhs.preferenceRank != rhs.preferenceRank { return lhs.preferenceRank > rhs.preferenceRank }
        if lhs.source != rhs.source { return lhs.source > rhs.source }
        if lhs.normalizedPath == defaultNormalizedPath { return true }
        if rhs.normalizedPath == defaultNormalizedPath { return false }
        return false
    }

    private static func tokenFingerprint(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizePOSIXPath(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var stack: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            if component == "." || component.isEmpty { continue }
            if component == ".." {
                if !stack.isEmpty, stack.last != ".." { stack.removeLast() }
                else if !isAbsolute { stack.append("..") }
                continue
            }
            stack.append(String(component))
        }
        let joined = stack.joined(separator: "/")
        return isAbsolute ? "/" + joined : joined
    }
}

/// Pure parsers for discovering CODEX_HOME from running Codex CLI processes.
enum CodexCredential {
    static func codexPIDs(in processList: String) -> [Int32] {
        processList.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let split = line.firstIndex(where: \Character.isWhitespace),
                  let pid = Int32(line[..<split])
            else { return nil }
            let command = line[split...].trimmingCharacters(in: .whitespaces).lowercased()
            guard looksLikeCodex(command) else { return nil }
            return pid
        }
    }

    static func home(inProcessEnvironment environment: String) -> String? {
        let prefix = "CODEX_HOME="
        return environment.split(whereSeparator: \Character.isWhitespace)
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
            .map { CodexProfile.normalizedPath($0) }
    }

    private static func looksLikeCodex(_ command: String) -> Bool {
        if command.contains("@openai/codex") { return true }
        if command.contains("/codex ") || command.hasSuffix("/codex") { return true }
        if command == "codex" || command.hasPrefix("codex ") { return true }
        return false
    }
}
