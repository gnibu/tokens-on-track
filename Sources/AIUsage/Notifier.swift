import Foundation
import UserNotifications

/// Fires at most one usage alert and one pace alert per window *instance*. The
/// bookkeeping is keyed on the window's reset time, so the moment a window
/// rolls over the slate is wiped and the next crossing is announced again.
enum Notifier {
    private struct Mark: Codable {
        var resetsAt: Int?
        var usageSent = false
        var paceSent = false
    }

    private static let stateKey = "notificationMarks"

    /// UNUserNotificationCenter traps when there is no bundle around it, which
    /// is exactly the case when the raw SwiftPM binary is run for debugging.
    private static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("ai-usage: notification authorization failed: \(error)")
            }
        }
    }

    /// Compare a fresh report against what has already been announced.
    static func evaluate(
        _ report: Report,
        preferences: Preferences = .shared,
        evaluateUsage: Bool = true
    ) {
        guard isBundled else { return }
        var marks = loadMarks()
        let timing = Pace.Timing(schedule: preferences.workSchedule)

        // Carried-over numbers were already judged when they were fresh; a
        // stale provider must not be able to raise an alert twice. Hidden
        // providers and model-specific rows are left out here too, so nothing
        // off-screen can raise an alert.
        let watched = report.displayProviders(
            hiding: preferences.hiddenProviders,
            hidingModels: preferences.hiddenModelLimits
        )
        for provider in watched where provider.ok && !provider.stale {
            for window in provider.windows {
                // Keep providers' full structured model names in alert
                // identity even when two compact labels happen to match.
                let key = "\(provider.name)/\(window.id)"
                var mark = marks[key] ?? Mark(resetsAt: window.resetsAt)

                // A new reset instant means a new window: forget what we said.
                if mark.resetsAt != window.resetsAt {
                    mark = Mark(resetsAt: window.resetsAt)
                }

                if evaluateUsage,
                   preferences.usageAlertsEnabled,
                   !mark.usageSent,
                   window.percent >= preferences.usageThreshold {
                    mark.usageSent = true
                    post(
                        title: "\(provider.name) \(window.label) at \(Int(window.percent.rounded()))%",
                        body: "Resets \(Pace.resetLabel(window.resetsAt)).",
                        id: "\(key)/usage/\(window.resetsAt ?? 0)"
                    )
                }

                // Only worth saying once there is enough quota spent for the
                // ratio to be about behaviour rather than rounding.
                if preferences.paceAlertsEnabled,
                   !mark.paceSent,
                   window.percent >= 10,
                   let ratio = Pace.ratio(window, timing: timing),
                   ratio > preferences.paceThreshold {
                    mark.paceSent = true
                    post(
                        title: "\(provider.name) \(window.label) above target",
                        body: String(
                            format: "%.0f%% used at %.1f× target. Resets %@.",
                            window.percent, ratio, Pace.resetLabel(window.resetsAt)
                        ),
                        id: "\(key)/pace/\(window.resetsAt ?? 0)"
                    )
                }

                marks[key] = mark
            }
        }

        saveMarks(marks)
    }

    private static func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("ai-usage: notification delivery failed: \(error)")
            }
        }
    }

    private static func loadMarks() -> [String: Mark] {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let marks = try? JSONDecoder().decode([String: Mark].self, from: data)
        else { return [:] }
        return marks
    }

    private static func saveMarks(_ marks: [String: Mark]) {
        guard let data = try? JSONEncoder().encode(marks) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}
