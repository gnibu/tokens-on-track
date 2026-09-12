import Foundation

/// What gets written to the cache. The snake_case keys are deliberate: the
/// file is meant to stay readable by anything that wants to `cat | jq` it.

struct UsageWindow: Codable, Identifiable, Equatable {
    var label: String
    var percent: Double
    var resetsAt: Int?
    var windowSeconds: Int?

    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label
        case percent
        case resetsAt = "resets_at"
        case windowSeconds = "window_seconds"
    }

    init(label: String, percent: Double, resetsAt: Int? = nil, windowSeconds: Int? = nil) {
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? box.decode(String.self, forKey: .label)) ?? "limit"
        percent = (try? box.decode(Double.self, forKey: .percent)) ?? 0
        resetsAt = try? box.decodeIfPresent(Int.self, forKey: .resetsAt)
        windowSeconds = try? box.decodeIfPresent(Int.self, forKey: .windowSeconds)
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
    }

    init(name: String) {
        self.name = name
    }

    /// Whether the rows are worth drawing. A stale reading that is all but zero
    /// carries no information — it says "we last saw nothing", which reads as an
    /// empty, broken block — so the card shows a "no recent reading" line for it
    /// instead. A stale *non-zero* reading (say 94%) is still worth carrying.
    var hasVisibleReading: Bool {
        guard !windows.isEmpty else { return false }
        if stale, windows.allSatisfy({ $0.percent < 1 }) { return false }
        return true
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
    /// Only for a while: past `carryLimit` the quota windows have moved on and
    /// the old numbers would be a lie rather than an approximation.
    static let carryLimit: TimeInterval = 3 * 3600

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
    /// user has hidden, with the Codex "spark" model buckets dropped on request.
    /// One filter for the card, the dropdown, the menu bar and the alerts, so a
    /// hidden provider is hidden everywhere at once.
    func displayProviders(hiding hiddenNames: Set<String> = [], hideSpark: Bool = false) -> [Provider] {
        visibleProviders.compactMap { provider in
            guard !hiddenNames.contains(provider.name) else { return nil }
            guard hideSpark else { return provider }
            var trimmed = provider
            trimmed.windows = provider.windows.filter { !$0.label.lowercased().hasPrefix("spark") }
            return trimmed
        }
    }

    /// The report as the reading surfaces see it, with hidden providers and
    /// spark rows already removed. Everything that ranks or summarises windows —
    /// the header verdict, the card's hot glow, the menu bar — runs off this, so
    /// none of them can speak for a row that is not drawn.
    func displaying(hiding hiddenNames: Set<String> = [], hideSpark: Bool = false) -> Report {
        var copy = self
        copy.providers = displayProviders(hiding: hiddenNames, hideSpark: hideSpark)
        return copy
    }

    /// True when any provider reports a "spark" bucket, so the settings pane can
    /// offer to hide them only when there is something to hide.
    var hasSparkWindows: Bool {
        providers.contains { $0.windows.contains { $0.label.lowercased().hasPrefix("spark") } }
    }

    /// A reading older than this is shown as stale rather than silently trusted.
    var isStale: Bool {
        Date().timeIntervalSince1970 - Double(updatedAt) > 2700
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
        provider.name + "\u{1}" + window.label
    }

    private static func key(_ pair: (provider: Provider, window: UsageWindow)) -> String {
        rowKey(provider: pair.provider, window: pair.window)
    }
}
