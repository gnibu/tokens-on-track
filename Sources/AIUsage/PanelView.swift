import AppKit
import SwiftUI

/// Usage stays in the dropdown; configuration opens in a regular window.
struct PanelView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("TOKENS ON TRACK")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(1.2)
                    .foregroundStyle(Glass.ink(0.6))
                Spacer(minLength: 4)
                GlassButton(
                    label: "", systemImage: "arrow.clockwise",
                    enabled: !store.isRefreshing, spinning: store.isRefreshing
                ) { Task { await store.refresh() } }
                .help("Refresh now")
                .accessibilityLabel("Refresh now")
                GlassButton(label: "", systemImage: "gearshape") {
                    MenuBarItem.shared.showSettings()
                }
                .help("Settings…")
                .accessibilityLabel("Open Settings")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            HStack(spacing: 6) {
                if store.isOffline { GlassSpinner(size: 11) }
                Text(usageStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.ink(0.4))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)

            MenuUsageView()
                .padding(EdgeInsets(top: 4, leading: 18, bottom: 18, trailing: 18))

            HStack {
                Spacer()
                GlassLink(title: "Quit") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .frame(width: 430)
        .glassPane(radius: Glass.panelRadius, dim: 0.75, tone: 0.7, shadow: false)
        .environment(\.colorScheme, .dark)
        .onAppear { store.refreshIfStale(olderThan: 300) }
    }

    private var usageStatusText: String {
        let every = store.retryCadenceLabel
        guard let report = store.report else { return "No reading yet · retrying \(every)" }
        if store.isRefreshing { return "Refreshing… · \(every)" }
        if report.hasNoReading { return "No reading yet · retrying \(every)" }
        let stale = report.isStale ? " (stale)" : ""
        return "Updated \(report.updatedLabel)\(stale) · \(every)"
    }
}
