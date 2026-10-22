import Foundation

/// `--mcp`: a local Model Context Protocol server over stdio, so an agent
/// running on this Mac can ask how much quota is left before it starts a task.
///
/// It only reads the cache the menu bar app writes. It never polls a provider
/// itself, so it adds no traffic, needs no credential and cannot trigger a
/// Keychain prompt — and the reading it reports is the one the card shows.
enum AgentServer {
    static let flag = "--mcp"
    static let serverName = "tokens-on-track"
    static let toolName = "get_usage"

    /// Newest first. An unknown version from the client gets the newest, which
    /// the client is then free to refuse.
    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// Reads newline-delimited JSON-RPC from stdin until the client hangs up.
    /// Nothing else may write to stdout: it is the protocol channel.
    static func run(cacheURL: URL, schedule: () -> WorkSchedule) -> Never {
        while let line = readLine(strippingNewline: true) {
            let reply = respond(
                to: line,
                load: { load(cacheURL) },
                schedule: schedule()
            )
            guard let reply else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
        exit(0)
    }

    static func load(_ url: URL) -> Report? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Report.self, from: data)
    }

    // ----------------------------------------------------------------- //

    /// One request in, at most one reply out. Notifications get none.
    static func respond(
        to line: String,
        load: () -> Report?,
        schedule: WorkSchedule = .disabled,
        now: Date = Date()
    ) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = message["method"] as? String
        else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        let result: [String: Any]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            result = [
                "protocolVersion": asked.flatMap { protocolVersions.contains($0) ? $0 : nil }
                    ?? protocolVersions[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": version],
                "instructions": instructions,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": [tool]]
        case "tools/call":
            guard params["name"] as? String == toolName else {
                return encode(["jsonrpc": "2.0", "id": id, "error": [
                    "code": -32602, "message": "Unknown tool: \(params["name"] ?? "none")",
                ]])
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let filter = (arguments["provider"] as? String)?
                .trimmingCharacters(in: .whitespaces)
            result = callResult(
                load(),
                provider: filter?.isEmpty == false ? filter : nil,
                schedule: schedule,
                now: now
            )
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": [
                "code": -32601, "message": "Method not found: \(method)",
            ]])
        }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    static let instructions = """
        Tokens on Track reports how much of each AI subscription quota and \
        spend budget (Claude, Codex, OpenCode Go, OpenRouter, Cursor) is used \
        on this Mac. Call \
        get_usage before starting a task that will spend quota, and again \
        between tasks.
        """

    private static let tool: [String: Any] = [
        "name": toolName,
        "title": "Quota usage",
        "description": """
            Latest quota reading for each AI provider on this Mac. Each window \
            reports used_percent (share spent), resets_at (when it returns to \
            0%) and target_percent (where usage would be if spent evenly over \
            the window). billing says what a window measures. "quota" is a \
            subscription allowance: what is left when it resets is lost, so \
            remaining_percent in a quota window that resets soon is free to \
            spend. "spend" is real money (spent_usd) against a budget the user \
            set (budget_usd): nothing is lost by leaving it unspent, so only \
            use it when the task needs that provider, and never treat a spend \
            window with status "no budget set" as having room. When a window \
            is out or nearly out, wait for resets_at before starting work on \
            that provider. Readings are taken by the menu bar app every few \
            minutes: check age_minutes and fresh. reset_credits counts free \
            full resets the user holds; only the user decides to spend one, so \
            when a provider is out and has usable_now credits, tell them \
            rather than assuming the quota will come back early.
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "provider": [
                    "type": "string",
                    "description": "Only this provider, by name or id, e.g. \"Claude\" or \"Codex\". Omit for all.",
                ],
            ],
        ],
        "annotations": ["readOnlyHint": true, "openWorldHint": false],
    ]

    // ----------------------------------------------------------------- //

    static func callResult(
        _ report: Report?,
        provider filter: String? = nil,
        schedule: WorkSchedule = .disabled,
        now: Date = Date()
    ) -> [String: Any] {
        guard let report else {
            return textResult(
                "No reading yet. Tokens on Track has to be running for usage to be measured.",
                isError: true
            )
        }
        var payload = usage(report, schedule: schedule, now: now)
        if let filter {
            let wanted = filter.lowercased()
            let providers = (payload["providers"] as? [[String: Any]] ?? []).filter { entry in
                [entry["id"], entry["name"], entry["kind"]]
                    .compactMap { ($0 as? String)?.lowercased() }
                    .contains { $0 == wanted || $0.hasPrefix(wanted + " ") }
            }
            guard !providers.isEmpty else {
                return textResult("No provider matching \"\(filter)\" is set up.", isError: true)
            }
            payload["providers"] = providers
        }
        return textResult(encode(payload, pretty: true) ?? "{}", isError: false)
    }

    /// The cache restated for a reader with no card to look at: dates spelled
    /// out, the pace target worked out, and windows that have reset since the
    /// reading flagged rather than reported as still spent.
    static func usage(
        _ report: Report,
        schedule: WorkSchedule = .disabled,
        now: Date = Date()
    ) -> [String: Any] {
        let timing = Pace.Timing(now: now, schedule: schedule)
        let age = now.timeIntervalSince1970 - Double(report.updatedAt)
        var payload: [String: Any] = [
            "updated_at": timestamp(report.updatedAt),
            "age_minutes": Int((age / 60).rounded()),
            "fresh": age <= Report.staleAfter,
            "providers": report.visibleProviders.map { provider(
                $0,
                timing: timing
            ) },
        ]
        if age > Report.staleAfter {
            payload["note"] = "This reading is old. Check that Tokens on Track is running and the Mac is awake."
        }
        return payload
    }

    private static func provider(_ provider: Provider, timing: Pace.Timing) -> [String: Any] {
        var entry: [String: Any] = [
            "id": provider.id,
            "kind": provider.kind,
            "name": provider.name,
            "ok": provider.ok,
            "windows": provider.windows.map { window($0, timing: timing) },
        ]
        if let plan = provider.plan { entry["plan"] = plan }
        if let error = provider.error { entry["error"] = error }
        if let credits = provider.resetCredits?.current(at: timing.now), credits.available > 0 {
            entry["reset_credits"] = ["available": credits.available, "usable_now": credits.usableNow]
        }
        if provider.stale {
            entry["stale"] = true
            if let measured = provider.measuredAt { entry["measured_at"] = timestamp(measured) }
        }
        return entry
    }

    private static func window(_ window: UsageWindow, timing: Pace.Timing) -> [String: Any] {
        // Dollars mean pay-as-you-go: unspent budget is money kept, not quota
        // thrown away at the reset, so an agent must not read it as free.
        let spend = window.spentUSD != nil || window.budgetUSD != nil
        var entry: [String: Any] = [
            "label": window.label,
            "billing": spend ? "spend" : "quota",
        ]
        if let model = window.model { entry["model"] = model }
        if let spent = window.spentUSD { entry["spent_usd"] = rounded(spent, places: 2) }
        if let budget = window.budgetUSD { entry["budget_usd"] = rounded(budget, places: 2) }

        // With no budget there is nothing to be a share of: the 0% the card
        // keeps for these rows is a placeholder, and quoted as 100% remaining
        // it would invite unlimited spending.
        if spend, window.budgetUSD == nil {
            entry["status"] = "no budget set"
            return entry
        }
        entry["used_percent"] = rounded(window.percent)
        entry["remaining_percent"] = rounded(max(0, 100 - window.percent))

        guard let resetsAt = window.resetsAt, resetsAt > 0 else {
            entry["status"] = "idle"
            return entry
        }
        let remaining = Double(resetsAt) - timing.now.timeIntervalSince1970
        entry["resets_at"] = timestamp(resetsAt)
        entry["resets_in_minutes"] = max(0, Int((remaining / 60).rounded()))
        guard remaining > 0 else {
            // The quota behind these numbers has been handed back. Saying
            // "94% used" for a window that is empty again would hold an agent
            // back for no reason.
            entry["status"] = "reset since this reading"
            return entry
        }
        if let target = Pace.target(window, timing: timing) {
            entry["target_percent"] = rounded(target.percent)
        }
        entry["status"] = status(window, timing: timing)
        return entry
    }

    /// The card's own words for a row, so an agent and the user describe the
    /// same window the same way.
    private static func status(_ window: UsageWindow, timing: Pace.Timing) -> String {
        if window.percent.rounded() >= 100 { return "out" }
        if window.percent >= 90 { return "nearly out" }
        switch Pace.severity(window, timing: timing).tier {
        case 2: return "well above target"
        case 1: return "above target"
        default: return "on target"
        }
    }

    // ----------------------------------------------------------------- //

    /// What Settings copies: enough for any coding agent to register the
    /// server and know what to do with it, whichever client it runs in.
    static func setupPrompt(executable: String) -> String {
        let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return """
            Tokens on Track exposes my AI quota usage (Claude, Codex, OpenCode Go, \
            OpenRouter, Cursor) as a local MCP server on this Mac.

            Register it as a stdio MCP server named "\(serverName)":
            - command: \(executable)
            - args: ["\(flag)"]

            Claude Code: claude mcp add --scope user \(serverName) -- \(quoted) \(flag)
            Codex: codex mcp add \(serverName) -- \(quoted) \(flag)

            Then call its \(toolName) tool before starting any task that will spend \
            quota, and again between tasks. Start the next task only while the \
            provider you are running on has quota left; when a window is out or \
            nearly out, wait until its resets_at time instead.
            """
    }

    // ----------------------------------------------------------------- //

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private static func textResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static func timestamp(_ epoch: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: Date(timeIntervalSince1970: Double(epoch)))
    }

    /// Decimal rather than Double: JSONSerialization prints a rounded Double
    /// at full precision, so 25.4 would reach the agent as 25.399999999999999.
    private static func rounded(_ value: Double, places: Int = 1) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.\(places)f", value))
    }

    private static func encode(_ object: [String: Any], pretty: Bool = false) -> String? {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
