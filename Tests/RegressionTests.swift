import AppKit
import Darwin
import Foundation

@main
enum RegressionTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let wallTiming = Pace.Timing(now: now)

    static func main() {
        ProviderFolderAccessTests.run()
        testRedHighUsageWindowOutranksGreenWindow()
        testColorTierOutranksPercentage()
        testProcessOutputIsReturned()
        testProcessIsTerminatedAtTimeout()
        testClaudeLimitsAreParsedGenerically()
        testClaudeLegacyLimitsRemainFallback()
        testClaudeMalformedLimitsAreSkipped()
        testClaudeKeychainServiceDerivation()
        testClaudePathNormalization()
        testClaudeCatalogMerging()
        testClaudeDefaultLabels()
        testClaudeLegacyProviderDecoding()
        testClaudeDuplicateTokenCollapse()
        testClaudeConfigDirFromEnvironment()
        testCodexProfileIDsAndPaths()
        testCodexCatalogMerging()
        testCodexDefaultLabels()
        testCodexAuthParsingAndDuplicateCollapse()
        testCodexHomeFromEnvironment()
        testMultipleCodexPollTargetOrdering()
        testCodexAdditionalLimitsAreParsedGenerically()
        testCodexMalformedAdditionalLimitsAreSkipped()
        testProviderSpecificModelDisplayNames()
        testCodexSparkPreferencesMigrateToModelVisibility()
        testModelLimitHistoryRemembersPastModels()
        testModelLimitHistorySeedsSparkForExistingInstalls()
        testOpenRouterBuildsBudgetWindows()
        testOpenRouterUsesLeapMonth()
        testWindowMetadataRoundTrips()
        testOpenRouterRebudgetsCachedSpend()
        testOpenCodeOpenRouterCredentialIsParsed()
        testConductorCredentialEnvironmentIsParsed()
        testOpenRouterDollarFormatting()
        testOpenCodeGoUsageWindowsAreParsed()
        testOpenCodeGoMalformedWindowsAreSkipped()
        testOpenCodeGoProviderPresentation()
        testOpenCodeGoLegacyCredentialIsParsed()
        testOpenCodeGoAccountCredentialIsParsed()
        testOpenCodeGoEnvironmentCredentialIsParsed()
        testCursorSummaryBecomesCycleWindows()
        testCursorSummaryOmitsZeroBreakdown()
        testCursorProSpendUnderOneThousandCents()
        testCursorSessionCookieIsBuiltFromJWT()
        testCursorAPIKeyIsNotASession()
        testCursorTeamSpendMapsCents()
        testCursorRebudgetsCachedSpend()
        testCursorReconnectMessages()
        testConductorCursorEnvironmentIsParsed()
        testBusiestWindowsIgnoreWhoOwnsThem()
        testFairShareGivesEveryProviderASlot()
        testFairShareSpendsSpareSlotsOnTheNextWorstWindow()
        testShippedIconsParse()
        testArcFlagsAreReadOneCharacterWide()
        testWindowInitialSkipsDigits()
        testMenuBarItemIsNeverZeroWidth()
        testStrayArgumentAfterCloseIsRejected()
        testNotLoggedInProviderIsHidden()
        testHiddenProviderIsFiltered()
        testHiddenScopedModelLimitsAreFiltered()
        testRecentlyActiveProviderStaysVisibleWhenUnreadable()
        testFailedPollKeepsTheLastReading()
        testCarriedReadingIsDroppedOnceItIsOld()
        testCarriedWindowIsDroppedOnceItHasReset()
        testHasNoReadingOnlyWhenAPollLandedNothing()
        testOfflinePollAsksAgainSooner()
        testJWTExpiryIsParsed()
        testStaleTokenSurvivesTheCarry()
        testCarryRemembersConductorSource()
        testLostConductorKeyPointsToSettings()
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
    // Claude's structured limits include model-scoped rows.
    // ----------------------------------------------------------------- //

    private static func testClaudeLimitsAreParsedGenerically() {
        let data: [String: Any] = [
            "limits": [
                [
                    "kind": "session",
                    "group": "session",
                    "percent": 64,
                    "resets_at": "2026-09-18T10:50:00+00:00",
                    "scope": NSNull(),
                ],
                [
                    "kind": "weekly_all",
                    "group": "weekly",
                    "percent": 81,
                    "resets_at": "2026-09-19T18:59:59+00:00",
                    "scope": NSNull(),
                ],
                [
                    "kind": "weekly_scoped",
                    "group": "weekly",
                    "percent": 71,
                    "resets_at": "2026-09-19T18:59:59+00:00",
                    "scope": [
                        "model": ["id": NSNull(), "display_name": "Fable"],
                        "surface": NSNull(),
                    ],
                ],
            ],
        ]

        let windows = Fetcher.claudeWindows(data)
        check(
            windows.map(\.label) == ["5h", "week", "week (Fable)"],
            "Claude limits must retain the base rows and name any scoped model"
        )
        check(windows.map(\.percent) == [64, 81, 71], "Claude limit percentages must be preserved")
        check(windows[2].model == "Fable", "the scoped model must remain structured metadata")
        check(windows[2].windowSeconds == 7 * 86_400, "a scoped weekly row must keep weekly pacing")
    }

    private static func testClaudeLegacyLimitsRemainFallback() {
        let data: [String: Any] = [
            "five_hour": [
                "utilization": 12,
                "resets_at": "2026-09-18T10:50:00+00:00",
            ],
            "seven_day": [
                "utilization": 34,
                "resets_at": "2026-09-19T18:59:59+00:00",
            ],
        ]

        let windows = Fetcher.claudeWindows(data)
        check(windows.map(\.label) == ["5h", "week"], "legacy Claude responses must still produce both rows")
        check(windows.map(\.percent) == [12, 34], "legacy utilization values must be preserved")
        check(windows.allSatisfy { $0.model == nil }, "legacy rows must stay unscoped")
    }

    private static func testClaudeMalformedLimitsAreSkipped() {
        let data: [String: Any] = [
            "five_hour": ["utilization": 9],
            "seven_day": ["utilization": 18],
            "limits": [
                ["kind": "weekly_all", "group": "weekly"],
                ["kind": "weekly_scoped", "group": "weekly", "percent": "not a number"],
                ["kind": "monthly_scoped", "group": "monthly", "percent": 25,
                 "scope": ["model": ["display_name": "Future"]]],
            ],
        ]

        let windows = Fetcher.claudeWindows(data)
        check(
            windows.map(\.label) == ["5h", "week", "month (Future)"],
            "malformed structured rows must be skipped while valid future groups stay visible"
        )
        check(windows.last?.windowSeconds == nil, "an unknown limit group must not invent a pacing duration")
    }

    private static func testCodexAdditionalLimitsAreParsedGenerically() {
        let additional: [[String: Any]] = [
            [
                "limit_name": "GPT-5.3-Codex-Spark",
                "rate_limit": [
                    "primary_window": [
                        "used_percent": 12,
                        "reset_at": 1_790_000_000,
                        "limit_window_seconds": 18_000,
                    ],
                    "secondary_window": [
                        "used_percent": 34,
                        "reset_at": 1_790_500_000,
                        "limit_window_seconds": 604_800,
                    ],
                ],
            ],
            [
                "limit_name": "Codex-Research",
                "rate_limit": [
                    "secondary_window": [
                        "used_percent": 56,
                        "reset_at": 1_790_500_000,
                        "limit_window_seconds": 604_800,
                    ],
                ],
            ],
        ]

        let windows = Fetcher.codexAdditionalWindows(additional)
        check(
            windows.map(\.label) == ["5h (Spark)", "week (Spark)", "week (Research)"],
            "every named Codex additional limit must produce compact model-scoped rows"
        )
        check(
            windows.map(\.model) == [
                "GPT-5.3-Codex-Spark",
                "GPT-5.3-Codex-Spark",
                "Codex-Research",
            ],
            "Codex rows must preserve each complete API limit name as metadata"
        )
    }

    private static func testCodexMalformedAdditionalLimitsAreSkipped() {
        let additional: [[String: Any]] = [
            ["rate_limit": ["primary_window": ["used_percent": 10]]],
            ["limit_name": "   ", "rate_limit": ["primary_window": ["used_percent": 20]]],
            ["limit_name": "Codex-Valid", "rate_limit": NSNull()],
        ]
        check(
            Fetcher.codexAdditionalWindows(additional).isEmpty,
            "unnamed or malformed Codex additional limits must be skipped"
        )
    }

    private static func testProviderSpecificModelDisplayNames() {
        check(
            ScopedModelLimit(provider: "Codex", model: "GPT-5.3-Codex-Spark").displayName == "Spark",
            "Codex limit names must retain their compact final segment"
        )
        check(
            ScopedModelLimit(provider: "Codex-deadbeef", model: "GPT-5.3-Codex-Spark").displayName == "Spark",
            "additional Codex profiles must retain compact model names"
        )
        check(
            ScopedModelLimit(provider: "Claude", model: "claude-fable-5-1").displayName
                == "claude-fable-5-1",
            "a Claude raw model ID must match the name shown in its usage row"
        )
    }

    private static func testCodexSparkPreferencesMigrateToModelVisibility() {
        let spark = ScopedModelLimit.key(provider: "Codex", model: ModelLimitMigration.codexSpark)
        let existing = Set([ScopedModelLimit.key(provider: "Claude", model: "Fable")])

        let hidden = ModelLimitMigration.codexSparkVisibility(
            existing: existing,
            hadPreviousReading: true,
            legacySessionHidden: nil,
            legacyWeekHidden: nil,
            legacyAllHidden: nil
        )
        check(hidden.contains(spark), "an existing install with both default-hidden Spark rows must keep Spark hidden")
        check(existing.isSubset(of: hidden), "migration must retain existing model choices")

        let mixed = ModelLimitMigration.codexSparkVisibility(
            existing: existing,
            hadPreviousReading: true,
            legacySessionHidden: true,
            legacyWeekHidden: false,
            legacyAllHidden: nil
        )
        check(!mixed.contains(spark), "a mixed legacy Spark state must become shown under one unified switch")

        let fresh = ModelLimitMigration.codexSparkVisibility(
            existing: existing,
            hadPreviousReading: false,
            legacySessionHidden: nil,
            legacyWeekHidden: nil,
            legacyAllHidden: nil
        )
        check(!fresh.contains(spark), "a fresh install must show newly discovered Spark limits")
    }

    private static func testModelLimitHistoryRemembersPastModels() {
        let spark = ScopedModelLimit(provider: "Codex", model: "GPT-5.3-Codex-Spark")
        let fable = ScopedModelLimit(provider: "Claude", model: "Fable")
        let duplicateSpark = ScopedModelLimit(provider: "codex", model: "gpt-5.3-codex-spark")

        let discovered = ModelLimitHistory.merging(
            existing: [spark],
            discovered: [fable, duplicateSpark]
        )
        check(
            discovered == [spark, fable],
            "model history must append new discoveries once while preserving names and order"
        )
        check(
            ModelLimitHistory.merging(existing: discovered, discovered: []) == discovered,
            "a response that omits model limits must not erase previously discovered models"
        )

        guard let data = try? JSONEncoder().encode(discovered),
              let restored = try? JSONDecoder().decode([ScopedModelLimit].self, from: data)
        else {
            check(false, "model history must encode and decode")
            return
        }
        check(restored == discovered, "persisted model history must retain provider and model names")
    }

    private static func testModelLimitHistorySeedsSparkForExistingInstalls() {
        let existing = ModelLimitHistory.seedingSpark(existing: [], hadPreviousReading: true)
        check(
            existing == [ScopedModelLimit(provider: "Codex", model: ModelLimitMigration.codexSpark)],
            "an existing installation must keep the previously available Spark setting"
        )
        check(
            ModelLimitHistory.seedingSpark(existing: [], hadPreviousReading: false).isEmpty,
            "a fresh installation must not invent a model it has never observed"
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

    private static func testWindowMetadataRoundTrips() {
        let original = UsageWindow(
            label: "day",
            percent: 25,
            resetsAt: 123,
            windowSeconds: 86_400,
            spentUSD: 0.25,
            budgetUSD: 1,
            model: "Fable"
        )
        guard let encoded = try? JSONEncoder().encode(original),
              let restored = try? JSONDecoder().decode(UsageWindow.self, from: encoded)
        else {
            check(false, "an OpenRouter window must encode and decode")
            return
        }
        check(restored == original, "window metadata must survive the usage cache")

        let old = Data(#"{"label":"week","percent":42}"#.utf8)
        let legacy = try? JSONDecoder().decode(UsageWindow.self, from: old)
        check(
            legacy?.spentUSD == nil && legacy?.budgetUSD == nil && legacy?.model == nil,
            "old caches must decode without optional window metadata"
        )
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
    // OpenCode Go's own quota endpoint reports three percentages directly.
    // ----------------------------------------------------------------- //

    private static func testOpenCodeGoUsageWindowsAreParsed() {
        let fixture: [String: Any] = [
            "usage": [
                "rolling": [
                    "status": "ok",
                    "percent": 42,
                    "resetsAt": "2026-09-22T15:30:00.000Z",
                ],
                "weekly": [
                    "status": "ok",
                    "percent": 17.5,
                    "resetsAt": "2026-09-28T00:00:00.000Z",
                ],
                "monthly": [
                    "status": "rate-limited",
                    "percent": 100,
                    "resetsAt": "2026-10-14T10:44:14.289Z",
                ],
            ],
        ]
        let windows = OpenCodeGoUsage.windows(from: fixture)
        check(windows.map(\.label) == ["5h", "week", "month"], "OpenCode Go must expose all three quota windows")
        check(windows.map(\.percent) == [42, 17.5, 100], "OpenCode Go percentages must be preserved")
        check(
            windows.map(\.windowSeconds) == [5 * 3600, 7 * 86400, 30 * 86400],
            "fixed OpenCode Go windows must carry their known durations"
        )
        check(windows.allSatisfy { $0.resetsAt != nil }, "OpenCode Go reset timestamps must be parsed")
    }

    private static func testOpenCodeGoMalformedWindowsAreSkipped() {
        let fixture: [String: Any] = [
            "usage": [
                "rolling": ["percent": Double.nan, "resetsAt": "nope"],
                "weekly": ["percent": 20, "resetsAt": "2026-09-28T00:00:00Z"],
                "monthly": ["status": "ok"],
            ],
        ]
        let windows = OpenCodeGoUsage.windows(from: fixture)
        check(windows.map(\.label) == ["week"], "malformed OpenCode Go windows must not become healthy zeroes")
    }

    private static func testOpenCodeGoProviderPresentation() {
        let provider = Fetcher.openCodeGoProvider()
        check(provider.id == "OpenCode Go", "OpenCode Go must retain its stable provider identity")
        check(provider.kind == "opencode-go", "OpenCode Go must retain its provider mark and settings kind")
        check(provider.name == "OpenCode", "the card must not repeat the Go service tier in its name")
        check(provider.plan == "GO", "Go must remain visible as the service-tier badge")
    }

    private static func testOpenCodeGoLegacyCredentialIsParsed() {
        let primary = Data(#"{"opencode-go":{"type":"api","key":"sk-go-primary"},"opencode":{"type":"api","key":"sk-go-legacy"}}"#.utf8)
        check(
            OpenCodeGoCredential.key(inLegacyAuth: primary) == "sk-go-primary",
            "the dedicated OpenCode Go auth entry must win"
        )
        let legacy = Data(#"{"opencode":{"type":"api","key":"sk-go-legacy"}}"#.utf8)
        check(
            OpenCodeGoCredential.key(inLegacyAuth: legacy) == "sk-go-legacy",
            "the old OpenCode provider entry must remain readable"
        )
        let wrongType = Data(#"{"opencode-go":{"type":"oauth","key":"secret"}}"#.utf8)
        check(OpenCodeGoCredential.key(inLegacyAuth: wrongType) == nil, "only strict API-key entries may be read")
    }

    private static func testOpenCodeGoAccountCredentialIsParsed() {
        let fixture = Data(#"""
        {
          "version": 2,
          "accounts": {
            "account_1": {
              "id": "account_1",
              "serviceID": "opencode-go",
              "credential": {"type": "api", "key": "sk-go-v2"}
            }
          },
          "active": {"opencode-go": "account_1"}
        }
        """#.utf8)
        check(
            OpenCodeGoCredential.key(inAccountStore: fixture) == "sk-go-v2",
            "OpenCode's active v2 account must supply its Go key"
        )
        let inactive = Data(#"""
        {
          "version": 2,
          "accounts": {
            "account_1": {
              "serviceID": "opencode-go",
              "credential": {"type": "api", "key": "inactive-secret"}
            }
          },
          "active": {}
        }
        """#.utf8)
        check(OpenCodeGoCredential.key(inAccountStore: inactive) == nil, "inactive v2 accounts must not be selected")
    }

    private static func testOpenCodeGoEnvironmentCredentialIsParsed() {
        check(
            OpenCodeGoCredential.key(inProcessEnvironment: "PATH=/bin OPENCODE_API_KEY=sk-go OTHER=x") == "sk-go",
            "the standard OpenCode API key environment value must be detected"
        )
        check(
            OpenCodeGoCredential.key(inProcessEnvironment: "OPENCODE_GO_API_KEY=sk-specific OPENCODE_API_KEY=sk-general")
                == "sk-specific",
            "the Go-specific environment value must win when both are present"
        )
    }

    private static func testCursorSummaryBecomesCycleWindows() {
        let summary: [String: Any] = [
            "billingCycleStart": "2026-09-11T16:23:42.215Z",
            "billingCycleEnd": "2026-10-11T16:23:42.215Z",
            "membershipType": "pro",
            "individualUsage": [
                "plan": [
                    "used": 1529,
                    "limit": 2000,
                    "autoPercentUsed": 13.21,
                    "apiPercentUsed": 3.16,
                    "totalPercentUsed": 10.19,
                ],
                "onDemand": [
                    "enabled": true,
                    "used": 4.5,
                    "limit": 20,
                ],
            ],
        ]
        let windows = CursorBudget.windows(fromSummary: summary)
        check(
            windows.map(\.label) == ["month", "month (Auto)", "month (API)", "on-demand"],
            "Cursor must expose cycle, auto, API and on-demand"
        )
        check(close(windows[0].percent, 10.19), "the cycle row must keep the API percentage")
        check(close(windows[0].spentUSD, 15.29), "dashboard cents must become dollars")
        check(close(windows[0].budgetUSD, 20), "a 2000-cent limit is $20")
        check(windows[1].model == "Auto" && windows[2].model == "API", "breakdown rows must be hideable models")
        check(CursorBudget.plan("pro") == "PRO", "membership becomes the plan badge")
        check(CursorBudget.plan("pro_plus") == "PRO+", "pro plus must stay compact")
        let reset = windows[0].resetsAt ?? 0
        check(reset > 1_700_000_000, "the cycle must have a real reset timestamp")
        check(windows[0].windowSeconds == windows[1].windowSeconds, "breakdown rows share the billing cycle")
    }

    private static func testCursorSummaryOmitsZeroBreakdown() {
        let summary: [String: Any] = [
            "billingCycleStart": "2026-09-11T16:23:42Z",
            "billingCycleEnd": "2026-10-11T16:23:42Z",
            "individualUsage": [
                "plan": [
                    "used": 0,
                    "limit": 0,
                    "autoPercentUsed": 0,
                    "apiPercentUsed": 0,
                    "totalPercentUsed": 0,
                ]
            ],
        ]
        let windows = CursorBudget.windows(fromSummary: summary)
        check(windows.map(\.label) == ["month"], "a zero cycle must not sprout empty Auto/API rows")
        check(windows[0].spentUSD == nil, "a zero limit must not invent dollar amounts")
    }

    private static func testCursorProSpendUnderOneThousandCents() {
        let summary: [String: Any] = [
            "billingCycleStart": "2026-09-18T15:28:02.000Z",
            "billingCycleEnd": "2026-10-18T15:28:02.000Z",
            "membershipType": "pro",
            "individualUsage": [
                "plan": [
                    "used": 500,
                    "limit": 2000,
                    "autoPercentUsed": 1.11,
                    "apiPercentUsed": 0,
                    "totalPercentUsed": 1.06,
                ]
            ],
        ]
        let windows = CursorBudget.windows(fromSummary: summary)
        check(windows.map(\.label) == ["month", "month (Auto)"], "a 0% API row must stay hidden")
        check(close(windows[0].spentUSD, 5), "500 included cents is $5, not $500")
        check(close(windows[0].budgetUSD, 20), "a 2000-cent Pro limit is $20")
        check(!CursorBudget.isPlaceholderSummary(summary), "a Pro cycle with a limit is a real reading")
        check(
            CursorBudget.isPlaceholderSummary([
                "membershipType": "free",
                "individualUsage": ["plan": ["used": 0, "limit": 0]],
            ]),
            "a free empty cycle is a leftover login, not the Pro quota"
        )
    }

    private static func testCursorSessionCookieIsBuiltFromJWT() {
        let payload = try! JSONSerialization.data(withJSONObject: ["sub": "auth0|user_01ABC", "exp": 1_790_233_892])
        let segment = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "header.\(segment).signature"
        let session = CursorCredential.session(from: jwt)
        check(
            session?.cookie == "auth0|user_01ABC%3A%3A\(jwt)",
            "a local JWT must become the dashboard cookie"
        )
        check(
            CursorCredential.session(from: "auth0|user_01ABC::\(jwt)")?.jwt == jwt,
            "a pasted sub::jwt must yield the JWT"
        )
        check(
            CursorCredential.session(from: "auth0|user_01ABC%3A%3A\(jwt)")?.jwt == jwt,
            "a URL-encoded cookie paste must yield the JWT"
        )
        check(Fetcher.jwtPayload(jwt)?["sub"] as? String == "auth0|user_01ABC", "jwtPayload must expose claims")
    }

    private static func testCursorAPIKeyIsNotASession() {
        check(CursorCredential.isAPIKey("crsr_abc"), "crsr_ keys are Admin/user API keys")
        check(CursorCredential.session(from: "crsr_abc") == nil, "an API key must not be treated as a session")
        check(!CursorCredential.isAPIKey("eyJhbGciOi.payload.sig"), "a JWT is not an API key")
    }

    private static func testCursorTeamSpendMapsCents() {
        let members: [[String: Any]] = [
            ["overallSpendCents": 2450.0, "monthlyLimitDollars": 40],
        ]
        let spend = CursorBudget.spend(fromTeamMembers: members)
        check(close(spend?.spent, 24.5), "team spend cents must become dollars")
        check(close(spend?.limit, 40), "a single member limit is usable as the budget")
        let windows = CursorBudget.windows(
            monthlySpend: 24.5,
            monthlyBudget: 40,
            now: date(2026, 9, 16, 12, 0, calendar: utcCalendar())
        )
        check(windows.map(\.label) == ["month"], "Admin spend maps to one cycle row")
        check(close(windows[0].percent, 61.25), "$24.50 of $40 is 61.25%")
    }

    private static func testCursorRebudgetsCachedSpend() {
        let instant = date(2026, 9, 16, 12, 0, calendar: utcCalendar())
        var cursor = Provider(name: "Cursor")
        cursor.loggedIn = true
        cursor.credentialSource = .keychain
        cursor.error = CursorBudget.missingBudgetMessage
        cursor.windows = CursorBudget.unbudgetedWindows(monthlySpend: 8, now: instant)
        check(cursor.needsBudget, "an unbudgeted Cursor Admin reading must suppress its empty block")
        let report = Report(providers: [cursor], date: instant)
        let rebudgeted = report.rebudgetingCursor(monthlyBudget: 40, now: instant)
        let provider = rebudgeted.providers[0]
        check(provider.ok && provider.error == nil, "setting a budget must activate a validated Cursor reading")
        check(provider.plan == "$40/mo", "the Cursor budget must become the plan badge")
        check(close(provider.windows[0].percent, 20), "$8 of $40 must be 20%")

        var dashboard = Provider(name: "Cursor")
        dashboard.windows = [
            UsageWindow(label: "month", percent: 10, spentUSD: 2, budgetUSD: 20),
            UsageWindow(label: "month (Auto)", percent: 12, model: "Auto"),
        ]
        let leftAlone = Report(providers: [dashboard], date: instant)
            .rebudgetingCursor(monthlyBudget: 99, now: instant)
        check(
            close(leftAlone.providers[0].windows[0].percent, 10),
            "dashboard percentages must not be rewritten by the budget field"
        )
    }

    private static func testCursorReconnectMessages() {
        var signedOut = Provider(name: "Cursor")
        signedOut.error = CursorBudget.notConnectedMessage
        signedOut.credentialSource = .cursorApp
        check(
            CursorCredential.reconnectMessage(for: signedOut)
                == "Cursor is signed out — sign in, or add a key in Settings",
            "a lost Cursor app session must point back to sign-in"
        )

        var lost = Provider(name: "Cursor")
        lost.error = CursorBudget.notConnectedMessage
        lost.credentialSource = .keychain
        check(
            CursorCredential.reconnectMessage(for: lost)
                == "no live key — add one in Settings to reconnect",
            "a lost Cursor key must point to Settings"
        )
    }

    private static func testConductorCursorEnvironmentIsParsed() {
        let processList = """
          123 /usr/bin/something
          456 /Users/me/Library/Application Support/com.conductor.app/bin/cursor-agent
          789 /opt/homebrew/bin/cursor
        """
        check(
            CursorCredential.conductorPIDs(in: processList) == [456],
            "only Conductor's Cursor process qualifies"
        )
        let environment = "PATH=/usr/bin CURSOR_API_KEY=crsr_test OTHER_SECRET=ignore"
        check(
            CursorCredential.key(inProcessEnvironment: environment) == "crsr_test",
            "the Cursor value must be extracted from a process environment"
        )
        check(
            CursorCredential.key(inProcessEnvironment: "CURSOR_SESSION_TOKEN=sub::jwt.here.sig")
                == "sub::jwt.here.sig",
            "a session token environment value must be detected"
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
            ("opencode-go", "opencode.svg"),
            ("OpenRouter", "openrouter.svg"),
            ("Cursor", "cursor.svg"),
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
        check(
            close(BrandGlyph.width(for: "opencode-go", height: 14), 14),
            "OpenCode's favicon mark must use the same square slot as other marks"
        )
        let openCodeMark = BrandGlyph.path(
            for: "opencode-go",
            fitting: NSSize(width: 14, height: 14),
            flipped: false
        )
        check(
            close(openCodeMark.map { Double($0.bounds.height) }, 14, tolerance: 0.1),
            "OpenCode's favicon mark must fill the provider-mark height"
        )
        check(
            openCodeMark?.contains(NSPoint(x: 1, y: 1)) == false
                && openCodeMark?.contains(NSPoint(x: 2, y: 2)) == true
                && openCodeMark?.contains(NSPoint(x: 7, y: 7)) == false
                && openCodeMark?.contains(NSPoint(x: 7, y: 13)) == true,
            "OpenCode's enlarged favicon mark must keep its centre transparent"
        )
        check(
            close(BrandGlyph.width(for: "Cursor", height: 14), 14),
            "Cursor's compact mark must keep a square slot"
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
        check(StatusIcon.windowInitial("week (Spark)") == "w", "a scoped week must retain the week initial")
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

    private static func testHiddenProviderIsFiltered() {
        let codex = provider(name: "Codex", windows: [window(percent: 10, elapsedPercent: 50)])
        let claude = provider(name: "Claude", windows: [window(percent: 80, elapsedPercent: 50)])
        let report = Report(providers: [claude, codex], date: now)

        let hidClaude = report.displayProviders(hiding: [ClaudeProfile.defaultKeychainService])
        check(hidClaude.map(\.name) == ["Codex"], "a hidden provider must be dropped")
    }

    private static func testHiddenScopedModelLimitsAreFiltered() {
        var claude = provider(name: "Claude", windows: [
            UsageWindow(label: "week", percent: 81, windowSeconds: 7 * 86_400),
            UsageWindow(label: "week (Fable)", percent: 71, windowSeconds: 7 * 86_400, model: "Fable"),
            UsageWindow(label: "month (Future)", percent: 25, model: "Future"),
        ])
        // Preserve a duplicate model row to prove one model switch controls
        // every scoped window for that model, not just a single label.
        claude.windows.append(
            UsageWindow(label: "5h (Fable)", percent: 30, windowSeconds: 5 * 3600, model: "Fable")
        )
        let report = Report(providers: [claude], date: now)
        let fable = ScopedModelLimit.key(
            provider: ClaudeProfile.defaultKeychainService,
            model: "Fable"
        )
        let shown = report.displayProviders(hidingModels: [fable])

        check(
            report.scopedModelLimits.map(\.model) == ["Fable", "Future"],
            "settings must list each discovered model once in reading order"
        )
        check(
            shown[0].windows.map(\.label) == ["week", "month (Future)"],
            "hiding Fable must remove all Fable rows while retaining overall and other model limits"
        )
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

    private static func testCarryRemembersConductorSource() {
        // A Conductor-discovered key is visible only while an OpenCode session
        // runs, so it vanishes between polls. The carried reading must remember
        // it came from Conductor, so the surface can point back there rather
        // than showing a bare "not connected".
        var good = provider(name: "OpenRouter", windows: [window(percent: 20, elapsedPercent: 50)])
        good.credentialSource = .conductor
        let previous = Report(providers: [good], date: now)

        var lost = Provider(name: "OpenRouter")
        lost.error = OpenRouterBudget.notConnectedMessage
        let later = now.addingTimeInterval(300)
        let carried = Report(providers: [lost], date: later).carryingOver(from: previous, now: later)

        check(carried.providers[0].stale, "the last reading must be carried")
        check(
            carried.providers[0].credentialSource == .conductor,
            "the carried reading must remember the Conductor source"
        )
    }

    private static func testLostConductorKeyPointsToSettings() {
        var provider = Provider(name: "OpenRouter")
        provider.error = OpenRouterBudget.notConnectedMessage
        provider.credentialSource = .conductor

        check(
            OpenRouterCredential.reconnectMessage(for: provider)
                == "no live key — add one in Settings to reconnect",
            "a lost transient key must point to the reliable manual-key control"
        )
    }

    private static func testJWTExpiryIsParsed() {
        // Codex's access token is a JWT; its expiry is read locally to tell a
        // freshly-minted token from the stale one, so the base64url payload
        // (with -/_ swapped for +// and stripped padding) must decode.
        let payload = try! JSONSerialization.data(withJSONObject: ["exp": 1_790_233_892])
        let segment = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        check(
            Fetcher.jwtExpiry("header.\(segment).signature") == 1_790_233_892,
            "the exp claim must survive base64url decoding"
        )
        check(Fetcher.jwtExpiry("not-a-jwt") == nil, "a non-JWT must yield no expiry")
        check(Fetcher.jwtExpiry("only.two") == nil, "a malformed JWT must yield no expiry")
    }

    private static func testStaleTokenSurvivesTheCarry() {
        // A 401 sets staleToken; carrying the last reading over the failed poll
        // must keep the flag, so the store stays on the fast token-watch cadence
        // rather than the user's interval while it waits for the CLI to run.
        let good = Report(
            providers: [provider(name: "Claude", windows: [window(percent: 80, elapsedPercent: 50)])],
            date: now
        )
        var failed = Provider(name: "Claude")
        failed.loggedIn = true
        failed.error = "stored token went stale — run claude once"
        failed.staleToken = true
        let later = now.addingTimeInterval(300)
        let carried = Report(providers: [failed], date: later).carryingOver(from: good, now: later)
        check(carried.providers[0].ok, "the last reading must still show")
        check(carried.providers[0].staleToken, "the stale-token flag must survive the carry")
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

    private static func testClaudeKeychainServiceDerivation() {
        check(
            ClaudeProfile.keychainService(for: ClaudeProfile.defaultNormalizedPath)
                == ClaudeProfile.defaultKeychainService,
            "the default profile must keep the legacy Keychain service name"
        )
        let teamPath = "/Users/test/.claude-team"
        check(
            ClaudeProfile.keychainService(for: teamPath)
                == "Claude Code-credentials-\(ClaudeProfile.pathHashPrefix8(teamPath))",
            "non-default profiles must use the hashed service suffix"
        )
    }

    private static func testClaudePathNormalization() {
        check(
            ClaudeProfile.normalizedPath("~/foo/./bar/../baz")
                == (("~/foo/baz" as NSString).expandingTildeInPath),
            "normalization must expand ~ and drop . and .. without resolving symlinks"
        )
        let mixedCase = "/Users/Test/.Claude-Team"
        check(
            ClaudeProfile.normalizedPath(mixedCase) == mixedCase,
            "normalization must preserve path case"
        )
    }

    private static func testClaudeCatalogMerging() {
        let discovered = "/Users/test/.claude-work"
        let ignored = ClaudeProfile.normalizedPath(discovered)
        let withoutDefault = ClaudeProfile.catalog(
            configuredPaths: [],
            rememberedPaths: [],
            discoveredPaths: [],
            ignoredPaths: [ClaudeProfile.defaultNormalizedPath]
        )
        check(withoutDefault.isEmpty, "removing the default Claude profile must hide it from the catalog")
        var catalog = ClaudeProfile.catalog(
            configuredPaths: [discovered],
            rememberedPaths: [],
            discoveredPaths: [discovered],
            ignoredPaths: [ignored]
        )
        check(
            !catalog.contains(where: { $0.normalizedPath == ignored }),
            "ignored paths must stay out until the user adds them again"
        )
        catalog = ClaudeProfile.catalog(
            configuredPaths: [discovered],
            rememberedPaths: [],
            discoveredPaths: [],
            ignoredPaths: []
        )
        check(catalog.count >= 2, "default and configured profiles must both appear")
    }

    private static func testClaudeDefaultLabels() {
        check(
            ClaudeProfile.defaultLabel(subscriptionType: "max", customLabel: nil, profilePath: "/x")
                == "Claude Personal",
            "personal plans must default to Claude Personal"
        )
        check(
            ClaudeProfile.defaultLabel(subscriptionType: "team", customLabel: nil, profilePath: "/x")
                == "Claude Team",
            "team plans must default to Claude Team"
        )
        check(
            ClaudeProfile.defaultLabel(subscriptionType: "team", customLabel: "Work", profilePath: "/x")
                == "Work",
            "a custom label must win over subscription defaults"
        )
    }

    private static func testClaudeLegacyProviderDecoding() {
        let json = """
        {"name":"Claude","ok":true,"windows":[{"label":"5h","percent":40}]}
        """
        guard let provider = try? JSONDecoder().decode(Provider.self, from: Data(json.utf8)) else {
            check(false, "legacy provider JSON must decode")
            return
        }
        check(provider.id == ClaudeProfile.defaultKeychainService, "legacy Claude rows must map to the default profile id")
        check(provider.kind == "claude", "legacy Claude rows must gain the claude kind")
    }

    private static func testClaudeDuplicateTokenCollapse() {
        let personal = ClaudeProfile.Entry(
            normalizedPath: ClaudeProfile.defaultNormalizedPath,
            keychainService: ClaudeProfile.defaultKeychainService,
            source: .default,
            preferenceRank: 2
        )
        let teamPath = "/Users/test/.claude-team"
        let team = ClaudeProfile.Entry(
            normalizedPath: teamPath,
            keychainService: ClaudeProfile.keychainService(for: teamPath),
            source: .configured,
            preferenceRank: 1
        )
        let token = "same-access-token"
        let collapsed = ClaudeProfile.collapseDuplicateTokens([team, personal]) { _ in
            ClaudeProfile.OAuthSnapshot(accessToken: token, subscriptionType: "team", expiresAtMs: nil)
        }
        check(collapsed.count == 1, "duplicate access tokens must collapse to one profile")
        check(
            collapsed[0].normalizedPath == personal.normalizedPath,
            "the default profile must win an otherwise equal duplicate-token tie"
        )
    }

    private static func testClaudeConfigDirFromEnvironment() {
        let processList = """
        123 /Users/me/.local/bin/claude chat
        456 node /path/to/claude-code/cli.js
        789 /Users/me/.local/bin/claude --chrome-native-host
        """
        check(ClaudeCredential.claudePIDs(in: processList) == [123, 456], "Claude Code processes must be detected")
        let environment = "PATH=/usr/bin CLAUDE_CONFIG_DIR=/Users/me/.claude-team OTHER=x"
        check(
            ClaudeCredential.configDir(inProcessEnvironment: environment)
                == ClaudeProfile.normalizedPath("/Users/me/.claude-team"),
            "CLAUDE_CONFIG_DIR must be parsed and normalized"
        )
    }

    private static func testCodexProfileIDsAndPaths() {
        check(
            CodexProfile.providerID(for: CodexProfile.defaultNormalizedPath) == "Codex",
            "the default Codex profile must preserve its legacy provider id"
        )
        let work = CodexProfile.normalizedPath("~/work/../.codex-work")
        check(work.hasSuffix("/.codex-work"), "Codex paths must expand and normalize without resolving symlinks")
        check(
            CodexProfile.providerID(for: work).hasPrefix(CodexProfile.idPrefix),
            "a non-default Codex profile must receive a path-derived id"
        )
        check(
            CodexProfile.providerID(for: work) == CodexProfile.providerID(for: work),
            "a Codex profile id must be stable"
        )
    }

    private static func testCodexCatalogMerging() {
        let work = "/Users/test/.codex-work"
        let withoutDefault = CodexProfile.catalog(
            configuredPaths: [],
            rememberedPaths: [],
            discoveredPaths: [],
            ignoredPaths: [CodexProfile.defaultNormalizedPath]
        )
        check(withoutDefault.isEmpty, "removing the default Codex profile must hide it from the catalog")
        var catalog = CodexProfile.catalog(
            configuredPaths: [work],
            rememberedPaths: [],
            discoveredPaths: [work],
            ignoredPaths: [work]
        )
        check(catalog.count == 1, "an ignored Codex profile must stay out while the default remains")
        catalog = CodexProfile.catalog(
            configuredPaths: [work],
            rememberedPaths: [work],
            discoveredPaths: [work],
            ignoredPaths: []
        )
        check(catalog.count == 2, "default and configured Codex profiles must merge without duplicates")
        check(catalog[0].providerID == CodexProfile.defaultID, "the default Codex profile must stay first")
    }

    private static func testCodexDefaultLabels() {
        check(
            CodexProfile.defaultLabel(planType: "pro", customLabel: nil, profilePath: "/x")
                == "Codex Personal",
            "personal Codex plans must use the personal label"
        )
        check(
            CodexProfile.defaultLabel(planType: "business", customLabel: nil, profilePath: "/x")
                == "Codex Team",
            "business Codex plans must use the team label"
        )
        check(
            CodexProfile.defaultLabel(planType: "team", customLabel: "Client", profilePath: "/x")
                == "Client",
            "a custom Codex label must win over the plan default"
        )
    }

    private static func testCodexAuthParsingAndDuplicateCollapse() {
        let fixture = Data(#"{"tokens":{"access_token":"same-token","account_id":"acct_1"}}"#.utf8)
        let auth = CodexProfile.parseAuth(fixture)
        check(auth?.accountID == "acct_1", "Codex auth.json account ids must be parsed")

        let personal = CodexProfile.Entry(
            normalizedPath: CodexProfile.defaultNormalizedPath,
            providerID: CodexProfile.defaultID,
            source: .default,
            preferenceRank: 2
        )
        let workPath = "/Users/test/.codex-work"
        let work = CodexProfile.Entry(
            normalizedPath: workPath,
            providerID: CodexProfile.providerID(for: workPath),
            source: .configured,
            preferenceRank: 1
        )
        let collapsed = CodexProfile.collapseDuplicateTokens([work, personal]) { _ in auth }
        check(collapsed == [personal], "the default Codex profile must win duplicate credentials")
    }

    private static func testCodexHomeFromEnvironment() {
        let processList = """
        123 /opt/homebrew/bin/codex exec
        456 node /usr/local/lib/node_modules/@openai/codex/bin/codex.js
        789 /usr/bin/not-codex-helper
        """
        check(CodexCredential.codexPIDs(in: processList) == [123, 456], "Codex CLI processes must be detected")
        let environment = "PATH=/usr/bin CODEX_HOME=/Users/me/.codex-work OTHER=x"
        check(
            CodexCredential.home(inProcessEnvironment: environment)
                == CodexProfile.normalizedPath("/Users/me/.codex-work"),
            "CODEX_HOME must be parsed and normalized"
        )
    }

    private static func testMultipleCodexPollTargetOrdering() {
        let defaultCodex = CodexProfile.Entry(
            normalizedPath: CodexProfile.defaultNormalizedPath,
            providerID: CodexProfile.defaultID,
            source: .default,
            preferenceRank: 2
        )
        let workPath = "/Users/test/.codex-work"
        let workCodex = CodexProfile.Entry(
            normalizedPath: workPath,
            providerID: CodexProfile.providerID(for: workPath),
            source: .configured,
            preferenceRank: 1
        )
        let ids = Fetcher.pollTargetIDs(claudeTargets: [], codexTargets: [defaultCodex, workCodex])
        check(
            ids == [defaultCodex.id, workCodex.id, Fetcher.openCodeGoID, Fetcher.openRouterID, Fetcher.cursorID],
            "both Codex profiles must be independent poll targets in profile order"
        )
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
