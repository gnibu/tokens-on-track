import Foundation

/// What gets written to the cache. The snake_case keys are deliberate: the
/// file is meant to stay readable by anything that wants to `cat | jq` it.

struct UsageWindow: Codable, Identifiable, Equatable {
    var label: String
    var percent: Double
    var resetsAt: Int?
    var windowSeconds: Int?
    /// Present only for cost-backed providers such as OpenRouter. Percentages
    /// remain the common currency used by ranking and pacing.
    var spentUSD: Double?
    var budgetUSD: Double?
    /// Display name supplied by a provider when this quota applies to one
    /// model. Kept separately from `label` so preferences never have to parse
    /// user-facing text to hide the row.
    var model: String?

    var id: String { model.map { $0 + "\u{1}" + label } ?? label }

    enum CodingKeys: String, CodingKey {
        case label
        case percent
        case resetsAt = "resets_at"
        case windowSeconds = "window_seconds"
        case spentUSD = "spent_usd"
        case budgetUSD = "budget_usd"
        case model
    }

    init(
        label: String,
        percent: Double,
        resetsAt: Int? = nil,
        windowSeconds: Int? = nil,
        spentUSD: Double? = nil,
        budgetUSD: Double? = nil,
        model: String? = nil
    ) {
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
        self.spentUSD = spentUSD
        self.budgetUSD = budgetUSD
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? box.decode(String.self, forKey: .label)) ?? "limit"
        percent = (try? box.decode(Double.self, forKey: .percent)) ?? 0
        resetsAt = try? box.decodeIfPresent(Int.self, forKey: .resetsAt)
        windowSeconds = try? box.decodeIfPresent(Int.self, forKey: .windowSeconds)
        spentUSD = try? box.decodeIfPresent(Double.self, forKey: .spentUSD)
        budgetUSD = try? box.decodeIfPresent(Double.self, forKey: .budgetUSD)
        model = try? box.decodeIfPresent(String.self, forKey: .model)
    }
}

/// One provider/model pair discovered in a structured quota response. Its
/// normalized key is persisted; the original names remain available to the UI.
struct ScopedModelLimit: Codable, Identifiable, Equatable {
    let provider: String
    let model: String

    var id: String { Self.key(provider: provider, model: model) }
    var displayName: String { Self.displayName(for: model) }

    static func key(provider: String, model: String) -> String {
        let providerPart = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelPart = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return providerPart + "\u{1}" + modelPart
    }

    static func displayName(for model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "-").last.map(String.init) ?? trimmed
    }
}

/// Durable catalog of model-specific limits seen on this Mac. Provider
/// responses may omit an inactive model on any given refresh, so discovery is
/// append-only and independent from whether that model is currently visible.
enum ModelLimitHistory {
    static func merging(
        existing: [ScopedModelLimit],
        discovered: [ScopedModelLimit]
    ) -> [ScopedModelLimit] {
        var result: [ScopedModelLimit] = []
        var seen = Set<String>()
        for limit in existing + discovered where seen.insert(limit.id).inserted {
            result.append(limit)
        }
        return result
    }

    static func seedingSpark(
        existing: [ScopedModelLimit],
        hadPreviousReading: Bool
    ) -> [ScopedModelLimit] {
        guard hadPreviousReading else { return existing }
        return merging(
            existing: existing,
            discovered: [
                ScopedModelLimit(provider: "Codex", model: ModelLimitMigration.codexSpark),
            ]
        )
    }
}

/// One-time bridge from the two Spark row switches shipped before all model
/// limits shared one setting. Only a fully hidden old model remains hidden;
/// a mixed state becomes shown because one model-level switch cannot express it.
enum ModelLimitMigration {
    static let codexSpark = "GPT-5.3-Codex-Spark"

    static func codexSparkVisibility(
        existing: Set<String>,
        hadPreviousReading: Bool,
        legacySessionHidden: Bool?,
        legacyWeekHidden: Bool?,
        legacyAllHidden: Bool?
    ) -> Set<String> {
        var result = existing
        let key = ScopedModelLimit.key(provider: "Codex", model: codexSpark)
        guard hadPreviousReading, !result.contains(key) else { return result }

        let bothRowsHidden = (legacySessionHidden ?? true) && (legacyWeekHidden ?? true)
        if legacyAllHidden == true || (legacyAllHidden == nil && bothRowsHidden) {
            result.insert(key)
        }
        return result
    }
}

struct Provider: Codable, Identifiable, Equatable {
    var name: String
    var ok: Bool = false
    var plan: String?
    var error: String?
    var windows: [UsageWindow] = []
    /// True when `windows` is the last reading that did land rather than one
    /// taken now: the poll failed and these numbers were carried over.
    var stale: Bool = false
    /// When those carried numbers were actually measured.
    var measuredAt: Int?
    /// True once the CLI's stored credentials were found. A provider that was
    /// never set up has nothing worth a row and no logo worth drawing, so it is
    /// hidden entirely rather than shown as an empty block.
    var loggedIn: Bool = false
    /// True when the last poll could not reach the provider at all — the
    /// offline case, as opposed to a token or key the provider itself rejected.
    /// Only this brings the retry down to a minute; the others cannot be fixed
    /// by asking again, and hammering the endpoint would be rude.
    var unreachable: Bool = false
    /// True when the last poll was refused with a 401: the stored access token
    /// has expired and only the CLI writing a new one will fix it. Re-polling
    /// the API meanwhile just earns another 401, so the store watches the
    /// token's local expiry and asks again only once a fresh one is minted.
    var staleToken: Bool = false
    /// Non-secret origin of the credential that produced this reading. It is
    /// shown in Settings and harmless in the cache.
    var credentialSource: OpenRouterCredential.Source?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case ok
        case plan
        case error
        case windows
        case stale
        case measuredAt = "measured_at"
        case loggedIn = "logged_in"
        case unreachable
        case staleToken = "stale_token"
        case credentialSource = "credential_source"
    }

    init(name: String) {
        self.name = name
    }

    /// Whether the rows are worth drawing. A stale reading that is all but zero
    /// carries no information — it says "we last saw nothing", which reads as an
    /// empty, broken block — so the card shows a "no recent reading" line for it
    /// instead. A stale *non-zero* reading (say 94%) is still worth carrying.
    var hasVisibleReading: Bool {
        guard ok, !windows.isEmpty else { return false }
        if stale, windows.allSatisfy({ $0.percent < 1 }) { return false }
        return true
    }

    /// The warning remains useful, but an empty provider block underneath it
    /// only repeats that setup is incomplete.
    var needsOpenRouterBudget: Bool {
        name == "OpenRouter" && error == OpenRouterBudget.missingBudgetMessage
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? box.decode(String.self, forKey: .name)) ?? "?"
        ok = (try? box.decode(Bool.self, forKey: .ok)) ?? false
        plan = try? box.decodeIfPresent(String.self, forKey: .plan)
        error = try? box.decodeIfPresent(String.self, forKey: .error)
        windows = (try? box.decode([UsageWindow].self, forKey: .windows)) ?? []
        stale = (try? box.decode(Bool.self, forKey: .stale)) ?? false
        measuredAt = try? box.decodeIfPresent(Int.self, forKey: .measuredAt)
        // A cache from before this flag existed: an ok reading was necessarily
        // logged in, so fall back to that rather than hiding it until the first
        // refresh lands.
        loggedIn = (try? box.decode(Bool.self, forKey: .loggedIn)) ?? ok
        unreachable = (try? box.decode(Bool.self, forKey: .unreachable)) ?? false
        staleToken = (try? box.decode(Bool.self, forKey: .staleToken)) ?? false
        credentialSource = try? box.decodeIfPresent(OpenRouterCredential.Source.self, forKey: .credentialSource)
    }
}

struct Report: Codable, Equatable {
    var updatedAt: Int
    var updatedLabel: String
    var providers: [Provider]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case updatedLabel = "updated_label"
        case providers
    }

    init(providers: [Provider], date: Date = Date()) {
        updatedAt = Int(date.timeIntervalSince1970)
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        updatedLabel = clock.string(from: date)
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = (try? box.decode(Int.self, forKey: .updatedAt)) ?? 0
        updatedLabel = (try? box.decode(String.self, forKey: .updatedLabel)) ?? "--:--"
        providers = (try? box.decode([Provider].self, forKey: .providers)) ?? []
    }

    /// A provider that failed this round keeps the numbers it last reported,
    /// marked stale, instead of the card blanking out. Most failures are one
    /// bad poll — an access token the CLI has not refreshed yet, or the API not
    /// answering — and the previous reading stays the best answer to "am I
    /// fine?" for the few minutes until the next try.
    ///
    /// Only for a while: past `carryLimit` even a window with no reset of its
    /// own is too old to stand in for a live reading. A day covers the common
    /// case — Claude's access token going stale overnight — so the last good
    /// numbers survive until the CLI runs again in the morning. Per-window
    /// expiry is handled separately below: a window past its reset is dropped
    /// regardless, so this cap only holds back readings nothing else retired.
    static let carryLimit: TimeInterval = 24 * 3600

    func carryingOver(from previous: Report?, now: Date = Date()) -> Report {
        guard let previous else { return self }
        var merged = self
        merged.providers = providers.map { provider in
            guard !provider.ok,
                  let old = previous.providers.first(where: { $0.name == provider.name }),
                  old.ok
            else { return provider }

            let measured = (old.stale ? old.measuredAt : previous.updatedAt) ?? previous.updatedAt
            guard now.timeIntervalSince1970 - Double(measured) < Self.carryLimit else { return provider }

            // A window that has passed its reset is a fresh window we know
            // nothing about, not a spent one: carrying "94%, nearly out" across
            // the boundary would keep the menu bar red through the first hours
            // of a quota that is actually empty.
            let live = old.windows.filter { window in
                guard let resetsAt = window.resetsAt, resetsAt > 0 else { return true }
                return Double(resetsAt) > now.timeIntervalSince1970
            }
            guard !live.isEmpty else { return provider }

            // A provider we had a reading for recently has "been active": keep it
            // on screen, dimmed and marked stale, even if its credentials cannot
            // be read this round. Only a provider we have never seen a reading for
            // — never set up — is hidden outright.
            var carried = provider
            carried.ok = true
            carried.stale = true
            carried.loggedIn = true
            carried.plan = provider.plan ?? old.plan
            // Remember where the carried reading's credential came from, even
            // though this poll found none. It lets a surface say "the last key
            // was a Conductor one — run OpenRouter there again" rather than a
            // bare "not connected".
            carried.credentialSource = provider.credentialSource ?? old.credentialSource
            carried.windows = live
            carried.measuredAt = measured
            return carried
        }
        return merged
    }

    /// The providers worth drawing: the ones whose CLI is actually set up. A
    /// provider that was never logged in has no logo and no bars to show, only
    /// an empty block that reads as broken, so it is left out of every surface.
    var visibleProviders: [Provider] {
        providers.filter(\.loggedIn)
    }

    /// What the reading surfaces actually draw: set-up providers, minus any the
    /// user has hidden, with any unwanted model-specific buckets dropped.
    /// One filter for the card, the dropdown, the menu bar and the alerts, so a
    /// hidden provider is hidden everywhere at once.
    func displayProviders(
        hiding hiddenNames: Set<String> = [],
        hidingModels hiddenModels: Set<String> = []
    ) -> [Provider] {
        visibleProviders.compactMap { provider in
            guard !hiddenNames.contains(provider.name) else { return nil }
            guard !hiddenModels.isEmpty else { return provider }
            var trimmed = provider
            trimmed.windows = provider.windows.filter {
                guard let model = $0.model else { return true }
                let key = ScopedModelLimit.key(provider: provider.name, model: model)
                return !hiddenModels.contains(key)
            }
            return trimmed
        }
    }

    /// The report as the reading surfaces see it, with hidden providers and
    /// model rows already removed. Everything that ranks or summarises windows —
    /// the header verdict, the card's hot glow, the menu bar — runs off this, so
    /// none of them can speak for a row that is not drawn.
    func displaying(
        hiding hiddenNames: Set<String> = [],
        hidingModels hiddenModels: Set<String> = []
    ) -> Report {
        var copy = self
        copy.providers = displayProviders(
            hiding: hiddenNames,
            hidingModels: hiddenModels
        )
        return copy
    }

    /// Rebuild cost-backed percentages from cached dollars when the local
    /// budget changes. No provider call is required, and preference edits do
    /// not masquerade as a freshly measured report.
    func rebudgetingOpenRouter(monthlyBudget: Double?, now: Date = Date()) -> Report {
        var copy = self
        guard let index = copy.providers.firstIndex(where: { $0.name == "OpenRouter" }) else {
            return copy
        }
        var provider = copy.providers[index]
        let daily = provider.windows.first(where: { $0.label == "day" })?.spentUSD
        let monthly = provider.windows.first(where: { $0.label == "month" })?.spentUSD
        guard let daily, let monthly else { return copy }

        guard let budget = monthlyBudget, budget.isFinite, budget > 0 else {
            provider.ok = false
            provider.stale = false
            provider.plan = nil
            provider.error = OpenRouterBudget.missingBudgetMessage
            provider.windows = OpenRouterBudget.unbudgetedWindows(
                dailySpend: daily,
                monthlySpend: monthly,
                now: now
            )
            copy.providers[index] = provider
            return copy
        }

        provider.plan = OpenRouterBudget.plan(budget)
        provider.windows = OpenRouterBudget.windows(
            dailySpend: daily,
            monthlySpend: monthly,
            monthlyBudget: budget,
            now: now
        )
        if provider.error == OpenRouterBudget.missingBudgetMessage {
            provider.ok = true
            provider.error = nil
        }
        copy.providers[index] = provider
        return copy
    }

    /// Model-specific quota switches currently worth offering in Settings.
    /// Preserve provider/window order and collapse several windows for one
    /// model into a single switch.
    var scopedModelLimits: [ScopedModelLimit] {
        var seen = Set<String>()
        var result: [ScopedModelLimit] = []
        for provider in providers {
            for window in provider.windows {
                guard let model = window.model?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !model.isEmpty
                else { continue }
                let limit = ScopedModelLimit(provider: provider.name, model: model)
                if seen.insert(limit.id).inserted { result.append(limit) }
            }
        }
        return result
    }

    /// A reading older than this is shown as stale rather than silently trusted.
    var isStale: Bool {
        Date().timeIntervalSince1970 - Double(updatedAt) > 2700
    }

    /// True when a poll has run and nothing landed: providers are set up, but
    /// not one of them produced a window and there was no recent reading to
    /// carry over. A poll that failed is not the end of the story — the timer
    /// asks again — so the surfaces use this to promise the automatic retry
    /// instead of leaving an empty card looking final. A provider that was
    /// never set up is not a retry, and neither is OpenRouter waiting on a
    /// budget: no poll will fix either one.
    var hasNoReading: Bool {
        let set = providers.filter { $0.loggedIn && !$0.needsOpenRouterBudget }
        guard !set.isEmpty else { return false }
        return !set.contains { $0.ok && !$0.windows.isEmpty }
    }

    /// True when the last poll could not reach anyone: every provider that can
    /// be polled is unreachable. One blocked host among reachable ones is not
    /// this — the others landed and must keep the user's interval instead of
    /// being polled fifteen times more often. A stale token, a rejected key or
    /// a missing budget is not this either. Used to poll again in a minute
    /// rather than wait out the user's interval for the card to fill back in.
    var needsFastRetry: Bool {
        let set = providers.filter { $0.loggedIn && !$0.needsOpenRouterBudget }
        guard !set.isEmpty else { return false }
        return set.allSatisfy(\.unreachable)
    }

    /// How long ago the reading landed, in the card's second line. The absolute
    /// clock beside it says *when*; this says whether it is worth trusting.
    func ageLabel(now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince1970 - Double(updatedAt)
        if updatedAt == 0 { return "never" }
        if seconds < 90 { return "just now" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int((seconds / 3600).rounded())
        if hours < 24 { return "\(hours) hr ago" }
        return "\(Int((seconds / 86400).rounded())) d ago"
    }

    /// The windows worth watching, worst first.
    ///
    /// `fairShare` gives every provider a slot before any provider gets a
    /// second one. That keeps a quiet Codex on screen next to a loud Claude,
    /// at the cost of bumping a window that really is busier — so it is a
    /// choice, not the rule.
    func busiestWindows(
        limit: Int,
        fairShare: Bool = false,
        timing: Pace.Timing = Pace.Timing()
    ) -> [(provider: Provider, window: UsageWindow)] {
        guard limit > 0 else { return [] }
        let ranked = providers
            .filter(\.ok)
            .flatMap { provider in provider.windows.map { (provider: provider, window: $0) } }
            .sorted {
                Pace.severity($0.window, timing: timing) > Pace.severity($1.window, timing: timing)
            }

        guard fairShare else { return Array(ranked.prefix(limit)) }

        var claimed = Set<String>()
        let leading = ranked.filter { claimed.insert($0.provider.name).inserted }
        let taken = Set(leading.map(Self.key))
        return Array((leading + ranked.filter { !taken.contains(Self.key($0)) }).prefix(limit))
    }

    /// Provider and window labels are each unique within a reading, but only
    /// together do they identify one row.
    static func rowKey(provider: Provider, window: UsageWindow) -> String {
        provider.name + "\u{1}" + window.id
    }

    private static func key(_ pair: (provider: Provider, window: UsageWindow)) -> String {
        rowKey(provider: pair.provider, window: pair.window)
    }
}
