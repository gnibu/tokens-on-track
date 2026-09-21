import CryptoKit
import Foundation

/// Claude Code profile paths, Keychain service names, and catalog merging.
/// Credentials are read-only; Tokens on Track never writes Claude's Keychain items.
/// Values the fetcher needs from user settings without importing Preferences in tests.
struct ClaudePollingContext {
    var configuredPaths: [String] = []
    var rememberedPaths: Set<String> = []
    var ignoredPaths: Set<String> = []
    /// Filled by the store after a process scan; never spawn `ps` while building targets.
    var discoveredPaths: [String] = []
    var label: (String) -> String? = { _ in nil }
    var remember: (String) -> Void = { _ in }
}

enum ClaudeProfile {
    static let defaultRelativePath = "~/.claude"
    static let defaultKeychainService = "Claude Code-credentials"
    static let keychainPrefix = "Claude Code-credentials-"

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
        var keychainService: String
        var source: Source
        /// Higher wins when two entries share an access token.
        var preferenceRank: Int

        var id: String { keychainService }
    }

    struct OAuthSnapshot: Equatable {
        let accessToken: String
        let subscriptionType: String?
        let expiresAtMs: Double?
    }

    // ----------------------------------------------------------------- //

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

    static func keychainService(for normalizedPath: String) -> String {
        if normalizedPath == defaultNormalizedPath {
            return defaultKeychainService
        }
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        let prefix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return keychainPrefix + prefix
    }

    static func pathHashPrefix8(_ normalizedPath: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func defaultLabel(
        subscriptionType: String?,
        customLabel: String?,
        profilePath: String
    ) -> String {
        if let custom = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        guard let raw = subscriptionType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return profilePath == defaultNormalizedPath ? "Claude Personal" : profileDirectoryName(profilePath)
        }
        let sub = raw.lowercased()
        if sub.contains("team") { return "Claude Team" }
        if sub.contains("enterprise") { return "Claude Enterprise" }
        if sub.contains("max") || sub.contains("pro") || sub.contains("personal") {
            return "Claude Personal"
        }
        return profileDirectoryName(profilePath)
    }

    /// Merge default, configured, remembered, and discovered profiles. Removed
    /// paths stay out until the user adds them again explicitly.
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
            let service = keychainService(for: path)
            let entry = Entry(
                normalizedPath: path,
                keychainService: service,
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
        for path in configuredPaths {
            insert(path: path, source: .configured, rank: 1)
        }
        for path in rememberedPaths {
            insert(path: path, source: .configured, rank: 0)
        }
        for path in discoveredPaths {
            insert(path: path, source: .discovered, rank: 0)
        }

        return byPath.values.sorted { lhs, rhs in
            if lhs.normalizedPath == defaultNormalizedPath { return true }
            if rhs.normalizedPath == defaultNormalizedPath { return false }
            return lhs.normalizedPath.localizedStandardCompare(rhs.normalizedPath) == .orderedAscending
        }
    }

    /// Drop profiles that decode to the same access token. The higher
    /// `preferenceRank` wins; ties favour the default profile path.
    static func collapseDuplicateTokens(
        _ entries: [Entry],
        oauth: (String) -> OAuthSnapshot?
    ) -> [Entry] {
        var seen = [String: Entry]()
        var result: [Entry] = []
        for entry in entries {
            guard let snapshot = oauth(entry.keychainService) else { continue }
            let hash = tokenFingerprint(snapshot.accessToken)
            if let existing = seen[hash] {
                if prefers(entry, over: existing) {
                    seen[hash] = entry
                    result.removeAll { $0.keychainService == existing.keychainService }
                    result.append(entry)
                }
            } else {
                seen[hash] = entry
                result.append(entry)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.normalizedPath == defaultNormalizedPath { return true }
            if rhs.normalizedPath == defaultNormalizedPath { return false }
            return lhs.normalizedPath.localizedStandardCompare(rhs.normalizedPath) == .orderedAscending
        }
    }

    static func parseOAuth(from keychainBlob: Data) -> OAuthSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: keychainBlob) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        let subscription = oauth["subscriptionType"] as? String
        let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue
        return OAuthSnapshot(accessToken: token, subscriptionType: subscription, expiresAtMs: expires)
    }

    static func settingsDetail(
        entry: Entry,
        hasCredential: Bool,
        appStore: Bool
    ) -> String {
        if hasCredential { return entry.normalizedPath }
        if appStore {
            return "\(entry.normalizedPath) — add this profile folder below, then run Claude Code with CLAUDE_CONFIG_DIR set to sign in."
        }
        return "\(entry.normalizedPath) — run Claude Code with CLAUDE_CONFIG_DIR=\(entry.normalizedPath) and sign in."
    }

    // ----------------------------------------------------------------- //

    private static func profileDirectoryName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Claude" : name
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
                if !stack.isEmpty, stack.last != ".." {
                    stack.removeLast()
                } else if !isAbsolute {
                    stack.append("..")
                }
                continue
            }
            stack.append(String(component))
        }
        let joined = stack.joined(separator: "/")
        return isAbsolute ? "/" + joined : joined
    }
}

// --------------------------------------------------------------------- //

/// Pure parsers for Claude Code process discovery. Tests use these without
/// spawning real processes.
enum ClaudeCredential {
    static func claudePIDs(in processList: String) -> [Int32] {
        processList.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let split = line.firstIndex(where: \Character.isWhitespace),
                  let pid = Int32(line[..<split])
            else { return nil }
            let command = line[split...].trimmingCharacters(in: .whitespaces).lowercased()
            guard looksLikeClaudeCode(command) else { return nil }
            return pid
        }
    }

    static func configDir(inProcessEnvironment environment: String) -> String? {
        let prefix = "CLAUDE_CONFIG_DIR="
        return environment.split(whereSeparator: \Character.isWhitespace)
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
            .map { ClaudeProfile.normalizedPath($0) }
    }

    private static func looksLikeClaudeCode(_ command: String) -> Bool {
        if command.contains("claude-code") { return true }
        if command.contains("@anthropic-ai/claude-code") { return true }
        if command.contains("/claude ") || command.hasSuffix("/claude") { return true }
        if command.contains("/.claude/local/") { return true }
        return false
    }
}
