import Foundation

/// Usage-alert decisions and acknowledgements, independent of macOS delivery.
enum UsageAlerts {
    /// Pace comparisons are too noisy at the start of a quota window.
    static let quietTargetPercent: Double = 10

    enum Kind {
        case usage
        case offTrack
        case wayOffTrack
    }

    struct Mark: Codable {
        var resetsAt: Int?
        var usageSent = false
        var paceSent = false
        // Optional so existing saved marks still decode after an upgrade.
        var severePaceSent: Bool?
        var lastPercent: Double?
        var resetAnnounced: Bool?

        /// Claude reports the same weekly reset as 11:59:59 on one poll and
        /// 12:00:00 on the next. A move of under an hour is that jitter, not a
        /// new window, and must not re-arm alerts already sent.
        func sameWindow(as resetsAt: Int?) -> Bool {
            guard let old = self.resetsAt, let new = resetsAt else { return self.resetsAt == resetsAt }
            return abs(new - old) < 3600
        }

        mutating func advance(to resetsAt: Int?) {
            if !sameWindow(as: resetsAt) { self = Mark(resetsAt: resetsAt) }
        }

        /// The flat usage threshold is only worth saying while spending is
        /// ahead of an even burn: 61% of the week on Friday is on track.
        func usageAlert(for window: UsageWindow, threshold: Double, timing: Pace.Timing) -> Bool {
            guard !usageSent, window.percent >= threshold else { return false }
            guard let target = Pace.targetPercent(window, timing: timing) else { return true }
            return window.percent > target
        }

        /// Called only after macOS accepts the notification request.
        mutating func acknowledge(_ kind: Kind) {
            switch kind {
            case .usage: usageSent = true
            case .offTrack: paceSent = true
            case .wayOffTrack:
                paceSent = true
                severePaceSent = true
            }
        }

        func paceAlert(
            for window: UsageWindow,
            threshold: Double,
            timing: Pace.Timing
        ) -> Kind? {
            // Both stages stay quiet through the first 10% of the active time
            // basis, even when a small target makes the burn ratio enormous.
            // Quota consumed is a separate floor, not a measure of elapsed time.
            guard window.percent >= 10,
                  let target = Pace.targetPercent(window, timing: timing),
                  target > quietTargetPercent
            else { return nil }
            let ratio = window.percent / target

            if ratio > max(3, threshold * 2) {
                return severePaceSent == true ? nil : .wayOffTrack
            }
            if ratio > threshold, !paceSent { return .offTrack }
            return nil
        }
    }
}
