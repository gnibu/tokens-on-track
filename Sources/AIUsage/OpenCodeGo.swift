import Foundation

/// OpenCode Go reports quota percentages itself, so unlike cost-backed
/// providers no local budget is needed to turn its response into windows.
enum OpenCodeGoUsage {
    static let notConnectedMessage = "not connected"

    /// Auto-discovered OpenCode credentials do not prove that the account has
    /// a Go subscription. Only actual Go usage makes those accounts visible;
    /// a key deliberately saved in Settings remains visible so its errors can
    /// be corrected there.
    static func shouldShowProvider(hasManualKey: Bool, hasUsage: Bool) -> Bool {
        hasManualKey || hasUsage
    }

    static func windows(from data: [String: Any]) -> [UsageWindow] {
        guard let usage = data["usage"] as? [String: Any] else { return [] }
        let descriptors: [(key: String, label: String, seconds: Int?)] = [
            ("rolling", "5h", 5 * 3600),
            ("weekly", "week", 7 * 86400),
            ("monthly", "month", nil),
        ]

        return descriptors.compactMap { descriptor in
            guard let raw = usage[descriptor.key] as? [String: Any],
                  let percent = (raw["percent"] as? NSNumber)?.doubleValue,
                  percent.isFinite,
                  let reset = date(fromISO: raw["resetsAt"] as? String)
            else { return nil }

            let seconds = descriptor.seconds ?? monthlyDuration(endingAt: reset)
            return UsageWindow(
                label: descriptor.label,
                percent: percent,
                resetsAt: Int(reset.timeIntervalSince1970),
                windowSeconds: seconds
            )
        }
    }

    private static func monthlyDuration(endingAt reset: Date) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(byAdding: .month, value: -1, to: reset) else { return nil }
        return Int(reset.timeIntervalSince(start))
    }

    private static func date(fromISO value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

/// Pure credential parsers. They deliberately select only an active API-key
/// record; OAuth entries and inactive accounts must never be mistaken for Go.
enum OpenCodeGoCredential {
    struct Candidate: Equatable {
        let key: String
        let source: OpenRouterCredential.Source
        let authoritative: Bool
    }

    static let dataDirectory = ("~/.local/share/opencode" as NSString).expandingTildeInPath
    static let accountPath = (dataDirectory as NSString).appendingPathComponent("account.json")
    static let legacyAuthPath = (dataDirectory as NSString).appendingPathComponent("auth.json")

    static func key(inLegacyAuth data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return apiKey(root["opencode-go"]) ?? apiKey(root["opencode"])
    }

    static func key(inAccountStore data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = root["accounts"] as? [String: Any],
              let active = root["active"] as? [String: Any]
        else { return nil }

        for service in ["opencode-go", "opencode"] {
            guard let accountID = active[service] as? String,
                  let account = accounts[accountID] as? [String: Any],
                  account["serviceID"] as? String == service,
                  let key = apiKey(account["credential"])
            else { continue }
            return key
        }
        return nil
    }

    static func key(inProcessEnvironment environment: String) -> String? {
        let fields = environment.split(whereSeparator: \Character.isWhitespace)
        for name in ["OPENCODE_GO_API_KEY", "OPENCODE_API_KEY"] {
            let prefix = name + "="
            if let field = fields.first(where: { $0.hasPrefix(prefix) }) {
                let value = String(field.dropFirst(prefix.count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func reconnectMessage(for provider: Provider) -> String? {
        guard provider.kind == "opencode-go",
              provider.error == OpenCodeGoUsage.notConnectedMessage,
              provider.credentialSource == .conductor
        else { return nil }
        return "no live key — add one in Settings to reconnect"
    }

    private static func apiKey(_ value: Any?) -> String? {
        guard let credential = value as? [String: Any],
              credential["type"] as? String == "api",
              let key = credential["key"] as? String,
              !key.isEmpty
        else { return nil }
        return key
    }
}
