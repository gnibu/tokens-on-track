import Foundation
import UserNotifications

/// Fires one usage alert and two escalating pace alerts per window *instance*. The
/// bookkeeping is keyed on the window's reset time, so the moment a window
/// rolls over the slate is wiped and the next crossing is announced again.
@MainActor
enum Notifier {
    private typealias Mark = UsageAlerts.Mark

    private static let stateKey = "notificationMarks"
    private static let creditsKey = "resetCreditCounts"
    private static var pending: Set<String> = []
    private static let delegate = NotificationDelegate()

    /// UNUserNotificationCenter traps when there is no bundle around it, which
    /// is exactly the case when the raw SwiftPM binary is run for debugging.
    private static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("ai-usage: notification authorization failed: \(error)")
            } else if !granted {
                NSLog("ai-usage: notifications are not allowed; enable Tokens on Track in System Settings > Notifications")
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
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized,
                  settings.alertSetting == .enabled else { return }
            evaluateAuthorized(report, preferences: preferences, evaluateUsage: evaluateUsage)
        }
    }

    private static func evaluateAuthorized(
        _ report: Report,
        preferences: Preferences,
        evaluateUsage: Bool
    ) {
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
        var creditCounts = loadCreditCounts()
        let now = Int(Date().timeIntervalSince1970)
        for provider in watched where provider.ok && !provider.stale {
            var cleared: [String] = []
            for window in provider.windows {
                // Keep providers' full structured model names in alert
                // identity even when two compact labels happen to match.
                let key = "\(provider.id)/\(window.id)"
                let previous = marks[key]
                var mark = previous ?? Mark(resetsAt: window.resetsAt)

                // Judged against the window as last seen, before the mark is
                // wiped below. Only a fresh reading can say a quota cleared.
                var announced = false
                if evaluateUsage,
                   let previous,
                   previous.resetAnnounced != true,
                   ResetWatch.quotaCleared(
                       previousResetsAt: previous.resetsAt,
                       previousPercent: previous.lastPercent,
                       window: window,
                       now: now
                   ) {
                    announced = true
                    if preferences.resetAlertsEnabled { cleared.append(window.label) }
                }

                // A new reset instant means a new window: forget what we said.
                if !mark.sameWindow(as: window.resetsAt) {
                    mark.advance(to: window.resetsAt)
                } else if announced {
                    // Said when the reset time passed; the provider reporting
                    // the next window later must not say it again.
                    mark.resetAnnounced = true
                }
                if evaluateUsage { mark.lastPercent = window.percent }

                if evaluateUsage,
                   preferences.usageAlertsEnabled,
                   mark.usageAlert(for: window, threshold: preferences.usageThreshold, timing: timing) {
                    post(
                        title: "\(provider.name) \(window.label) at \(Int(window.percent.rounded()))%",
                        body: "Resets \(Pace.resetLabel(window.resetsAt)).",
                        id: "\(key)/usage/\(mark.resetsAt ?? 0)"
                    ) {
                        acknowledge(.usage, key: key, resetsAt: window.resetsAt)
                    }
                }

                if preferences.paceAlertsEnabled,
                   let kind = mark.paceAlert(for: window, threshold: preferences.paceThreshold, timing: timing),
                   let target = Pace.targetPercent(window, timing: timing) {
                    let severe = kind == .wayOffTrack
                    let stage = severe ? "way off track" : "off track"
                    post(
                        title: "\(provider.name) \(window.label) \(stage)",
                        body: String(
                            format: "%.0f%% used; %.0f%% remaining. %.1f× target (%.0f%% expected). Resets %@.",
                            window.percent, max(0, 100 - window.percent), window.percent / target,
                            target, Pace.resetLabel(window.resetsAt)
                        ),
                        id: "\(key)/\(severe ? "severe-pace" : "pace")/\(mark.resetsAt ?? 0)"
                    ) {
                        acknowledge(kind, key: key, resetsAt: window.resetsAt)
                    }
                }

                marks[key] = mark
            }

            if !cleared.isEmpty {
                post(
                    title: cleared.count == 1
                        ? "\(provider.name) \(cleared[0]) limit reset"
                        : "\(provider.name) limits reset",
                    body: cleared.count == 1
                        ? "Full quota available again."
                        : "\(cleared.joined(separator: ", ")) — full quota available again.",
                    id: "\(provider.id)/reset/\(now)"
                )
            }

            if evaluateUsage, let credits = provider.resetCredits {
                let arrived = ResetWatch.newCredits(previous: creditCounts[provider.id], current: credits)
                if arrived > 0, preferences.resetAlertsEnabled {
                    let total = credits.available == 1 ? "1 reset" : "\(credits.available) resets"
                    post(
                        title: arrived == 1
                            ? "\(provider.name): new reset credit"
                            : "\(provider.name): \(arrived) new reset credits",
                        body: "\(total) available. Click the ↺ badge in Tokens on Track to use one when you hit a limit.",
                        id: "\(provider.id)/credit/\(now)"
                    )
                }
                creditCounts[provider.id] = credits.available
            }
        }

        saveMarks(marks)
        UserDefaults.standard.set(creditCounts, forKey: creditsKey)
    }

    private static func loadCreditCounts() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: creditsKey) as? [String: Int]) ?? [:]
    }

    private static func acknowledge(_ kind: UsageAlerts.Kind, key: String, resetsAt: Int?) {
        var marks = loadMarks()
        // A late completion must not acknowledge a different quota window or
        // overwrite another notification's successful acknowledgement.
        guard var mark = marks[key], mark.sameWindow(as: resetsAt) else { return }
        mark.acknowledge(kind)
        marks[key] = mark
        saveMarks(marks)
    }

    private static func post(title: String, body: String, id: String, onSuccess: (() -> Void)? = nil) {
        guard pending.insert(id).inserted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                pending.remove(id)
                if let error {
                    NSLog("ai-usage: notification delivery failed: \(error)")
                } else {
                    onSuccess?()
                }
            }
        }
    }

    private static func loadMarks() -> [String: Mark] {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let marks = try? JSONDecoder().decode([String: Mark].self, from: data)
        else { return [:] }
        // Keys were `Claude/…` before providers had stable ids; carry them to
        // the default profile's id so an upgrade does not repeat an alert.
        let legacy = "Claude/"
        let current = ClaudeProfile.defaultKeychainService + "/"
        return Dictionary(marks.map { key, mark in
            key.hasPrefix(legacy) ? (current + String(key.dropFirst(legacy.count)), mark) : (key, mark)
        }, uniquingKeysWith: { new, _ in new })
    }

    private static func saveMarks(_ marks: [String: Mark]) {
        guard let data = try? JSONEncoder().encode(marks) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}

/// Keep alerts visible even when the menu bar app owns the foreground panel.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
