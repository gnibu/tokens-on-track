import Foundation

/// Turns OpenRouter's dollar counters into the same finite windows every other
/// provider reports. OpenRouter measures these periods in UTC, so DST and the
/// Mac's current time zone must not change either boundary.
enum OpenRouterBudget {
    static let missingBudgetMessage = "please define a budget in Settings"
    /// No credential was found this poll at all. Named so the fetcher that sets
    /// it and the surfaces that tailor it cannot drift apart.
    static let notConnectedMessage = "not connected"

    static func windows(
        dailySpend: Double,
        monthlySpend: Double,
        monthlyBudget: Double,
        now: Date = Date()
    ) -> [UsageWindow] {
        guard monthlyBudget.isFinite, monthlyBudget > 0 else { return [] }

        guard let periods = periods(at: now) else { return [] }

        let dailyBudget = monthlyBudget / Double(periods.days)
        return [
            window(label: "day", spend: dailySpend, budget: dailyBudget, interval: periods.day),
            window(label: "month", spend: monthlySpend, budget: monthlyBudget, interval: periods.month),
        ]
    }

    /// Retain raw spend while the user has not chosen a budget. The provider
    /// remains non-ok, so these cache-only rows are not drawn or ranked.
    static func unbudgetedWindows(
        dailySpend: Double,
        monthlySpend: Double,
        now: Date = Date()
    ) -> [UsageWindow] {
        guard let periods = periods(at: now) else { return [] }
        return [
            rawWindow(label: "day", spend: dailySpend, interval: periods.day),
            rawWindow(label: "month", spend: monthlySpend, interval: periods.month),
        ]
    }

    static func plan(_ monthlyBudget: Double) -> String {
        "\(dollars(monthlyBudget))/mo"
    }

    /// Cost labels are scanning aids, not an invoice. Whole dollars drop the
    /// decimals, anything else keeps at most two — and a small spend is given
    /// just enough digits to stay visible rather than rounding to `$0`.
    static func dollars(_ value: Double) -> String {
        guard value.isFinite else { return "$0" }
        let magnitude = abs(value)
        let decimals: Int
        if magnitude == magnitude.rounded() {
            decimals = 0
        } else if magnitude >= 0.01 {
            decimals = 2
        } else {
            decimals = min(6, max(2, Int(ceil(-log10(magnitude))) + 1))
        }

        var number = String(format: "%.\(decimals)f", value)
        while number.contains("."), number.last == "0" { number.removeLast() }
        if number.last == "." { number.removeLast() }
        return "$\(number)"
    }

    static func detail(for window: UsageWindow) -> String? {
        guard let spent = window.spentUSD, let budget = window.budgetUSD else { return nil }
        return "\(dollars(spent)) / \(dollars(budget))"
    }

    private static func window(
        label: String,
        spend: Double,
        budget: Double,
        interval: DateInterval
    ) -> UsageWindow {
        UsageWindow(
            label: label,
            percent: max(0, spend) / budget * 100,
            resetsAt: Int(interval.end.timeIntervalSince1970),
            windowSeconds: Int(interval.duration),
            spentUSD: max(0, spend),
            budgetUSD: budget
        )
    }

    private static func rawWindow(label: String, spend: Double, interval: DateInterval) -> UsageWindow {
        UsageWindow(
            label: label,
            percent: 0,
            resetsAt: Int(interval.end.timeIntervalSince1970),
            windowSeconds: Int(interval.duration),
            spentUSD: max(0, spend)
        )
    }

    private static func periods(at now: Date) -> (day: DateInterval, month: DateInterval, days: Int)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let day = calendar.dateInterval(of: .day, for: now),
              let month = calendar.dateInterval(of: .month, for: now),
              let days = calendar.range(of: .day, in: .month, for: now)?.count
        else { return nil }
        return (day, month, days)
    }
}

/// Pure parsers used by the credential resolver. Keeping them here means tests
/// never have to touch the real OpenCode file or inspect a real process.
enum OpenRouterCredential {
    enum Source: String, Codable, Equatable {
        case keychain = "Saved in Keychain"
        case openCode = "OpenCode"
        case environment = "Environment"
        case conductor = "Conductor · while OpenCode runs"
        case cursorApp = "Cursor app"
    }

    struct Candidate: Equatable {
        let key: String
        let source: Source
        let authoritative: Bool
    }

    static let openCodeAuthPath = ("~/.local/share/opencode/auth.json" as NSString)
        .expandingTildeInPath

    static func reconnectMessage(for provider: Provider) -> String? {
        guard provider.kind == "openrouter",
              provider.error == OpenRouterBudget.notConnectedMessage,
              provider.credentialSource == .conductor
        else { return nil }
        return "no live key — add one in Settings to reconnect"
    }

    static func key(inOpenCodeAuth data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credential = root["openrouter"] as? [String: Any],
              let key = credential["key"] as? String,
              !key.isEmpty
        else { return nil }
        return key
    }

    static func conductorPIDs(in processList: String) -> [Int32] {
        processList.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let split = line.firstIndex(where: \Character.isWhitespace),
                  let pid = Int32(line[..<split])
            else { return nil }
            let command = line[split...].trimmingCharacters(in: .whitespaces)
            guard command.contains("/com.conductor.app/agent-binaries/acp-providers/opencode/"),
                  command.hasSuffix("/opencode acp")
            else { return nil }
            return pid
        }
    }

    static func key(inProcessEnvironment environment: String) -> String? {
        let prefix = "OPENROUTER_API_KEY="
        return environment.split(whereSeparator: \Character.isWhitespace)
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}
