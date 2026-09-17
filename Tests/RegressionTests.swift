import AppKit
import Darwin
import Foundation

@main
enum RegressionTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let wallTiming = Pace.Timing(now: now)

    static func main() {
        testRedHighUsageWindowOutranksGreenWindow()
        testColorTierOutranksPercentage()
        testProcessOutputIsReturned()
        testProcessIsTerminatedAtTimeout()
        testOpenRouterBuildsBudgetWindows()
        testOpenRouterUsesLeapMonth()
        testOpenRouterWindowMetadataRoundTrips()
        testOpenRouterRebudgetsCachedSpend()
        testOpenCodeOpenRouterCredentialIsParsed()
        testConductorCredentialEnvironmentIsParsed()
        testOpenRouterDollarFormatting()
        testBusiestWindowsIgnoreWhoOwnsThem()
        testFairShareGivesEveryProviderASlot()
        testFairShareSpendsSpareSlotsOnTheNextWorstWindow()
        testShippedIconsParse()
        testArcFlagsAreReadOneCharacterWide()
        testWindowInitialSkipsDigits()
        testMenuBarItemIsNeverZeroWidth()
        testStrayArgumentAfterCloseIsRejected()
        testNotLoggedInProviderIsHidden()
        testHiddenProviderAndSparkWindowsAreFiltered()
        testRecentlyActiveProviderStaysVisibleWhenUnreadable()
        testFailedPollKeepsTheLastReading()
        testCarriedReadingIsDroppedOnceItIsOld()
        testCarriedWindowIsDroppedOnceItHasReset()
        testHasNoReadingOnlyWhenAPollLandedNothing()
        testOfflinePollAsksAgainSooner()
        testBudgetModeQuotesTheBudget()
        testTargetModeQuotesThePaceIndex()
        testTargetModeSaysNothingWhileTheWindowIsYoung()
        testPaceIsPrintedSoonerThanItIsColoured()
        testPaceReadingIsCapped()
        testTooltipStatesBothReadings()
        testVerdictUsesTargetLanguage()
        testFullWindowSaysOutOnce()
        testWorkingHoursRedistributeShortWindow()
        testWorkingHoursSwitchBackToWallClock()
        testWorkingHoursSpreadAWeekAcrossAllSelectedHours()
        testWorkingHoursZeroOverlapFallsBackToWallClock()
        testWorkingHoursDisabledUsesWallClock()
        testOvernightScheduleBelongsToItsStartDay()
        testScheduleRespectsDST()
        testScheduleUsesTheProvidedTimeZone()
        testScheduleBoundaryIsExact()
        print("All regression tests passed")
    }

    private static func testRedHighUsageWindowOutranksGreenWindow() {
        let green = window(percent: 80, elapsedPercent: 80)
        let red = window(percent: 95, elapsedPercent: 95)
        check(
            Pace.severity(green, timing: wallTiming) < Pace.severity(red, timing: wallTiming),
            "95% red window must outrank 80% green window"
        )
    }

    private static func testColorTierOutranksPercentage() {
        let green = window(percent: 80, elapsedPercent: 80)
        let red = window(percent: 50, elapsedPercent: 25)
        check(
            Pace.severity(green, timing: wallTiming) < Pace.severity(red, timing: wallTiming),
            "red pace window must outrank higher-percentage green window"
        )
    }

    private static func testProcessOutputIsReturned() {
        let output = Fetcher.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["hello"],
            timeout: 1
        )
        check(
            output.flatMap { String(data: $0, encoding: .utf8) } == "hello",
            "successful helper process must return stdout"
        )
    }

    private static func testProcessIsTerminatedAtTimeout() {
        let startedAt = Date()
        let output = Fetcher.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: 0.1
        )
        check(output == nil, "timed-out helper process must return nil")
        check(
            Date().timeIntervalSince(startedAt) < 2,
            "timed-out helper process must be terminated promptly"
        )
    }

    // ----------------------------------------------------------------- //
    // OpenRouter spend becomes ordinary quota windows.
    // ----------------------------------------------------------------- //

    private static func testOpenRouterBuildsBudgetWindows() {
        let calendar = utcCalendar()
        let instant = date(2026, 9, 16, 12, 0, calendar: calendar)
        let windows = OpenRouterBudget.windows(
            dailySpend: 0.105751342,
            monthlySpend: 0.105751342,
            monthlyBudget: 20,
            now: instant
        )

        check(windows.map(\.label) == ["day", "month"], "OpenRouter must expose day and month")
        check(close(windows[0].budgetUSD, 20.0 / 30.0), "September daily allowance must be 1/30 of budget")
        check(close(windows[0].spentUSD, 0.105751342), "daily spend must stay exact")
        check(close(windows[0].percent, 0.105751342 / (20.0 / 30.0) * 100), "daily percent must use the derived allowance")
        check(close(windows[1].percent, 0.105751342 / 20 * 100), "monthly percent must use the monthly budget")
        check(
            windows[0].resetsAt == Int(date(2026, 9, 17, 0, 0, calendar: calendar).timeIntervalSince1970),
            "the day must reset at the next UTC midnight"
        )
        check(windows[0].windowSeconds == 86_400, "a UTC day must be 86400 seconds")
        check(
            windows[1].resetsAt == Int(date(2026, 10, 1, 0, 0, calendar: calendar).timeIntervalSince1970),
            "the month must reset at the next UTC month"
        )
        check(windows[1].windowSeconds == 30 * 86_400, "September must be a 30-day window")
    }

    private static func testOpenRouterUsesLeapMonth() {
        let calendar = utcCalendar()
        let instant = date(2028, 2, 10, 12, 0, calendar: calendar)
        let windows = OpenRouterBudget.windows(
            dailySpend: 1,
            monthlySpend: 5,
            monthlyBudget: 29,
            now: instant
        )
        check(close(windows[0].budgetUSD, 1), "a leap-February daily allowance must use 29 days")
        check(windows[1].windowSeconds == 29 * 86_400, "February 2028 must contain 29 UTC days")
    }

    private static func testOpenRouterWindowMetadataRoundTrips() {
        let original = UsageWindow(
            label: "day",
            percent: 25,
            resetsAt: 123,
            windowSeconds: 86_400,
            spentUSD: 0.25,
            budgetUSD: 1
        )
        guard let encoded = try? JSONEncoder().encode(original),
              let restored = try? JSONDecoder().decode(UsageWindow.self, from: encoded)
        else {
            check(false, "an OpenRouter window must encode and decode")
            return
        }
        check(restored == original, "USD metadata must survive the usage cache")

        let old = Data(#"{"label":"week","percent":42}"#.utf8)
        let legacy = try? JSONDecoder().decode(UsageWindow.self, from: old)
        check(legacy?.spentUSD == nil && legacy?.budgetUSD == nil, "old caches must decode without USD metadata")
    }

    private static func testOpenRouterRebudgetsCachedSpend() {
        let calendar = utcCalendar()
        let instant = date(2026, 9, 16, 12, 0, calendar: calendar)
        var openRouter = Provider(name: "OpenRouter")
        openRouter.loggedIn = true
        openRouter.credentialSource = .openCode
        openRouter.error = OpenRouterBudget.missingBudgetMessage
        openRouter.windows = OpenRouterBudget.unbudgetedWindows(
            dailySpend: 0.20,
            monthlySpend: 2,
            now: instant
        )
        check(openRouter.needsOpenRouterBudget, "an unbudgeted OpenRouter reading must suppress its empty block")
        let report = Report(providers: [openRouter], date: instant)
        let rebudgeted = report.rebudgetingOpenRouter(monthlyBudget: 40, now: instant)
        let provider = rebudgeted.providers[0]

        check(provider.ok && provider.error == nil, "setting a budget must activate a validated reading")
        check(!provider.needsOpenRouterBudget, "a budgeted OpenRouter reading must show its provider block")
        check(provider.plan == "$40/mo", "the budget must become the plan badge")
        check(close(provider.windows[0].budgetUSD, 40.0 / 30.0), "the daily allowance must be recomputed")
        check(close(provider.windows[1].percent, 5), "$2 of $40 must be 5%")
    }

    private static func testOpenCodeOpenRouterCredentialIsParsed() {
        let fixture = Data(#"{"openrouter":{"type":"api","key":"sk-or-test-open-code"},"lmstudio":{"type":"api","key":"local"}}"#.utf8)
        check(
            OpenRouterCredential.key(inOpenCodeAuth: fixture) == "sk-or-test-open-code",
            "the standard OpenCode OpenRouter credential must be detected"
        )
        check(OpenRouterCredential.key(inOpenCodeAuth: Data("{}".utf8)) == nil, "a missing credential stays missing")
    }

    private static func testConductorCredentialEnvironmentIsParsed() {
        let processList = """
          123 /usr/bin/something
          456 /Users/me/Library/Application Support/com.conductor.app/agent-binaries/acp-providers/opencode/1.18.29/darwin-arm64/opencode acp
          789 /opt/homebrew/bin/opencode
          321 /Users/me/Library/Application Support/com.conductor.app/agent-binaries/acp-providers/opencode/1.18.29/darwin-arm64/opencode acp --extra
        """
        check(
            OpenRouterCredential.conductorPIDs(in: processList) == [456],
            "only Conductor's exact OpenCode ACP process qualifies"
        )

        let environment = "PATH=/usr/bin HOME=/Users/me OPENROUTER_API_KEY=sk-or-test-conductor OTHER_SECRET=ignore"
        check(
            OpenRouterCredential.key(inProcessEnvironment: environment) == "sk-or-test-conductor",
            "the OpenRouter value must be extracted from a process environment"
        )
        check(
            OpenRouterCredential.key(inProcessEnvironment: "PATH=/usr/bin") == nil,
            "an environment without OpenRouter must not yield a key"
        )
    }

    private static func testOpenRouterDollarFormatting() {
        check(OpenRouterBudget.dollars(20) == "$20", "whole budgets should omit cents")
        check(OpenRouterBudget.dollars(20.75) == "$20.75", "a non-whole budget must keep its cents")
        check(OpenRouterBudget.dollars(0.105751342) == "$0.11", "spend should round to cents")
        check(OpenRouterBudget.dollars(0.04) == "$0.04", "sub-five-cent spend must not round to zero")
        check(OpenRouterBudget.dollars(0.004) == "$0.004", "small spend must stay visible")
        check(OpenRouterBudget.dollars(12.34) == "$12.34", "larger values should use the same precision")

        let costWindow = UsageWindow(
            label: "day", percent: 15, resetsAt: nil, windowSeconds: nil,
            spentUSD: 0.1, budgetUSD: 0.7
        )
        check(
            Pace.tooltip(source: nil, window: costWindow, showsCost: true).contains("$0.1 / $0.7"),
            "the optional cost tooltip must include rounded dollars"
        )
        check(
            !Pace.tooltip(source: nil, window: costWindow, showsCost: false).contains("$"),
            "disabling dollar values must also hide them from the menu bar tooltip"
        )
    }

    // ----------------------------------------------------------------- //
    // What the menu bar speaks for.
    // ----------------------------------------------------------------- //

    private static func testBusiestWindowsIgnoreWhoOwnsThem() {
        // Two busy Claude windows and one idle Codex one: asking for the two
        // busiest has to mean exactly that, twice the same provider included.
        let picked = twoProviderReport().busiestWindows(limit: 2, timing: wallTiming)
        check(
            picked.map(\.provider.name) == ["Claude", "Claude"],
            "the busiest windows must be the busiest, whoever owns them"
        )
        check(
            picked.map(\.window.percent) == [95, 90],
            "the busiest windows must come back in order"
        )
    }

    private static func testFairShareGivesEveryProviderASlot() {
        let picked = twoProviderReport().busiestWindows(
            limit: 2,
            fairShare: true,
            timing: wallTiming
        )
        check(
            picked.map(\.provider.name) == ["Claude", "Codex"],
            "fair share must seat a second provider before the first repeats"
        )
    }

    private static func testFairShareSpendsSpareSlotsOnTheNextWorstWindow() {
        let picked = twoProviderReport().busiestWindows(
            limit: 3,
            fairShare: true,
            timing: wallTiming
        )
        check(
            picked.map(\.provider.name) == ["Claude", "Codex", "Claude"],
            "a spare slot must go to the next worst window, whoever owns it"
        )
        check(
            picked.map(\.window.percent) == [95, 1, 90],
            "the repeat slot must be the provider's second worst window"
        )
    }

    private static func twoProviderReport() -> Report {
        Report(providers: [
            provider(name: "Claude", windows: [
                window(percent: 95, elapsedPercent: 95),
                window(percent: 90, elapsedPercent: 95),
            ]),
            provider(name: "Codex", windows: [window(percent: 1, elapsedPercent: 50)]),
        ])
    }

    // ----------------------------------------------------------------- //
    // Provider marks.
    // ----------------------------------------------------------------- //

    private static func testShippedIconsParse() {
        for (provider, file) in [
            ("Claude", "claude.svg"),
            ("Codex", "openai.svg"),
            ("OpenRouter", "openrouter.svg"),
        ] {
            guard let directory = BrandGlyph.iconDirectory else {
                check(false, "icon directory must resolve")
                return
            }
            let url = directory.appendingPathComponent(file)
            guard let document = try? String(contentsOf: url, encoding: .utf8) else {
                check(false, "\(file) must be readable — is it still in Resources/Icons?")
                return
            }
            guard let outline = SVGPath.outline(in: document), let path = SVGPath.parse(outline) else {
                check(false, "\(file) must parse into a path")
                return
            }
            // All shipped marks must remain non-trivial outlines.
            let bounds = path.bounds
            check(
                bounds.width > 14 && bounds.height > 14,
                "\(file) must remain a legible outline, got \(bounds)"
            )
            guard let fitted = BrandGlyph.path(
                for: provider,
                fitting: NSSize(width: 24, height: 24),
                flipped: false
            ) else {
                check(false, "\(file) must fit into a provider mark")
                return
            }
            check(
                fitted.bounds.minX >= -0.1 && fitted.bounds.minY >= -0.1
                    && fitted.bounds.maxX <= 24.1 && fitted.bounds.maxY <= 24.1,
                "\(file) must fit uniformly inside 24×24, got \(fitted.bounds)"
            )
        }

        check(
            close(BrandGlyph.width(for: "Claude", height: 14), 14),
            "square provider marks must keep a square slot"
        )
        check(
            close(BrandGlyph.width(for: "OpenRouter", height: 14), 14),
            "OpenRouter's compact mark must keep a square slot"
        )
    }

    private static func testArcFlagsAreReadOneCharacterWide() {
        // `0 01 10` is two flags and two numbers. Reading the flags as numbers
        // swallows the sweep flag and the arc comes out mirrored.
        guard let glued = SVGPath.parse("M0 0a5 5 0 0110 0"),
              let spaced = SVGPath.parse("M0 0a5 5 0 0 1 10 0")
        else {
            check(false, "an arc with glued flags must parse")
            return
        }
        check(
            abs(glued.bounds.height - spaced.bounds.height) < 0.01,
            "glued arc flags must describe the same arc as spaced ones"
        )
        check(
            abs(spaced.bounds.height - 5) < 0.01,
            "a semicircle of radius 5 must be 5 tall, got \(spaced.bounds.height)"
        )
    }

    private static func testMenuBarItemIsNeverZeroWidth() {
        // The empty reading has no provider to draw a mark for, so a logo-only
        // item would have nothing in it at all. With no Dock tile, that leaves
        // no way back to the settings or to Quit.
        for parts in [StatusIcon.Parts.mark, .gauge, .percent, .window, []] {
            let image = StatusIcon.image(segments: [], parts: parts)
            check(
                image.size.width > 0,
                "an empty reading must stay clickable, got \(image.size) for \(parts)"
            )
        }
    }

    private static func testStrayArgumentAfterCloseIsRejected() {
        // Close takes no arguments, so it has nothing to repeat over. Treating
        // it as repeatable leaves the `1` here forever unconsumed, and the
        // parse loop spins on it instead of giving up.
        check(SVGPath.parse("M0 0Z1") == nil, "a stray argument after close must fail the parse")
        check(SVGPath.parse("M0 0L1 1Z") != nil, "a well-formed close must still parse")
    }

    private static func testWindowInitialSkipsDigits() {
        // `5h` has to read as `h`; taking the very first character gives `5`,
        // which says nothing about the window at all.
        check(StatusIcon.windowInitial("5h") == "h", "5h must be marked h")
        check(StatusIcon.windowInitial("week") == "w", "week must be marked w")
        check(StatusIcon.windowInitial("spark week") == "s", "spark week must be marked s")
        check(StatusIcon.windowInitial("30") == nil, "a label with no letters gets no mark")
    }

    private static func testNotLoggedInProviderIsHidden() {
        var absent = Provider(name: "Codex")
        absent.error = "not logged in"
        let report = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 40, elapsedPercent: 50)]), absent],
            date: now
        )
        check(
            report.visibleProviders.map(\.name) == ["Claude"],
            "a provider that was never logged in must not be shown"
        )
    }

    private static func testHiddenProviderAndSparkWindowsAreFiltered() {
        var codex = provider(name: "Codex", windows: [
            window(percent: 10, elapsedPercent: 50),
        ])
        codex.windows.append(UsageWindow(label: "spark 5h", percent: 0, resetsAt: nil, windowSeconds: 5 * 3600))
        codex.windows.append(UsageWindow(label: "spark week", percent: 0, resetsAt: nil, windowSeconds: 7 * 86400))
        let claude = provider(name: "Claude", windows: [window(percent: 80, elapsedPercent: 50)])
        let report = Report(providers: [claude, codex], date: now)

        check(
            report.hasSparkSession && report.hasSparkWeekly,
            "each spark bucket must be detectable for its own settings switch"
        )

        let hidClaude = report.displayProviders(hiding: ["Claude"], hidingSpark: .none)
        check(hidClaude.map(\.name) == ["Codex"], "a hidden provider must be dropped")

        let noSession = report.displayProviders(hidingSpark: HiddenSpark(session: true))
        let sessionRows = noSession.first { $0.name == "Codex" }?.windows.map(\.label)
        check(
            sessionRows == ["10.0", "spark week"],
            "hiding the session row must keep the weekly spark row"
        )

        let noSpark = report.displayProviders(hidingSpark: HiddenSpark(session: true, weekly: true))
        let codexRows = noSpark.first { $0.name == "Codex" }?.windows.map(\.label)
        check(codexRows == ["10.0"], "both spark rows must be droppable, the main window kept")
    }

    private static func testRecentlyActiveProviderStaysVisibleWhenUnreadable() {
        let good = Report(
            providers: [provider(name: "Codex", windows: [window(percent: 40, elapsedPercent: 50)])],
            date: now
        )
        // Credentials unreadable this round, but Codex has been active: it is
        // partially shown (carried, dimmed), not hidden as if never set up.
        var unreadable = Provider(name: "Codex")
        unreadable.error = "not logged in"
        let later = now.addingTimeInterval(300)
        let merged = Report(providers: [unreadable], date: later).carryingOver(from: good, now: later)

        check(merged.providers[0].ok, "a recently-active provider keeps its last reading")
        check(merged.providers[0].stale, "the carried reading is marked stale")
        check(
            merged.visibleProviders.map(\.name) == ["Codex"],
            "a provider that has been active must stay on screen, not vanish"
        )
    }

    private static func testFailedPollKeepsTheLastReading() {
        let good = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 40, elapsedPercent: 50)])],
            date: now
        )
        var failed = Provider(name: "Claude")
        failed.loggedIn = true
        failed.error = "stored token went stale — run claude once to refresh it"
        // Inside the carried window's own life: a window that has reset is a
        // separate case, and `testCarriedWindowIsDroppedOnceItHasReset` has it.
        let later = now.addingTimeInterval(300)
        let merged = Report(providers: [failed], date: later).carryingOver(from: good, now: later)

        let carried = merged.providers[0]
        check(carried.ok, "a one-off failed poll must not blank the provider out")
        check(carried.stale, "the carried reading must be marked stale")
        check(carried.windows.count == 1, "the last reading's rows must survive")
        check(carried.error != nil, "the reason for the failed poll must still be said")
        check(carried.measuredAt == good.updatedAt, "the carried rows must say when they were measured")
    }

    private static func testCarriedReadingIsDroppedOnceItIsOld() {
        let good = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 40, elapsedPercent: 50)])],
            date: now
        )
        let later = now.addingTimeInterval(Report.carryLimit + 60)
        var failed = Provider(name: "Claude")
        failed.loggedIn = true
        failed.error = "the service is not answering (http 503)"
        let merged = Report(providers: [failed], date: later).carryingOver(from: good, now: later)

        check(!merged.providers[0].ok, "a reading older than the carry limit must not be shown as usable")
        check(merged.providers[0].windows.isEmpty, "stale-beyond-limit rows must be dropped")
    }

    private static func testCarriedWindowIsDroppedOnceItHasReset() {
        // 94% of a five-hour window that resets a minute from now. Once it has,
        // the quota is empty and carrying the old number would keep the menu bar
        // red — and the verdict at "nearly out" — through the fresh window.
        let spent = UsageWindow(
            label: "5h",
            percent: 94,
            resetsAt: Int(now.timeIntervalSince1970) + 60,
            windowSeconds: 18_000
        )
        let week = UsageWindow(
            label: "week",
            percent: 30,
            resetsAt: Int(now.timeIntervalSince1970) + 86_400,
            windowSeconds: 604_800
        )
        let good = Report(providers: [provider(name: "Claude", windows: [spent, week])], date: now)

        let later = now.addingTimeInterval(120)
        var failed = Provider(name: "Claude")
        failed.loggedIn = true
        failed.error = "stored token went stale — run claude once"
        let merged = Report(providers: [failed], date: later).carryingOver(from: good, now: later)

        let carried = merged.providers[0]
        check(carried.ok && carried.stale, "the windows that have not reset must still be carried")
        check(
            carried.windows.map(\.label) == ["week"],
            "a window carried past its own reset must be dropped"
        )

        // And with nothing left to carry, the provider goes back to having no
        // reading rather than to an empty one that still counts as usable.
        let onlySpent = Report(providers: [provider(name: "Claude", windows: [spent])], date: now)
        let emptied = Report(providers: [failed], date: later).carryingOver(from: onlySpent, now: later)
        check(!emptied.providers[0].ok, "a provider whose every carried window has reset is not ok")
    }

    private static func testHasNoReadingOnlyWhenAPollLandedNothing() {
        // Set up but unreachable: the card must say the app is still trying,
        // not that there is simply nothing.
        var down = Provider(name: "Claude")
        down.loggedIn = true
        down.error = "unreachable — The Internet connection appears to be offline."
        let failed = Report(providers: [down], date: now)
        check(failed.hasNoReading, "a logged-in provider with no windows is a failed poll")

        // Nothing set up at all: there is no poll to retry.
        var absent = Provider(name: "Codex")
        absent.error = "not logged in"
        let empty = Report(providers: [absent], date: now)
        check(!empty.hasNoReading, "a provider that was never set up is not a retry")

        // A reading that landed is not "no reading".
        let good = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 40, elapsedPercent: 50)])],
            date: now
        )
        check(!good.hasNoReading, "a landed reading must not read as missing")

        // A one-off failed poll keeps its last reading, so it is not missing
        // either — the outage notice covers the staleness.
        let later = now.addingTimeInterval(300)
        let merged = Report(providers: [down], date: later).carryingOver(from: good, now: later)
        check(!merged.hasNoReading, "a carried reading is something to draw")

        // OpenRouter with no budget set is not a failed poll: no retry fixes it.
        var unbudgeted = Provider(name: "OpenRouter")
        unbudgeted.loggedIn = true
        unbudgeted.error = OpenRouterBudget.missingBudgetMessage
        unbudgeted.windows = [window(percent: 5, elapsedPercent: 10)]
        let budgetless = Report(providers: [unbudgeted], date: now)
        check(!budgetless.hasNoReading, "awaiting a budget is setup, not a retry")
    }

    private static func testOfflinePollAsksAgainSooner() {
        // Nothing could be reached: retry on the short cadence.
        var offline = Provider(name: "Claude")
        offline.loggedIn = true
        offline.error = "unreachable — The Internet connection appears to be offline."
        offline.unreachable = true
        check(
            Report(providers: [offline], date: now).needsFastRetry,
            "a poll that reached nobody must ask again sooner"
        )

        // One blocked host among reachable ones is not offline: the others
        // answered, so they keep the user's interval.
        let mixed = Report(providers: [
            offline,
            provider(name: "Codex", windows: [window(percent: 40, elapsedPercent: 50)]),
        ], date: now)
        check(
            !mixed.needsFastRetry,
            "one unreachable provider must not shorten everyone's interval"
        )

        // A token the provider rejected is not the offline case: asking again
        // in a minute cannot fix it.
        var rejected = Provider(name: "Codex")
        rejected.loggedIn = true
        rejected.error = "stored token went stale — run codex once"
        check(
            !Report(providers: [rejected], date: now).needsFastRetry,
            "a rejection must not shorten the interval"
        )

        // A landed reading restores the user's cadence.
        let good = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 40, elapsedPercent: 50)])],
            date: now
        )
        check(!good.needsFastRetry, "a landed reading must not keep the short cadence")

        // Going offline with a reading still in hand is still offline: the card
        // keeps the carried rows and comes back in a minute.
        let later = now.addingTimeInterval(300)
        let carried = Report(providers: [offline], date: later).carryingOver(from: good, now: later)
        check(carried.providers[0].stale, "the carried rows must be marked stale")
        check(carried.providers[0].unreachable, "the offline reason must survive the carry")
        check(carried.needsFastRetry, "an offline poll with carried rows still retries sooner")
    }

    private static func testBudgetModeQuotesTheBudget() {
        // Half the budget a quarter of the way in — 50 against the budget, 200
        // against the clock. Budget mode must not be tempted by the latter.
        let reading = Pace.reading(
            window(percent: 50, elapsedPercent: 25),
            mode: .budget,
            timing: wallTiming
        )
        check(reading.text == "50%", "budget mode must quote the budget, got \(reading.text)")
        check(reading.hasValue, "a budget reading always has a value")
    }

    private static func testTargetModeQuotesThePaceIndex() {
        let reading = Pace.reading(
            window(percent: 50, elapsedPercent: 25),
            mode: .target,
            timing: wallTiming
        )
        check(reading.text == "200%", "target mode must quote the pace index, got \(reading.text)")
        check(reading.hasValue, "a pace index that exists is a value")
        check(Pace.PercentMode.target.rawValue == "pace", "target mode must preserve the legacy preference")
    }

    private static func testTargetModeSaysNothingWhileTheWindowIsYoung() {
        // The budget number must NOT stand in here. Both readings share one
        // column, so a budget percentage printed under a target heading is
        // indistinguishable from a target one and quietly means something else —
        // which is exactly how "2% of target" and "2% of budget" came to look
        // like the same reading for a window that had just reset.
        let reading = Pace.reading(
            window(percent: 3, elapsedPercent: 0.5),
            mode: .target,
            timing: wallTiming
        )
        check(
            reading.text == Pace.noReading,
            "a window too young for a target comparison must print a dash, got \(reading.text)"
        )
        check(!reading.hasValue, "an absent target comparison must not claim to have a value")
        check(reading.text != "3%", "the budget number must never stand in for a target comparison")
    }

    private static func testPaceIsPrintedSoonerThanItIsColoured() {
        // Between the two floors: settled enough to print next to the reset
        // time that explains it, not settled enough to recolour the row or to
        // decide which window the menu bar speaks for.
        let young = window(percent: 2, elapsedPercent: 2)
        check(
            Pace.reading(young, mode: .target, timing: wallTiming).text == "100%",
            "a window past the display floor must print its pace"
        )
        check(
            Pace.ratio(young, timing: wallTiming) == nil,
            "the same window must still be too young to be given a severity tier"
        )
    }

    private static func testPaceReadingIsCapped() {
        // 100% of the budget spent against a 5% target is a 2000% pace index,
        // would widen the menu bar item without telling the reader anything.
        let runaway = window(percent: 100, elapsedPercent: 5)
        let reading = Pace.reading(runaway, mode: .target, timing: wallTiming)
        check(reading.text == "999%", "a runaway pace must be capped, got \(reading.text)")

        let tooltip = Pace.tooltip(source: nil, window: runaway, timing: wallTiming)
        check(
            tooltip.contains("999% of target"),
            "the tooltip must agree with the capped pace reading, got \(tooltip)"
        )
        check(!tooltip.contains("2000% of target"), "the tooltip must not expose the uncapped reading")
    }

    private static func testTooltipStatesBothReadings() {
        let tooltip = Pace.tooltip(
            source: "Claude 5h",
            window: window(percent: 50, elapsedPercent: 25),
            timing: wallTiming
        )
        for expected in ["Claude 5h", "200% of target", "50% of the budget", "25% target"] {
            check(tooltip.contains(expected), "tooltip must state \(expected), got: \(tooltip)")
        }

        // With no target comparison to state it has to say why rather than quote a number.
        let young = Pace.tooltip(
            source: nil,
            window: window(percent: 3, elapsedPercent: 2),
            timing: wallTiming
        )
        check(!young.contains("of target"), "a young window must not be given a target comparison")
        check(young.contains("3% of the budget"), "the budget is stated either way")
    }

    private static func testFullWindowSaysOutOnce() {
        // A spent window: "nearly out" hedges against a bar reading 100%, and
        // quoting "100% of the 5h window" after "5h window out" says it twice.
        let spent = UsageWindow(
            label: "5h",
            percent: 100,
            resetsAt: Int(now.timeIntervalSince1970) + 600,
            windowSeconds: 18_000
        )
        let report = Report(providers: [provider(name: "Claude", windows: [spent])], date: now)
        let verdict = Pace.verdict(report, mode: .budget, timing: wallTiming)
        check(verdict.headline == "5h window out", "a full window is out, not nearly out, got \(verdict.headline)")
        check(!verdict.line.contains("100%"), "the line must not repeat the number it just stated, got \(verdict.line)")
        check(
            Pace.note(report.providers[0], timing: wallTiming)?.text == "out",
            "the provider note must agree with the verdict"
        )

        var nearly = spent
        nearly.percent = 94
        let nearlyReport = Report(providers: [provider(name: "Claude", windows: [nearly])], date: now)
        let nearlyVerdict = Pace.verdict(nearlyReport, mode: .budget, timing: wallTiming)
        check(nearlyVerdict.headline == "5h window nearly out", "below 100% still hedges, got \(nearlyVerdict.headline)")
        check(nearlyVerdict.line.contains("94%"), "a hedged line still quotes the number, got \(nearlyVerdict.line)")
    }

    private static func testVerdictUsesTargetLanguage() {
        let report = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 50, elapsedPercent: 25)])],
            date: now
        )
        let verdict = Pace.verdict(report, mode: .target, timing: wallTiming)
        check(verdict.headline == "Well above target", "the verdict must use target language")
        check(verdict.line.contains("200% of target"), "the verdict must name the target comparison")
        check(!verdict.line.lowercased().contains("pace"), "user-facing verdicts must not say pace")
    }

    // ----------------------------------------------------------------- //
    // Working-hours targets and pace.
    // ----------------------------------------------------------------- //

    private static func testWorkingHoursRedistributeShortWindow() {
        let calendar = utcCalendar()
        let start = date(2026, 7, 27, 17, 0, calendar: calendar)
        let reset = date(2026, 7, 27, 22, 0, calendar: calendar)
        let current = date(2026, 7, 27, 18, 0, calendar: calendar)
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: [.monday],
            startMinute: 17 * 60,
            endMinute: 19 * 60
        )
        let timing = Pace.Timing(now: current, schedule: schedule, calendar: calendar)
        let quota = quotaWindow(start: start, reset: reset, percent: 20)

        let target = Pace.target(quota, timing: timing)
        check(target?.basis == .workingHours, "the overlapping short window must use working hours")
        check(close(target?.percent, 50), "one of two usable hours must produce a 50% target")
        check(
            close(Pace.paceIndex(quota, timing: timing), 40),
            "20% spent against a 50% target must produce a 40% pace index"
        )
        check(
            Pace.tooltip(source: nil, window: quota, timing: timing).contains("working hours"),
            "the tooltip must name the working-hours basis"
        )
    }

    private static func testWorkingHoursSwitchBackToWallClock() {
        let calendar = utcCalendar()
        let start = date(2026, 7, 27, 17, 0, calendar: calendar)
        let reset = date(2026, 7, 27, 22, 0, calendar: calendar)
        let current = date(2026, 7, 27, 20, 0, calendar: calendar)
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: [.monday],
            startMinute: 17 * 60,
            endMinute: 19 * 60
        )
        let timing = Pace.Timing(now: current, schedule: schedule, calendar: calendar)
        let quota = quotaWindow(start: start, reset: reset, percent: 20)

        let target = Pace.target(quota, timing: timing)
        check(target?.basis == .wallClock, "after 19:00 the same window must use wall clock")
        check(close(target?.percent, 60), "three of five wall hours must produce a 60% target")
        check(
            Pace.tooltip(source: nil, window: quota, timing: timing).contains("wall clock"),
            "the tooltip must name the wall-clock basis when the feature is enabled"
        )
    }

    private static func testWorkingHoursSpreadAWeekAcrossAllSelectedHours() {
        let calendar = utcCalendar()
        let start = date(2026, 7, 27, 0, 0, calendar: calendar)
        let reset = date(2026, 8, 3, 0, 0, calendar: calendar)
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: WorkSchedule.defaultWeekdays,
            startMinute: 9 * 60,
            endMinute: 19 * 60
        )
        let quota = quotaWindow(start: start, reset: reset, percent: 25)

        let wednesday = Pace.Timing(
            now: date(2026, 7, 29, 14, 0, calendar: calendar),
            schedule: schedule,
            calendar: calendar
        )
        let target = Pace.target(quota, timing: wednesday)
        check(target?.basis == .workingHours, "the weekly window must use its scheduled hours")
        check(
            close(target?.percent, 50),
            "25 of the week's 50 working hours must produce a 50% target"
        )
        check(
            close(Pace.paceIndex(quota, timing: wednesday), 50),
            "25% spent against a 50% target must produce a 50% pace index"
        )

        let saturday = Pace.Timing(
            now: date(2026, 8, 1, 12, 0, calendar: calendar),
            schedule: schedule,
            calendar: calendar
        )
        let weekend = Pace.target(quota, timing: saturday)
        check(weekend?.basis == .wallClock, "the weekly window must switch to wall clock on Saturday")
        check(
            close(weekend?.percent, 132.0 / 168.0 * 100),
            "weekend wall-clock progress must keep moving"
        )
    }

    private static func testWorkingHoursZeroOverlapFallsBackToWallClock() {
        let calendar = utcCalendar()
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: [.monday],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        )
        let current = date(2026, 7, 27, 10, 0, calendar: calendar)
        let quota = quotaWindow(
            start: date(2026, 7, 28, 20, 0, calendar: calendar),
            reset: date(2026, 7, 29, 1, 0, calendar: calendar),
            percent: 0
        )
        let timing = Pace.Timing(now: current, schedule: schedule, calendar: calendar)

        check(
            Pace.target(quota, timing: timing)?.basis == .wallClock,
            "a window with no scheduled overlap must fall back to wall clock"
        )
    }

    private static func testWorkingHoursDisabledUsesWallClock() {
        let calendar = utcCalendar()
        let start = date(2026, 7, 27, 17, 0, calendar: calendar)
        let reset = date(2026, 7, 27, 22, 0, calendar: calendar)
        let schedule = WorkSchedule(
            enabled: false,
            weekdays: [.monday],
            startMinute: 17 * 60,
            endMinute: 19 * 60
        )
        let timing = Pace.Timing(
            now: date(2026, 7, 27, 18, 0, calendar: calendar),
            schedule: schedule,
            calendar: calendar
        )
        let quota = quotaWindow(start: start, reset: reset, percent: 20)

        let target = Pace.target(quota, timing: timing)
        check(target?.basis == .wallClock, "a disabled schedule must preserve the wall-clock target")
        check(close(target?.percent, 20), "one of five wall hours must produce a 20% target")
        check(
            Pace.target(UsageWindow(label: "unknown", percent: 10), timing: timing) == nil,
            "missing reset metadata must still produce no target"
        )

        let invalid = WorkSchedule(
            enabled: true,
            weekdays: [.monday],
            startMinute: 9 * 60,
            endMinute: 9 * 60
        )
        check(!invalid.isValid, "equal start and end times must be invalid")
        let invalidTiming = Pace.Timing(
            now: timing.now,
            schedule: invalid,
            calendar: calendar
        )
        check(
            Pace.target(quota, timing: invalidTiming)?.basis == .wallClock,
            "an invalid schedule must fall back to wall clock"
        )

        let restored = WorkSchedule(
            enabled: true,
            weekdayMask: schedule.weekdayMask,
            startMinute: schedule.startMinute,
            endMinute: schedule.endMinute
        )
        check(restored.weekdays == schedule.weekdays, "the persisted weekday mask must round-trip")
    }

    private static func testOvernightScheduleBelongsToItsStartDay() {
        let calendar = utcCalendar()
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: [.monday],
            startMinute: 22 * 60,
            endMinute: 2 * 60
        )
        let mondayStart = date(2026, 7, 27, 21, 0, calendar: calendar)
        let tuesdayEnd = date(2026, 7, 28, 3, 0, calendar: calendar)
        let range = DateInterval(start: mondayStart, end: tuesdayEnd)

        check(
            schedule.isActive(
                at: date(2026, 7, 28, 1, 0, calendar: calendar),
                calendar: calendar
            ),
            "Tuesday 01:00 must belong to Monday's overnight shift"
        )
        check(
            close(schedule.scheduledSeconds(in: range, calendar: calendar), 4 * 3600),
            "the overnight shift must contribute four hours"
        )
    }

    private static func testScheduleRespectsDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: [.sunday],
            startMinute: 60,
            endMinute: 4 * 60
        )

        let spring = DateInterval(
            start: date(2026, 3, 29, 0, 0, calendar: calendar),
            end: date(2026, 3, 30, 0, 0, calendar: calendar)
        )
        let autumn = DateInterval(
            start: date(2026, 10, 25, 0, 0, calendar: calendar),
            end: date(2026, 10, 26, 0, 0, calendar: calendar)
        )
        check(
            close(schedule.scheduledSeconds(in: spring, calendar: calendar), 2 * 3600),
            "01:00–04:00 must contain two wall hours across spring-forward"
        )
        check(
            close(schedule.scheduledSeconds(in: autumn, calendar: calendar), 4 * 3600),
            "01:00–04:00 must contain four wall hours across fall-back"
        )
    }

    private static func testScheduleUsesTheProvidedTimeZone() {
        var utc = utcCalendar()
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let instant = date(2026, 7, 27, 10, 0, calendar: utc)
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: [.monday],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        )

        check(schedule.isActive(at: instant, calendar: utc), "10:00 UTC must be inside the schedule")
        check(
            !schedule.isActive(at: instant, calendar: newYork),
            "the same instant at 06:00 New York time must be outside the schedule"
        )
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private static func testScheduleBoundaryIsExact() {
        let calendar = utcCalendar()
        let schedule = WorkSchedule(
            enabled: true,
            weekdays: [.monday],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        )
        let before = date(2026, 7, 27, 17, 59, calendar: calendar)
        let end = date(2026, 7, 27, 18, 0, calendar: calendar)

        check(schedule.nextBoundary(after: before, calendar: calendar) == end, "18:00 is the next boundary")
        check(!schedule.isActive(at: end, calendar: calendar), "the schedule must be inactive at its end")
    }

    // ----------------------------------------------------------------- //

    private static func provider(name: String, windows: [UsageWindow]) -> Provider {
        var provider = Provider(name: name)
        provider.ok = true
        provider.loggedIn = true
        provider.windows = windows
        return provider
    }

    private static func window(percent: Double, elapsedPercent: Double) -> UsageWindow {
        let length = 1_000
        let remaining = Double(length) * (1 - elapsedPercent / 100)
        return UsageWindow(
            label: "\(percent)",
            percent: percent,
            resetsAt: Int(now.timeIntervalSince1970 + remaining),
            windowSeconds: length
        )
    }

    private static func quotaWindow(start: Date, reset: Date, percent: Double) -> UsageWindow {
        UsageWindow(
            label: "quota",
            percent: percent,
            resetsAt: Int(reset.timeIntervalSince1970),
            windowSeconds: Int(reset.timeIntervalSince(start))
        )
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private static func close(_ actual: Double?, _ expected: Double, tolerance: Double = 0.01) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) <= tolerance
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
