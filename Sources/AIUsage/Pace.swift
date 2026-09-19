import SwiftUI

/// Pace maths and formatting, shared by the panel, the menu bar icon and the
/// notification rules. One implementation so that every surface judges a
/// window identically.
enum Pace {
    static let good = Color(red: 0.369, green: 0.788, blue: 0.541)   // #5ec98a
    static let warn = Color(red: 1.000, green: 0.706, blue: 0.329)   // #ffb454
    static let bad = Color(red: 1.000, green: 0.420, blue: 0.420)    // #ff6b6b

    /// The three shades a filled track is drawn in. The flat colour is what the
    /// menu bar and the ring use; the gradient is what gives the fill in a
    /// recessed groove its curvature.
    struct Palette {
        let base: Color
        let top: Color
        let bottom: Color

        var fill: LinearGradient {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
    }

    static let idleFill = LinearGradient(
        colors: [.white.opacity(0.5), .white.opacity(0.3)],
        startPoint: .top,
        endPoint: .bottom
    )

    struct Severity: Comparable {
        let tier: Int
        let percent: Double
        let pace: Double

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.percent != rhs.percent { return lhs.percent < rhs.percent }
            return lhs.pace < rhs.pace
        }
    }

    enum ClockBasis {
        case wallClock
        case workingHours

        var label: String {
            switch self {
            case .wallClock: return "wall clock"
            case .workingHours: return "working hours"
            }
        }
    }

    /// One instant and schedule shared by every pace decision made while a
    /// surface is rendered. This prevents a boundary crossing halfway through
    /// a render from giving the notch and its colour different answers.
    struct Timing {
        let now: Date
        let schedule: WorkSchedule
        let calendar: Calendar

        init(
            now: Date = Date(),
            schedule: WorkSchedule = .disabled,
            calendar: Calendar = .autoupdatingCurrent
        ) {
            self.now = now
            self.schedule = schedule
            self.calendar = calendar
        }
    }

    /// Where usage should be now, expressed as a share of the quota. The basis
    /// records which clock supplied that target.
    struct Target {
        let percent: Double
        let basis: ClockBasis
    }

    /// The even-spend target, 0-100. While the user is inside working hours,
    /// the full quota is spread over every scheduled second in the window.
    /// Outside them — or when the window contains none — wall time supplies the
    /// target instead.
    static func target(_ window: UsageWindow, timing: Timing = Timing()) -> Target? {
        guard let resetsAt = window.resetsAt, let length = window.windowSeconds, length > 0 else {
            return nil
        }
        let reset = Date(timeIntervalSince1970: Double(resetsAt))
        let start = reset.addingTimeInterval(-Double(length))

        if timing.schedule.isActive(at: timing.now, calendar: timing.calendar) {
            let whole = DateInterval(start: start, end: reset)
            let total = timing.schedule.scheduledSeconds(in: whole, calendar: timing.calendar)
            if total > 0 {
                let end = min(reset, max(start, timing.now))
                let passed = end > start
                    ? timing.schedule.scheduledSeconds(
                        in: DateInterval(start: start, end: end),
                        calendar: timing.calendar
                    )
                    : 0
                return Target(
                    percent: min(100, max(0, passed / total * 100)),
                    basis: .workingHours
                )
            }
        }

        let remaining = Double(resetsAt) - timing.now.timeIntervalSince1970
        let elapsed = Double(length) - remaining
        return Target(
            percent: min(100, max(0, elapsed / Double(length) * 100)),
            basis: .wallClock
        )
    }

    static func targetPercent(_ window: UsageWindow, timing: Timing = Timing()) -> Double? {
        target(window, timing: timing)?.percent
    }

    /// Share of the window that has to be gone before a pace ratio is quoted at
    /// all. Spending divided by a very small elapsed share swings wildly from
    /// one poll to the next, so early on the answer is "not yet" rather than a
    /// number that will look different in a minute.
    ///
    /// Two floors because the two uses can bear different amounts of noise. The
    /// severity tier picks the colour of a row and the window the menu bar
    /// speaks for, so it waits for the ratio to settle. A printed percentage is
    /// read once, next to the reset time that explains why it is early, and
    /// holding it back to match the colour left freshly reset windows with
    /// nothing to say for hours.
    static let severityFloor: Double = 5
    static let displayFloor: Double = 1

    /// How far ahead of an even burn the window is. 1.0 is exactly on pace.
    /// Nil before the window has run long enough for the ratio to mean anything.
    static func ratio(
        _ window: UsageWindow,
        floor: Double = severityFloor,
        timing: Timing = Timing()
    ) -> Double? {
        guard let target = targetPercent(window, timing: timing), target >= floor else { return nil }
        return window.percent / target
    }

    /// The same reading as a percentage, which is how the summary states it:
    /// spending measured against the even-burn mark on the track rather than
    /// against the whole budget. 100 sits exactly on the mark, 150 is half
    /// again past it. Nil while the mark is still too early to mean anything.
    static func paceIndex(
        _ window: UsageWindow,
        floor: Double = severityFloor,
        timing: Timing = Timing()
    ) -> Double? {
        ratio(window, floor: floor, timing: timing).map { $0 * 100 }
    }

    /// Which number the percentages quote. The gauges are unaffected either
    /// way: a ring or a track always fills to the share of the budget spent,
    /// because that is the only one of the two readings with an end to it.
    enum PercentMode: String, CaseIterable {
        /// How much of the budget is gone. 100% is the budget spent.
        case budget
        /// How that spending compares with an even burn. 100% sits exactly on
        /// the target mark, which is the white notch on the tracks. The legacy
        /// raw value preserves existing saved preferences.
        case target = "pace"
    }

    /// A pace reading early in a window is a small number over a smaller one
    /// and runs to four figures. Past this the exact value says nothing the cap
    /// does not, and in the menu bar it would widen the item a digit at a time.
    static let paceCeiling: Double = 999

    /// What a column shows for a window that has no stable target comparison
    /// yet. Not the budget
    /// number: the two readings share one column, so a budget percentage
    /// printed under a target heading is indistinguishable from a target
    /// comparison and silently means something else. The track beside it still
    /// fills to the budget, and the reset time beside that says why the window
    /// is early.
    static let noReading = "—"

    /// The percentage a surface prints, and whether there was one to print.
    struct Reading {
        let text: String
        /// False when the window is too young for a stable target comparison
        /// and target mode was asked for. The surfaces dim it, so an absent
        /// reading is not mistaken for a very small one.
        let hasValue: Bool
    }

    static func reading(
        _ window: UsageWindow,
        mode: PercentMode,
        timing: Timing = Timing()
    ) -> Reading {
        guard mode == .target else {
            return Reading(text: "\(Int(window.percent.rounded()))%", hasValue: true)
        }
        guard let index = paceIndex(window, floor: displayFloor, timing: timing) else {
            return Reading(text: noReading, hasValue: false)
        }
        return Reading(text: "\(Int(min(paceCeiling, index).rounded()))%", hasValue: true)
    }

    /// What a target percentage is measured against. Said once per tooltip, not
    /// once per window in it.
    static let targetExplainer = "100% of target means usage is exactly where it should be now."

    /// The line behind the menu bar item. A bare "142%" cannot say which of the
    /// two readings it is, so the tooltip states both and how far into the
    /// window they were taken.
    ///
    /// `explains` appends `targetExplainer`; leave it off when several of these
    /// are being stacked and the caller adds the sentence itself.
    static func tooltip(
        source: String?,
        window: UsageWindow,
        explains: Bool = true,
        showsCost: Bool = true,
        timing: Timing = Timing()
    ) -> String {
        let dollars = showsCost
            ? OpenRouterBudget.detail(for: window).map { " · \($0)" } ?? ""
            : ""
        let spent = "\(Int(window.percent.rounded()))% of the budget spent\(dollars)"
        let lead = source.map { "\($0) — " } ?? ""
        let target = target(window, timing: timing)

        guard let index = paceIndex(window, timing: timing), let target else {
            let basis = target.map { basisSentence($0, timing: timing) } ?? ""
            return "\(lead)\(spent). Too early in the window to compare with the target.\(basis)"
        }
        let reading = """
            \(lead)\(Int(min(paceCeiling, index).rounded()))% of target · \(spent), \
            \(basisReading(target, timing: timing)).
            """
        return explains ? "\(reading) \(targetExplainer)" : reading
    }

    /// Green while spending is at or under the even-burn pace, orange when
    /// running ahead of it, red when far ahead or nearly exhausted.
    static func color(_ window: UsageWindow, timing: Timing = Timing()) -> Color {
        switch severityTier(window, timing: timing) {
        case 2: return bad
        case 1: return warn
        default: return good
        }
    }

    static func palette(_ window: UsageWindow, timing: Timing = Timing()) -> Palette {
        switch severityTier(window, timing: timing) {
        case 2:
            return Palette(
                base: bad,
                top: Color(red: 1.000, green: 0.604, blue: 0.604),   // #ff9a9a
                bottom: Color(red: 0.902, green: 0.310, blue: 0.310)  // #e64f4f
            )
        case 1:
            return Palette(
                base: warn,
                top: Color(red: 1.000, green: 0.816, blue: 0.541),   // #ffd08a
                bottom: Color(red: 0.941, green: 0.604, blue: 0.188)  // #f09a30
            )
        default:
            return Palette(
                base: good,
                top: Color(red: 0.549, green: 0.910, blue: 0.678),   // #8ce8ad
                bottom: Color(red: 0.294, green: 0.722, blue: 0.478)  // #4bb87a
            )
        }
    }

    private static func severityTier(_ window: UsageWindow, timing: Timing) -> Int {
        if window.percent >= 90 { return 2 }
        guard let ratio = ratio(window, timing: timing) else {
            // Too early in the window for a pace ratio to mean anything.
            if window.percent >= 60 { return 2 }
            if window.percent >= 30 { return 1 }
            return 0
        }
        if ratio > 1.5 { return 2 }
        if ratio > 1.0 { return 1 }
        return 0
    }

    /// Ranking used to pick which window the menu bar should speak for: the one
    /// in the most trouble. Colour tier wins first, then usage and pace break
    /// ties without collapsing high percentages into the same capped score.
    static func severity(_ window: UsageWindow, timing: Timing = Timing()) -> Severity {
        Severity(
            tier: severityTier(window, timing: timing),
            percent: window.percent,
            pace: ratio(window, timing: timing) ?? 0
        )
    }

    /// One sentence answering "am I fine?", so neither surface makes the reader
    /// parse four rows to find out.
    struct Verdict {
        /// Title of the dropdown's summary pill, over `detail`.
        let headline: String
        /// The card's one line, which has to carry the number as well.
        let line: String
        let detail: String
        let percent: Double
        /// Even-spend target, for the ring's white target mark.
        let target: Double?
        /// "Anthropic 5h" — the row the whole summary is speaking about, named
        /// so that the ring is not an anonymous number.
        let source: String?
        /// Identifies that row in the list below, so it can be marked there too.
        let rowKey: String?
        let color: Color
        /// True once the reading is bad enough that the whole card goes red.
        let hot: Bool
    }

    /// `mode` decides which reading the summary sentence quotes, so that it
    /// agrees with the column of numbers underneath it. That agreement is what
    /// labels the column: a heading over it was tried and read as clutter, and
    /// this sentence is already on screen saying "70% of target" in words.
    static func verdict(
        _ report: Report?,
        mode: PercentMode = .budget,
        timing: Timing = Timing()
    ) -> Verdict {
        guard let worst = report?.busiestWindows(limit: 1, timing: timing).first else {
            return Verdict(
                headline: "No reading yet",
                line: "No reading yet",
                detail: "nothing fetched",
                percent: 0,
                target: nil,
                source: nil,
                rowKey: nil,
                color: good,
                hot: false
            )
        }

        let window = worst.window
        let tier = severityTier(window, timing: timing)
        let exhausted = tier == 2 && window.percent >= 90
        let spentWord = spentPhrase(window.percent)
        let reading = readingPhrase(window, mode: mode, timing: timing)
        let basis = target(window, timing: timing)
        let basisSuffix = timing.schedule.enabled
            ? basis.map { " · \($0.basis.label)" } ?? " · wall clock"
            : ""

        let short: String
        switch tier {
        case 2: short = "Well above target"
        case 1: short = "Above target"
        default: short = "On target"
        }

        // "5h window out — 100% of the 5h window" says the same thing twice, so
        // once the budget reading is what the first half already stated, it goes.
        let spentLine = spentWord == "out" && mode == .budget
            ? "\(window.label) window out\(basisSuffix)"
            : "\(window.label) window \(spentWord) — \(reading)\(basisSuffix)"

        return Verdict(
            headline: exhausted ? "\(window.label) window \(spentWord)" : (tier == 0 ? "On target everywhere" : short),
            line: exhausted ? spentLine : "\(short) — \(reading)\(basisSuffix)",
            detail: "worst: \(worst.provider.name) \(window.label), \(reading)\(basisSuffix)",
            percent: window.percent,
            target: basis?.percent,
            source: "\(worst.provider.name) \(window.label)",
            rowKey: Report.rowKey(provider: worst.provider, window: window),
            color: color(window, timing: timing),
            hot: tier == 2
        )
    }

    /// The number the summary quotes, named. Whichever reading the rows below
    /// are showing, said in words — "70% of target" or "36% of the week" — so the
    /// bare percentages in the column inherit the noun from the sentence above
    /// them.
    ///
    /// Target mode still falls back to the budget here rather than to a dash. A
    /// column of numbers has to be read against one heading and cannot carry
    /// a substitution, but a sentence names whatever it is quoting.
    private static func readingPhrase(
        _ window: UsageWindow,
        mode: PercentMode,
        timing: Timing
    ) -> String {
        if mode == .target, let index = paceIndex(window, floor: displayFloor, timing: timing) {
            return "\(Int(min(paceCeiling, index).rounded()))% of target"
        }
        return "\(Int(window.percent.rounded()))% of \(phrase(window.label))"
    }

    /// "nearly out" against a bar reading 100% is a hedge the number contradicts.
    /// Rounded, not exact, so the word agrees with the percentage on screen.
    private static func spentPhrase(_ percent: Double) -> String {
        Int(percent.rounded()) >= 100 ? "out" : "nearly out"
    }

    /// Window labels are a mix of periods and durations: "the week" reads, but
    /// "the 5h" does not and needs the noun spelling out.
    private static func phrase(_ label: String) -> String {
        let period = ["week", "day", "month", "hour", "session"].contains { label.contains($0) }
        return period ? "the \(label)" : "the \(label) window"
    }

    /// The word beside a provider's name: how that provider on its own is doing.
    /// Nil when the reading is missing or carried over from an earlier poll:
    /// what happened is said once, in the notice above the list, and a verdict
    /// read off stale numbers would be stated with more confidence than it has.
    static func note(
        _ provider: Provider,
        timing: Timing = Timing()
    ) -> (text: String, color: Color)? {
        guard provider.ok, !provider.stale else { return nil }
        guard let worst = provider.windows.max(by: {
            severity($0, timing: timing) < severity($1, timing: timing)
        })
        else { return ("no windows", .white.opacity(0.45)) }

        if worst.percent < 5 { return ("barely touched", .white.opacity(0.45)) }
        switch severityTier(worst, timing: timing) {
        case 2 where worst.percent >= 90: return (spentPhrase(worst.percent), bad)
        case 2: return ("well above target", bad)
        case 1: return ("above target", warn)
        default: return ("on target", good)
        }
    }

    private static func basisReading(_ target: Target, timing: Timing) -> String {
        switch target.basis {
        case .workingHours:
            return "\(Int(target.percent.rounded()))% target based on working hours"
        case .wallClock where timing.schedule.enabled:
            return "\(Int(target.percent.rounded()))% target based on wall clock"
        case .wallClock:
            return "\(Int(target.percent.rounded()))% target"
        }
    }

    private static func basisSentence(_ target: Target, timing: Timing) -> String {
        guard timing.schedule.enabled else { return "" }
        switch target.basis {
        case .workingHours:
            return " The target uses working hours."
        case .wallClock where !timing.schedule.isValid:
            return " The target uses wall clock because the working-hours range is invalid."
        case .wallClock where !timing.schedule.isActive(at: timing.now, calendar: timing.calendar):
            return " The target uses wall clock outside working hours."
        case .wallClock:
            return " The target uses wall clock because this window contains no working hours."
        }
    }

    /// Bare wall clock, for saying when a carried-over reading was taken.
    static func clockLabel(_ epoch: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(epoch))
        let clock = DateFormatter()
        // A carried reading can now be up to a day old, so a bare HH:mm would be
        // ambiguous across midnight — name the day once it is not today's.
        clock.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE HH:mm"
        return clock.string(from: date)
    }

    /// Absolute reset time. Today is clock-only; inside the next seven days is
    /// weekday plus hour; beyond that, date only — the hour is noise that far off.
    static func resetLabel(_ epoch: Int?, now: Date = Date()) -> String {
        // An untouched window has no reset instant yet; the clock starts on use.
        guard let epoch, epoch > 0 else { return "idle" }
        let at = Date(timeIntervalSince1970: Double(epoch))
        if at <= now { return "now" }

        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        let calendar = Calendar.current
        if calendar.isDate(at, inSameDayAs: now) { return clock.string(from: at) }

        if at.timeIntervalSince(now) >= 7 * 86400 {
            let long = DateFormatter()
            long.dateFormat = "MM/dd"
            return long.string(from: at)
        }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEE HH:mm"
        return weekday.string(from: at)
    }
}
