import Darwin
import Foundation

/// Reads credentials already stored on the machine by the provider CLIs:
///   - Claude Code: macOS Keychain item "Claude Code-credentials"
///   - Codex:       ~/.codex/auth.json
///
/// Nothing is written back to those stores and no token is ever logged. This is
/// the same requests the two CLIs make for themselves.
enum Fetcher {
    static let keychainService = "Claude Code-credentials"
    static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let codexAuthPath = ("~/.codex/auth.json" as NSString).expandingTildeInPath
    static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/codex/usage")!
    static let openRouterUsageURL = URL(string: "https://openrouter.ai/api/v1/key")!
    static let codexUserAgent = "codex_cli_rs/0.56.0 (Mac OS 26.4.0; arm64) Terminal"

    static let timeout: TimeInterval = 20

    /// The providers this app knows how to poll, in display order. Named so the
    /// store can schedule each one on its own cadence.
    static let providerNames = ["Claude", "Codex", "OpenRouter"]

    /// Fetch every named provider, concurrently. A provider left out is one the
    /// caller has decided is not due yet.
    static func fetch(names: [String], openRouterMonthlyBudget: Double?) async -> [Provider] {
        await withTaskGroup(of: Provider.self) { group in
            for name in names {
                group.addTask {
                    await fetch(name, openRouterMonthlyBudget: openRouterMonthlyBudget)
                }
            }
            var providers: [Provider] = []
            for await provider in group { providers.append(provider) }
            return providers
        }
    }

    static func fetch(_ name: String, openRouterMonthlyBudget: Double?) async -> Provider {
        switch name {
        case "Claude": return await fetchClaude()
        case "Codex": return await fetchCodex()
        case "OpenRouter": return await fetchOpenRouter(monthlyBudget: openRouterMonthlyBudget)
        default: return Provider(name: name)
        }
    }

    // ----------------------------------------------------------------- //
    // Claude Code
    // ----------------------------------------------------------------- //

    static func fetchClaude() async -> Provider {
        var provider = Provider(name: "Claude")

        guard let blob = keychainSecret(service: keychainService) else {
            provider.error = "keychain unavailable"
            return provider
        }
        let oauth = (json(blob)?["claudeAiOauth"] as? [String: Any]) ?? [:]
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            provider.error = "not logged in"
            return provider
        }
        provider.loggedIn = true
        provider.plan = oauth["subscriptionType"] as? String

        let data: [String: Any]
        do {
            data = try await getJSONRetrying(claudeUsageURL, headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
            ])
        } catch let error as HTTPStatus {
            provider.error = note(for: error.code, refreshWith: "claude")
            provider.staleToken = error.code == 401
            return provider
        } catch {
            provider.error = "unreachable — \(error.localizedDescription.prefix(60))"
            provider.unreachable = true
            return provider
        }

        provider.windows = claudeWindows(data)
        provider.ok = !provider.windows.isEmpty
        if !provider.ok { provider.error = "no limit data" }
        return provider
    }

    /// Turn Claude's current structured `limits` list into ordinary windows.
    /// Model names and future groups come from the response rather than a list
    /// in the app. The two legacy blocks fill any base rows omitted by an older
    /// or partially rolled-out response.
    static func claudeWindows(_ data: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        var baseGroups = Set<String>()
        var seen = Set<String>()

        for limit in (data["limits"] as? [[String: Any]]) ?? [] {
            guard let percent = (limit["percent"] as? NSNumber)?.doubleValue,
                  percent.isFinite,
                  let rawGroup = (limit["group"] as? String) ?? (limit["kind"] as? String)
            else { continue }

            let group = rawGroup.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !group.isEmpty else { continue }
            let descriptor = claudeGroup(group)
            let model = claudeModelName(limit["scope"])
            let unique = group + "\u{1}" + (model?.lowercased() ?? "")
            guard seen.insert(unique).inserted else { continue }
            if model == nil { baseGroups.insert(group) }

            windows.append(UsageWindow(
                label: descriptor.label + (model.map { " (\($0))" } ?? ""),
                percent: percent,
                resetsAt: epoch(fromISO: limit["resets_at"] as? String),
                windowSeconds: descriptor.seconds,
                model: model
            ))
        }

        // These fields are still present today and keep the app compatible
        // with older responses. They are only fallbacks, never duplicate rows.
        for (key, group, label, length) in [
            ("five_hour", "session", "5h", 5 * 3600),
            ("seven_day", "weekly", "week", 7 * 86400),
        ] where !baseGroups.contains(group) {
            guard let block = data[key] as? [String: Any],
                  let percent = (block["utilization"] as? NSNumber)?.doubleValue,
                  percent.isFinite
            else { continue }
            windows.append(UsageWindow(
                label: label,
                percent: percent,
                resetsAt: epoch(fromISO: block["resets_at"] as? String),
                windowSeconds: length
            ))
        }

        // Shortest first, with an overall row immediately before its scoped
        // peers. Swift's sort is not stable, so retain response order as the
        // final tie-breaker.
        return windows.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.windowSeconds ?? Int.max, lhs.element.model == nil ? 0 : 1, lhs.offset)
            let right = (rhs.element.windowSeconds ?? Int.max, rhs.element.model == nil ? 0 : 1, rhs.offset)
            return left < right
        }.map(\.element)
    }

    private static func claudeGroup(_ group: String) -> (label: String, seconds: Int?) {
        switch group {
        case "session": return ("5h", 5 * 3600)
        case "daily": return ("day", 86_400)
        case "weekly": return ("week", 7 * 86_400)
        case "monthly": return ("month", nil)
        case "yearly", "annual": return ("year", nil)
        default:
            return (group.replacingOccurrences(of: "_", with: " "), nil)
        }
    }

    private static func claudeModelName(_ rawScope: Any?) -> String? {
        guard let scope = rawScope as? [String: Any],
              let model = scope["model"] as? [String: Any]
        else { return nil }
        let raw = (model["display_name"] as? String) ?? (model["id"] as? String)
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }

    // ----------------------------------------------------------------- //
    // Codex
    // ----------------------------------------------------------------- //

    static func fetchCodex() async -> Provider {
        var provider = Provider(name: "Codex")

        guard let raw = FileManager.default.contents(atPath: codexAuthPath),
              let tokens = json(raw)?["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty
        else {
            provider.error = "not logged in"
            return provider
        }
        provider.loggedIn = true

        let headers = [
            "Authorization": "Bearer \(token)",
            "chatgpt-account-id": (tokens["account_id"] as? String) ?? "",
            "originator": "codex_cli_rs",
            "User-Agent": codexUserAgent,
            "Accept": "application/json",
        ]

        let data: [String: Any]
        do {
            // The edge in front of chatgpt.com occasionally answers 403 to an
            // otherwise valid request; the retry inside covers that.
            data = try await getJSONRetrying(codexUsageURL, headers: headers)
        } catch let error as HTTPStatus {
            provider.error = note(for: error.code, refreshWith: "codex")
            provider.staleToken = error.code == 401
            return provider
        } catch {
            provider.error = "unreachable — \(error.localizedDescription.prefix(60))"
            provider.unreachable = true
            return provider
        }

        provider.plan = data["plan_type"] as? String
        provider.windows += codexWindows(data["rate_limit"])
        provider.windows += codexAdditionalWindows(data["additional_rate_limits"])

        provider.ok = !provider.windows.isEmpty
        if !provider.ok { provider.error = "no limit data" }
        return provider
    }

    /// Turn one Codex rate_limit block into rows, shortest window first.
    /// Parse every named model bucket Codex sends. Unknown names are kept in
    /// structured metadata while the final name segment keeps labels compact.
    static func codexAdditionalWindows(_ raw: Any?) -> [UsageWindow] {
        guard let limits = raw as? [[String: Any]] else { return [] }
        return limits.flatMap { extra -> [UsageWindow] in
            guard let rawName = extra["limit_name"] as? String else { return [] }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return [] }
            return codexWindows(extra["rate_limit"], model: name)
        }
    }

    private static func codexWindows(_ limits: Any?, model: String? = nil) -> [UsageWindow] {
        guard let limits = limits as? [String: Any] else { return [] }
        var out: [UsageWindow] = []
        for key in ["primary_window", "secondary_window"] {
            guard let block = limits[key] as? [String: Any],
                  let percent = (block["used_percent"] as? NSNumber)?.doubleValue,
                  percent.isFinite
            else { continue }
            let length = (block["limit_window_seconds"] as? NSNumber)?.intValue
            let baseLabel = windowLabel(length)
            let label = model.map {
                "\(baseLabel) (\(ScopedModelLimit.displayName(provider: "Codex", model: $0)))"
            } ?? baseLabel
            out.append(UsageWindow(
                label: label,
                percent: percent,
                resetsAt: (block["reset_at"] as? NSNumber)?.intValue,
                windowSeconds: length,
                model: model
            ))
        }
        return out.sorted { ($0.windowSeconds ?? 0) < ($1.windowSeconds ?? 0) }
    }

    // ----------------------------------------------------------------- //
    // OpenRouter
    // ----------------------------------------------------------------- //

    static func fetchOpenRouter(monthlyBudget: Double?) async -> Provider {
        var provider = Provider(name: "OpenRouter")
        let candidates = openRouterCandidates()
        guard !candidates.isEmpty else {
            provider.error = OpenRouterBudget.notConnectedMessage
            return provider
        }
        provider.loggedIn = true

        var response: [String: Any]?
        for candidate in candidates {
            provider.credentialSource = candidate.source
            do {
                response = try await getJSONRetrying(openRouterUsageURL, headers: [
                    "Authorization": "Bearer \(candidate.key)",
                    "Accept": "application/json",
                    "User-Agent": "Tokens-on-Track",
                ])
                break
            } catch let error as HTTPStatus where error.code == 401 && !candidate.authoritative {
                // A stale automatically-discovered credential should not mask a
                // later live one, particularly with several Conductor agents.
                continue
            } catch let error as HTTPStatus {
                provider.error = openRouterNote(for: error.code, manual: candidate.authoritative)
                return provider
            } catch {
                provider.error = "unreachable — \(error.localizedDescription.prefix(60))"
                provider.unreachable = true
                return provider
            }
        }

        guard let data = response?["data"] as? [String: Any] else {
            provider.error = "stored key was rejected"
            return provider
        }

        // A response without the spend counters cannot be turned into a reading.
        // Defaulting them to zero would draw a healthy 0% out of a malformed
        // payload, so the absence is an error rather than a value.
        guard let daily = (data["usage_daily"] as? NSNumber)?.doubleValue,
              let monthly = (data["usage_monthly"] as? NSNumber)?.doubleValue
        else {
            provider.error = "no spend data"
            return provider
        }

        guard let budget = monthlyBudget, budget.isFinite, budget > 0 else {
            provider.windows = OpenRouterBudget.unbudgetedWindows(
                dailySpend: daily,
                monthlySpend: monthly
            )
            provider.error = OpenRouterBudget.missingBudgetMessage
            return provider
        }

        provider.plan = OpenRouterBudget.plan(budget)
        provider.windows = OpenRouterBudget.windows(
            dailySpend: daily,
            monthlySpend: monthly,
            monthlyBudget: budget
        )
        provider.ok = true
        return provider
    }

    private static func openRouterCandidates() -> [OpenRouterCredential.Candidate] {
        var candidates: [OpenRouterCredential.Candidate] = []
        if let key = OpenRouterKeychain.read() {
            candidates.append(.init(key: key, source: .keychain, authoritative: true))
        }
        if let raw = FileManager.default.contents(atPath: OpenRouterCredential.openCodeAuthPath),
           let key = OpenRouterCredential.key(inOpenCodeAuth: raw) {
            candidates.append(.init(key: key, source: .openCode, authoritative: false))
        }
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty {
            candidates.append(.init(key: key, source: .environment, authoritative: false))
        }
        candidates += conductorOpenRouterKeys().map {
            .init(key: $0, source: .conductor, authoritative: false)
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.key).inserted }
    }

    /// Conductor injects provider keys into its managed OpenCode child rather
    /// than OpenCode's normal auth file. There is no public credential API, so
    /// this same-user process lookup is intentionally a last, transient resort.
    private static func conductorOpenRouterKeys() -> [String] {
        guard let raw = runProcess(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,command="],
            timeout: 5
        ), let list = String(data: raw, encoding: .utf8)
        else { return [] }

        return OpenRouterCredential.conductorPIDs(in: list).compactMap { pid in
            guard let raw = runProcess(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["eww", "-p", String(pid), "-o", "command="],
                timeout: 5
            ), let environment = String(data: raw, encoding: .utf8)
            else { return nil }
            return OpenRouterCredential.key(inProcessEnvironment: environment)
        }
    }

    private static func openRouterNote(for code: Int, manual: Bool) -> String {
        switch code {
        case 401: return manual ? "key rejected — update it in Settings" : "stored key was rejected"
        case 429: return "rate limited — the reading will catch up"
        case 500...599: return "the service is not answering (http \(code))"
        default: return "http \(code)"
        }
    }

    // ----------------------------------------------------------------- //
    // plumbing
    // ----------------------------------------------------------------- //

    struct HTTPStatus: Error {
        let code: Int
    }

    /// When a provider's already-stored token expires, read from the local
    /// credential without a network call. Nil for a provider whose credential
    /// is a plain key with no expiry (OpenRouter) or cannot be read.
    ///
    /// The store uses this, not the API, to decide when a token-rejected
    /// provider is worth polling again: a 401 lasts until the CLI writes a new
    /// token, and the only local sign that has happened is the expiry moving.
    static func localTokenExpiry(_ name: String) -> Double? {
        switch name {
        case "Claude":
            guard let blob = keychainSecret(service: keychainService),
                  let oauth = json(blob)?["claudeAiOauth"] as? [String: Any],
                  let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue
            else { return nil }
            return ms / 1000  // stored in milliseconds
        case "Codex":
            guard let raw = FileManager.default.contents(atPath: codexAuthPath),
                  let tokens = json(raw)?["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String
            else { return nil }
            return jwtExpiry(token)
        default:
            return nil
        }
    }

    /// The `exp` claim (epoch seconds) from a JWT's payload, read without
    /// verifying the signature — enough to see whether the token has expired.
    static func jwtExpiry(_ token: String) -> Double? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let exp = (json(data)?["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        return exp
    }

    /// What to tell the reader about a failed poll.
    ///
    /// A 401 is not a sign-out: both CLIs keep a refresh token and mint a new
    /// access token when they next run, so the copy we read from their store
    /// simply goes stale — overnight, typically. Saying "expired, log in again"
    /// there was wrong as well as alarming; running the CLI once is the fix.
    static func note(for code: Int, refreshWith command: String) -> String {
        switch code {
        case 401: return "stored token went stale — run \(command) once"
        case 429: return "rate limited — the reading will catch up"
        case 500...599: return "the service is not answering (http \(code))"
        default: return "http \(code)"
        }
    }

    /// One retry, two seconds later, on a failure a second attempt can plausibly
    /// clear: a dropped connection, a 5xx, a throttle, or the 403 the chatgpt.com
    /// edge sometimes answers with. A 401 is not retried — the stored token will
    /// not have changed by then; only the CLI running again fixes that.
    private static func getJSONRetrying(
        _ url: URL,
        headers: [String: String]
    ) async throws -> [String: Any] {
        do {
            return try await getJSON(url, headers: headers)
        } catch {
            guard retryable(error) else { throw error }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return try await getJSON(url, headers: headers)
        }
    }

    private static func retryable(_ error: Error) -> Bool {
        guard let status = error as? HTTPStatus else { return true }
        return status.code == 403 || status.code == 429 || status.code >= 500
    }

    private static func getJSON(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw HTTPStatus(code: status)
        }
        return json(data) ?? [:]
    }

    private static func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Shelled out rather than done through SecItemCopyMatching, which keeps
    /// the app out of the keychain-entitlement business and reuses the consent
    /// the item's ACL already grants `security`. macOS asks the first time.
    private static func keychainSecret(service: String) -> Data? {
        runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-generic-password", "-s", service, "-w"],
            timeout: 15
        )
    }

    /// Run a small helper process without allowing an unanswered system prompt
    /// to hold the provider refresh open forever.
    static func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> Data? {
        let task = Process()
        task.executableURL = executableURL
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }

        do {
            try task.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if task.isRunning {
                task.terminate()
            }
            if finished.wait(timeout: .now() + 1) == .timedOut, task.isRunning {
                Darwin.kill(task.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            return nil
        }

        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        return task.terminationStatus == 0 ? out : nil
    }

    private static func epoch(fromISO value: String?) -> Int? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return Int(date.timeIntervalSince1970) }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return Int(date.timeIntervalSince1970) }
        return nil
    }

    private static func windowLabel(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "limit" }
        if seconds >= 7 * 86400 { return "week" }
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        return "\(seconds / 3600)h"
    }
}
