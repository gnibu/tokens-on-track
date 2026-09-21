import Foundation

/// Turns Cursor's billing-cycle usage into the same finite windows every other
/// provider reports. Personal accounts expose percentages for the current
/// cycle; team Admin keys expose dollar spend that is mapped through a budget.
enum CursorBudget {
    static let missingBudgetMessage = OpenRouterBudget.missingBudgetMessage
    static let notConnectedMessage = OpenRouterBudget.notConnectedMessage
    static let userKeyMessage = "this key cannot read usage — use a team Admin key, or remove it to use the Cursor app"

    static func plan(_ membership: String?) -> String? {
        guard let raw = membership?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        switch raw.lowercased() {
        case "pro_plus", "pro-plus", "proplus": return "PRO+"
        case "business": return "TEAMS"
        default: return raw.uppercased()
        }
    }

    static func plan(monthlyBudget: Double) -> String {
        OpenRouterBudget.plan(monthlyBudget)
    }

    static func detail(for window: UsageWindow) -> String? {
        OpenRouterBudget.detail(for: window)
    }

    /// Personal dashboard `usage-summary` (and the same fields on
    /// `get-current-period-usage`) already carry 0–100 percentages and the
    /// billing-cycle bounds. Auto/API rows are optional extras, hidden when
    /// they would only repeat a zero total.
    static func windows(fromSummary data: [String: Any]) -> [UsageWindow] {
        let start = date(data["billingCycleStart"])
        let end = date(data["billingCycleEnd"])
        let plan = individual(data, "plan")
        let onDemand = individual(data, "onDemand")

        let total = percent(plan?["totalPercentUsed"])
            ?? percent(fromUsed: number(plan?["used"]), limit: number(plan?["limit"]))
        guard let total, let start, let end, end > start else { return [] }

        let seconds = max(1, Int(end.timeIntervalSince(start)))
        let resetsAt = Int(end.timeIntervalSince1970)
        let (spent, budget) = dollars(fromAPI: number(plan?["used"]), limit: number(plan?["limit"]))
        var windows = [
            window(
                label: "month",
                percent: total,
                resetsAt: resetsAt,
                seconds: seconds,
                spent: spent,
                budget: budget
            )
        ]

        let auto = percent(plan?["autoPercentUsed"])
        let api = percent(plan?["apiPercentUsed"])
        if let auto, auto >= 0.5 {
            windows.append(window(
                label: "month (Auto)",
                percent: auto,
                resetsAt: resetsAt,
                seconds: seconds,
                model: "Auto"
            ))
        }
        if let api, api >= 0.5 {
            windows.append(window(
                label: "month (API)",
                percent: api,
                resetsAt: resetsAt,
                seconds: seconds,
                model: "API"
            ))
        }

        if bool(onDemand?["enabled"]),
           let used = number(onDemand?["used"]),
           let demandLimit = number(onDemand?["limit"]),
           demandLimit > 0
        {
            let (demandSpent, demandBudget) = dollars(fromAPI: used, limit: demandLimit)
            windows.append(window(
                label: "on-demand",
                percent: max(0, used) / demandLimit * 100,
                resetsAt: resetsAt,
                seconds: seconds,
                spent: demandSpent,
                budget: demandBudget,
                model: "On-demand"
            ))
        }
        return windows
    }

    /// A free account with no included quota. The Cursor app can leave a stale
    /// login beside a live Pro session; callers skip this and keep looking.
    static func isPlaceholderSummary(_ data: [String: Any]) -> Bool {
        let membership = (data["membershipType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let plan = individual(data, "plan")
        let used = number(plan?["used"]) ?? 0
        let limit = number(plan?["limit"]) ?? 0
        let unpaid = membership == nil || membership == "free"
        return unpaid && used < 1 && limit < 1
    }

    static func windows(
        monthlySpend: Double,
        monthlyBudget: Double,
        now: Date = Date()
    ) -> [UsageWindow] {
        OpenRouterBudget.windows(
            dailySpend: 0,
            monthlySpend: monthlySpend,
            monthlyBudget: monthlyBudget,
            now: now
        ).filter { $0.label == "month" }
    }

    static func unbudgetedWindows(monthlySpend: Double, now: Date = Date()) -> [UsageWindow] {
        OpenRouterBudget.unbudgetedWindows(
            dailySpend: 0,
            monthlySpend: monthlySpend,
            now: now
        ).filter { $0.label == "month" }
    }

    /// Dashboard spend is in cents when any value in the pair is a whole number
    /// of 1000 or more (`500` used / `2000` limit → $5 / $20). Smaller values
    /// are already dollars, so a $200 Ultra limit is not mistaken for $2.
    static func dollars(fromAPI value: Double?) -> Double? {
        dollars(fromAPI: value, limit: value).spent
    }

    static func dollars(fromAPI used: Double?, limit: Double?) -> (spent: Double?, budget: Double?) {
        let unit = [used, limit].compactMap { $0 }.max() ?? 0
        let cents = unit >= 1000 && unit == unit.rounded()
        func convert(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return cents ? value / 100 : value
        }
        return (convert(used), convert(limit))
    }

    static func dollars(fromCents cents: Double?) -> Double? {
        guard let cents, cents.isFinite, cents >= 0 else { return nil }
        return cents / 100
    }

    static func spend(fromTeamMembers members: [[String: Any]]) -> (spent: Double, limit: Double?)? {
        let rows = members.compactMap { number($0["overallSpendCents"]) ?? number($0["spendCents"]) }
        guard !rows.isEmpty else { return nil }
        let spent = rows.reduce(0, +) / 100
        let limits = members.compactMap {
            number($0["monthlyLimitDollars"]) ?? number($0["effectivePerUserLimitDollars"])
        }.filter { $0 > 0 }
        return (spent, limits.count == 1 ? limits[0] : nil)
    }

    private static func bool(_ raw: Any?) -> Bool {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return false
    }

    private static func window(
        label: String,
        percent: Double,
        resetsAt: Int,
        seconds: Int,
        spent: Double? = nil,
        budget: Double? = nil,
        model: String? = nil
    ) -> UsageWindow {
        let hasBudget = budget.map { $0 > 0 } ?? false
        return UsageWindow(
            label: label,
            percent: percent,
            resetsAt: resetsAt,
            windowSeconds: seconds,
            spentUSD: hasBudget ? spent : nil,
            budgetUSD: hasBudget ? budget : nil,
            model: model
        )
    }

    private static func individual(_ data: [String: Any], _ key: String) -> [String: Any]? {
        let root = data["individualUsage"] as? [String: Any]
        return (root?[key] as? [String: Any]) ?? (data[key] as? [String: Any])
    }

    private static func percent(_ raw: Any?) -> Double? {
        guard let value = number(raw), value.isFinite else { return nil }
        return max(0, value)
    }

    private static func percent(fromUsed used: Double?, limit: Double?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return max(0, used) / limit * 100
    }

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return nil
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let value = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

/// Pure parsers used by the credential resolver. Tests never have to touch the
/// real Cursor database, Keychain item, or a live process.
enum CursorCredential {
    static let accessTokenService = "cursor-access-token"
    static let conductorSettingsService = "com.conductor.app.production.settings"
    static let conductorAPIKeyAccount = "env:local:shared:CURSOR_API_KEY"
    static let stateDBPath = (
        "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb" as NSString
    ).expandingTildeInPath
    static let accessTokenKey = "cursorAuth/accessToken"

    struct Session: Equatable {
        let jwt: String
        let cookie: String
    }

    struct Candidate: Equatable {
        let secret: String
        let source: OpenRouterCredential.Source
        let authoritative: Bool
        var isAPIKey: Bool { CursorCredential.isAPIKey(secret) }
        var session: Session? { CursorCredential.session(from: secret) }
    }

    static func reconnectMessage(for provider: Provider) -> String? {
        guard provider.kind == "cursor",
              provider.error == CursorBudget.notConnectedMessage
        else { return nil }
        if provider.credentialSource == .cursorApp {
            return "Cursor is signed out — sign in, or add a key in Settings"
        }
        return "no live key — add one in Settings to reconnect"
    }

    static func isAPIKey(_ secret: String) -> Bool {
        secret.lowercased().hasPrefix("crsr_")
    }

    /// Accept a dashboard session token in any of the shapes the cookie, the
    /// local JWT, or a `sub::jwt` paste actually take.
    static func session(from secret: String) -> Session? {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAPIKey(trimmed) else { return nil }

        if let jwt = jwt(afterSeparator: "%3A%3A", in: trimmed)
            ?? jwt(afterSeparator: "::", in: trimmed)
        {
            return session(jwt: jwt, subject: jwtSubject(jwt))
        }
        guard looksLikeJWT(trimmed), let subject = jwtSubject(trimmed) else { return nil }
        return session(jwt: trimmed, subject: subject)
    }

    static func jwtSubject(_ token: String) -> String? {
        Fetcher.jwtPayload(token)?["sub"] as? String
    }

    static func key(inProcessEnvironment environment: String) -> String? {
        for prefix in ["CURSOR_API_KEY=", "CURSOR_SESSION_TOKEN="] {
            if let value = environment.split(whereSeparator: \Character.isWhitespace)
                .first(where: { $0.hasPrefix(prefix) })
                .map({ String($0.dropFirst(prefix.count)) }),
               !value.isEmpty
            {
                return value
            }
        }
        return nil
    }

    static func conductorPIDs(in processList: String) -> [Int32] {
        processList.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let split = line.firstIndex(where: \Character.isWhitespace),
                  let pid = Int32(line[..<split])
            else { return nil }
            let command = line[split...].trimmingCharacters(in: .whitespaces)
            guard command.contains("/com.conductor.app/"),
                  command.localizedCaseInsensitiveContains("cursor")
            else { return nil }
            return pid
        }
    }

    private static func jwt(afterSeparator separator: String, in secret: String) -> String? {
        guard let range = secret.range(of: separator) else { return nil }
        let jwt = String(secret[range.upperBound...])
        return looksLikeJWT(jwt) ? jwt : nil
    }

    private static func looksLikeJWT(_ token: String) -> Bool {
        token.split(separator: ".").count == 3
    }

    private static func session(jwt: String, subject: String?) -> Session? {
        guard looksLikeJWT(jwt) else { return nil }
        let identity = subject ?? jwtSubject(jwt) ?? ""
        let cookie = identity.isEmpty ? jwt : "\(identity)%3A%3A\(jwt)"
        return Session(jwt: jwt, cookie: cookie)
    }
}
