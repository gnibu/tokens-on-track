import SwiftUI

/// The reading itself. Two densities of the same content: the roomy one the
/// desktop card uses, and the tighter one that fits the dropdown's Usage tab.
/// Both are driven by the same rows so the two can never drift apart.

/// Column widths and type sizes — the only difference between the two.
struct RowMetrics {
    let label: CGFloat
    let percent: CGFloat
    let reset: CGFloat
    let trackHeight: CGFloat
    let gap: CGFloat
    let labelSize: CGFloat
    let percentSize: CGFloat
    let resetSize: CGFloat
    /// The provider mark beside the name, sized to the cap height of the name
    /// rather than to its point size, so it reads as a sibling of the word.
    let markSize: CGFloat
    let glows: Bool

    static let card = RowMetrics(
        label: 112, percent: 46, reset: 88, trackHeight: 10, gap: 12,
        labelSize: 14, percentSize: 14, resetSize: 12, markSize: 16, glows: true
    )

    // Leave room for a scoped model label such as "week (Fable)".
    static let menu = RowMetrics(
        label: 112, percent: 38, reset: 70, trackHeight: 8, gap: 10,
        labelSize: 12, percentSize: 12, resetSize: 11, markSize: 14, glows: false
    )
}

private func providerShowsCost(_ provider: Provider, preferences: Preferences) -> Bool {
    switch provider.kind {
    case "cursor": return preferences.showCursorCosts
    case "openrouter": return preferences.showOpenRouterCosts
    default: return false
    }
}

// --------------------------------------------------------------------- //

/// 1a — the free-standing glass card: summary line, hairline, then a block per
/// provider with the word for how that provider on its own is doing.
struct DesktopUsageCard: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared
    var timing: Pace.Timing?

    var body: some View {
        let timing = timing ?? Pace.Timing(schedule: preferences.workSchedule)
        let display = store.report?.displaying(
            hiding: preferences.hiddenProviders,
            hidingModels: preferences.hiddenModelLimits
        )
        let verdict = Pace.verdict(display, mode: preferences.percentMode, timing: timing)
        let shown = display?.providers ?? []
        // A provider with nothing to draw is named once by `OutageNotice`
        // above; an empty block under it only repeats that. So the blocks are
        // the providers with a reading, and a carried one still counts.
        let blocks = shown.filter(\.hasVisibleReading)
        let noReading = display?.hasNoReading ?? false
        let retrying = noReading || (display?.needsFastRetry ?? false)

        VStack(alignment: .leading, spacing: 18) {
            header(verdict, noReading: noReading)

            OutageNotice(providers: shown, size: 12)

            if retrying {
                RetryNotice(size: 12)
            }

            Glass.hairline

            if !blocks.isEmpty {
                ForEach(blocks) { provider in
                    ProviderBlock(
                        provider: provider,
                        metrics: .card,
                        mode: preferences.percentMode,
                        timing: timing,
                        showsCost: providerShowsCost(provider, preferences: preferences),
                        worstRow: verdict.rowKey
                    )
                }
            } else if shown.isEmpty {
                Text(store.isRefreshing ? "fetching…" : "no data yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.ink(0.5))
            }
        }
    }

    private func header(_ verdict: Pace.Verdict, noReading: Bool) -> some View {
        HStack(spacing: 12) {
            UsageRing(
                percent: verdict.percent,
                color: verdict.color,
                target: verdict.target,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.source.map { "WORST — \($0.uppercased())" } ?? "TOKENS ON TRACK")
                    .font(.system(size: 11, weight: .regular))
                    .kerning(1.4)
                    .foregroundStyle(Glass.ink(0.5))
                Text(verdict.line)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(verdict.hot ? Color(red: 1, green: 0.788, blue: 0.788) : .white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(store.report?.updatedLabel ?? "--:--")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Glass.ink(0.7))
                Text(statusText(noReading: noReading))
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.ink(0.4))
            }
            .fixedSize()

            GlassButton(
                label: "",
                systemImage: "arrow.clockwise",
                enabled: !store.isRefreshing,
                spinning: store.isRefreshing
            ) {
                Task { await store.refresh() }
            }
            .help("Refresh now")
        }
    }

    /// The second line of the clock column. "just now" is when the poll ran, not
    /// when a reading landed, so a failed poll says so instead of claiming a
    /// freshness the card cannot back up.
    private func statusText(noReading: Bool) -> String {
        if store.isRefreshing { return "refreshing…" }
        if noReading { return "retrying…" }
        return store.report?.ageLabel() ?? "never"
    }
}

// --------------------------------------------------------------------- //

/// 1b — the Usage tab: one summary pill, then the same rows a size down.
struct MenuUsageView: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        let timing = Pace.Timing(schedule: preferences.workSchedule)
        let display = store.report?.displaying(
            hiding: preferences.hiddenProviders,
            hidingModels: preferences.hiddenModelLimits
        )
        let verdict = Pace.verdict(display, mode: preferences.percentMode, timing: timing)
        let shown = display?.providers ?? []
        let blocks = shown.filter(\.hasVisibleReading)

        VStack(alignment: .leading, spacing: 16) {
            summary(verdict)

            OutageNotice(providers: shown, size: 11)

            if !blocks.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(blocks) { provider in
                        ProviderBlock(
                            provider: provider,
                            metrics: .menu,
                            mode: preferences.percentMode,
                            timing: timing,
                            showsNote: false,
                            showsCost: providerShowsCost(provider, preferences: preferences),
                            worstRow: verdict.rowKey
                        )
                    }
                }
            } else if shown.isEmpty {
                Text(store.isRefreshing ? "fetching…" : "no data yet")
                    .font(.system(size: 12))
                    .foregroundStyle(Glass.ink(0.5))
            }
        }
    }

    private func summary(_ verdict: Pace.Verdict) -> some View {
        HStack(spacing: 12) {
            UsageRing(
                percent: verdict.percent,
                color: verdict.color,
                target: verdict.target,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verdict.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Glass.ink(0.5))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .fill(Color.white.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// --------------------------------------------------------------------- //

/// Why a provider has no reading, said once for the whole card and in amber
/// rather than red: a missed poll is a gap in what we know, not a warning about
/// spending, and the rows below still say everything we do know.
struct OutageNotice: View {
    /// Already filtered to what the surface draws — a hidden or never-set-up
    /// provider is not reported as an outage.
    let providers: [Provider]
    let size: CGFloat

    var body: some View {
        let down = providers.filter { !$0.ok || $0.stale }

        if !down.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(down) { provider in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: size))
                        Text(Self.line(provider))
                            .font(.system(size: size))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(Pace.warn.opacity(0.92))
        }
    }

    /// A stale provider still has rows below, so the notice has to say which
    /// reading those rows are — otherwise the numbers look current.
    static func line(_ provider: Provider) -> String {
        let reason = outageReason(provider)
        // Only name the reading's age when its rows are actually on screen; a
        // stale-and-empty provider shows "no recent reading" instead of rows, so
        // "· rows from …" would point at nothing.
        guard provider.stale, provider.hasVisibleReading, let measured = provider.measuredAt else {
            return "\(provider.name): \(reason)"
        }
        return "\(provider.name): \(reason) · rows from \(Pace.clockLabel(measured))"
    }

    /// What went wrong, in the reader's terms. A vanished transient Conductor
    /// key gets an actionable route to the reliable credential field.
    private static func outageReason(_ provider: Provider) -> String {
        if let reconnect = OpenRouterCredential.reconnectMessage(for: provider) { return reconnect }
        if let reconnect = CursorCredential.reconnectMessage(for: provider) { return reconnect }
        return provider.error ?? "no reading"
    }
}

// --------------------------------------------------------------------- //

/// A poll has run and nothing landed. Rather than let the empty card read as a
/// dead end, one line says the app keeps asking by itself — the refresh button
/// beside it is for retrying now rather than waiting out the interval.
struct RetryNotice: View {
    @EnvironmentObject private var store: UsageStore
    let size: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            GlassSpinner(size: size + 1)
            Text("Retrying automatically \(store.retryCadenceLabel)")
                .font(.system(size: size))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Glass.ink(0.55))
    }
}

// --------------------------------------------------------------------- //

struct ProviderBlock: View {
    let provider: Provider
    let metrics: RowMetrics
    /// Which reading the percentage column quotes. Passed down rather than read
    /// from `Preferences` here, so one observer at the top of each surface
    /// redraws the whole list.
    var mode: Pace.PercentMode = .budget
    var timing = Pace.Timing()
    var showsNote: Bool = true
    var showsCost: Bool = false
    /// The row the summary above is speaking for, marked here so the reader can
    /// trace the ring back to the window it came from.
    var worstRow: String? = nil

    /// Rows sit under the provider name, not under the mark — icon + gap from the header.
    private var rowLeadingInset: CGFloat {
        BrandGlyph.width(for: provider.kind, height: metrics.markSize) + 9
    }

    var body: some View {
        let note = Pace.note(provider, timing: timing)

        VStack(alignment: .leading, spacing: metrics.trackHeight == 10 ? 10 : 9) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                BrandMark(provider: provider.kind, size: metrics.markSize)
                    // Marks are centred on their own box, names sit on a
                    // baseline; aligning the two by eye keeps the row level.
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - metrics.markSize * 0.14 }

                Text(provider.name)
                    .font(.system(size: metrics.labelSize + 3, weight: .semibold))
                    .foregroundStyle(.white)

                if let plan = provider.plan, !plan.isEmpty {
                    planBadge(plan)
                }

                Spacer(minLength: 6)

                if showsNote, let note {
                    Text(note.text)
                        .font(.system(size: 12))
                        .foregroundStyle(note.color)
                }
            }

            // Only providers with a reading reach here: one with nothing to
            // draw is named once by `OutageNotice` instead of getting an empty
            // block of its own. Carried rows are dimmed, so they cannot be
            // mistaken for numbers just measured.
            VStack(alignment: .leading, spacing: metrics.trackHeight == 10 ? 10 : 9) {
                ForEach(provider.windows) { window in
                    UsageRow(
                        window: window,
                        metrics: metrics,
                        mode: mode,
                        timing: timing,
                        showsCost: showsCost,
                        isWorst: worstRow == Report.rowKey(provider: provider, window: window),
                        dimmed: provider.stale
                    )
                }
            }
            .padding(.leading, rowLeadingInset)
        }
    }

    @ViewBuilder
    private func planBadge(_ plan: String) -> some View {
        let text = Text(plan.uppercased())
            .font(.system(size: metrics.labelSize == 14 ? 11 : 10, weight: .semibold))
            .kerning(1)

        if showsNote {
            text
                .foregroundStyle(Glass.ink(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
        } else {
            text.foregroundStyle(Glass.ink(0.5))
        }
    }
}

/// The provider mark beside its name, drawn from the same outline the menu bar
/// uses. Monochrome and uniformly scaled, per the trademark note on
/// `BrandGlyph` — pace colour stays on the track and the ring.
struct BrandMark: View {
    let provider: String
    let size: CGFloat
    var opacity: Double = 0.9

    var body: some View {
        let width = BrandGlyph.width(for: provider, height: size)

        Group {
            if let outline = BrandGlyph.path(
                for: provider,
                fitting: NSSize(width: width, height: size),
                flipped: false
            ) {
                // Even-odd, as the outline was parsed: the marks carry counters
                // a nonzero fill would flood.
                Path(outline.cgPath).fill(style: FillStyle(eoFill: true))
            } else {
                // The monogram the menu bar falls back to, at this size.
                Text(String(provider.prefix(1)).uppercased())
                    .font(.system(size: size * 0.78, weight: .semibold))
            }
        }
        .foregroundStyle(Glass.ink(opacity))
        .frame(width: width, height: size)
    }
}

struct UsageRow: View {
    let window: UsageWindow
    let metrics: RowMetrics
    var mode: Pace.PercentMode = .budget
    var timing = Pace.Timing()
    var showsCost: Bool = false
    var isWorst: Bool = false
    /// A carried reading: same type size as a live one, only quieter ink.
    var dimmed: Bool = false

    private func rowInk(_ level: Double) -> Color {
        Glass.ink(dimmed ? level * 0.55 : level)
    }

    var body: some View {
        let reading = Pace.reading(window, mode: mode, timing: timing)
        let cost = showsCost ? OpenRouterBudget.detail(for: window) : nil

        HStack(alignment: .firstTextBaseline, spacing: metrics.gap) {
            VStack(alignment: .leading, spacing: 1) {
                Text(window.label)
                    .font(.system(size: metrics.labelSize, weight: isWorst ? .semibold : .regular))
                    .foregroundStyle(rowInk(isWorst ? 0.95 : 0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                if let cost {
                    Text(cost)
                        .font(.system(size: max(8, metrics.labelSize - 4)))
                        .monospacedDigit()
                        .foregroundStyle(rowInk(0.4))
                        .lineLimit(1)
                }
            }
            .frame(width: metrics.label, alignment: .leading)

            UsageTrack(
                percent: window.percent,
                target: Pace.targetPercent(window, timing: timing),
                palette: Pace.palette(window, timing: timing),
                height: metrics.trackHeight,
                glows: metrics.glows,
                dimmed: dimmed
            )
            .alignmentGuide(.firstTextBaseline) { dimensions in
                // Sit the bar on the label's baseline like the figures beside it.
                dimensions[.bottom] - metrics.trackHeight * 0.55
            }

            // Dimmed when there is nothing to report and when the window is too
            // young to have a stable target comparison, so a dash reads as
            // "not yet" rather than as a reading in its own right.
            Text(reading.text)
                .font(.system(size: metrics.percentSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(rowInk(window.percent < 0.5 || !reading.hasValue ? 0.55 : 1))
                .frame(width: metrics.percent, alignment: .trailing)

            Text(Pace.resetLabel(window.resetsAt))
                .font(.system(size: metrics.resetSize, weight: .regular, design: .monospaced))
                .foregroundStyle(rowInk(0.45))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: metrics.reset, alignment: .trailing)
        }
    }
}
