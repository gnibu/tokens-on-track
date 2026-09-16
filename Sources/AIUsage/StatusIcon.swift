import AppKit
import SwiftUI

/// The menu bar glyph: one segment per window worth watching, worst first.
/// A segment is up to three parts — the provider mark, a ring filled to that
/// window's consumption, and the percentage — and the user picks which of the
/// three to show.
///
/// Drawn rather than composed from SF Symbols because the tint is the whole
/// point, and a template image would throw the colour away.
enum StatusIcon {
    struct Segment {
        /// Names the provider, so the mark can be looked up.
        var provider: String
        /// The window's own label, of which only the first letter is drawn.
        var window: String = ""
        /// Fills the ring. Always the share of the budget spent, whichever
        /// reading the text beside it quotes — a ring needs a number with an
        /// end to it, and a pace rate has none.
        var percent: Double?
        /// The percentage as printed, already formatted by `Pace.reading` so
        /// that the icon has no say in which of the two readings it is.
        var text: String?
        var color: Color
    }

    /// Which parts of a segment to draw. Never empty — the settings pane keeps
    /// the last enabled part switched on.
    struct Parts: OptionSet {
        let rawValue: Int

        static let mark = Parts(rawValue: 1 << 0)
        static let gauge = Parts(rawValue: 1 << 1)
        static let percent = Parts(rawValue: 1 << 2)
        /// Rides inside the gauge, so it costs no width and means nothing
        /// without it.
        static let window = Parts(rawValue: 1 << 3)

        static let all: Parts = [.mark, .gauge, .percent, .window]
    }

    private static let height: CGFloat = 18
    private static let mark: CGFloat = 13
    /// As wide as the bar can take, to leave the window initial inside it as
    /// much room as possible.
    private static let ring: CGFloat = 16
    private static let partGap: CGFloat = 3
    private static let segmentGap: CGFloat = 7
    private static let lineWidth: CGFloat = 2

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.labelColor,
    ]

    private static let monogramAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor.labelColor,
    ]

    /// Sized to clear the ring's stroke on both sides, and bold because on a
    /// display without a HiDPI backing store this is five pixels tall.
    ///
    /// Full `labelColor`, exactly as the percentage: it has to carry at five
    /// pixels, and anything dimmer is the first thing to disappear. Note that
    /// `labelColor` must be used *as is* — running it through
    /// `withAlphaComponent` resolves the dynamic colour against whichever
    /// appearance happens to be current, which for a stored attribute is the
    /// light one, and the letter then vanishes into a dark menu bar.
    private static let windowAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .bold),
        .foregroundColor: NSColor.labelColor,
    ]

    static func image(segments: [Segment], parts: Parts = .all) -> NSImage {
        // An empty reading still needs something clickable in the menu bar.
        let drawn = segments.isEmpty ? [placeholder] : segments

        // Whatever is asked for, the item has to end up with some width. An
        // empty part set has nothing to draw, and so does a logo-only item
        // whose segment has no provider to name — which is exactly what an
        // empty reading is. Either way the app has no Dock tile, so a
        // zero-width item would leave no way back to the settings or to Quit.
        var parts = parts.isEmpty ? .gauge : parts
        if drawn.allSatisfy({ width(of: $0, parts: parts) <= 0 }) {
            parts.insert(.gauge)
        }

        let widths = drawn.map { width(of: $0, parts: parts) }
        let total = widths.reduce(0, +) + segmentGap * CGFloat(drawn.count - 1)

        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (segment, width) in zip(drawn, widths) {
                draw(segment, parts: parts, atX: x)
                x += width + segmentGap
            }
            return true
        }
        // The ring is meaningful in colour, so it must not be tinted by the bar.
        image.isTemplate = false
        return image
    }

    private static var placeholder: Segment {
        Segment(provider: "", percent: nil, color: .secondary)
    }

    // ----------------------------------------------------------------- //

    private static func width(of segment: Segment, parts: Parts) -> CGFloat {
        var widths: [CGFloat] = []
        if parts.contains(.mark), !segment.provider.isEmpty {
            widths.append(markWidth(for: segment.provider))
        }
        if parts.contains(.gauge) {
            widths.append(ring)
        }
        if parts.contains(.percent) {
            widths.append(ceil(label(for: segment).size(withAttributes: textAttributes).width))
        }
        return widths.reduce(0, +) + partGap * CGFloat(max(0, widths.count - 1))
    }

    private static func draw(_ segment: Segment, parts: Parts, atX origin: CGFloat) {
        var x = origin
        var drawn = false
        func space() {
            if drawn { x += partGap }
            drawn = true
        }

        if parts.contains(.mark), !segment.provider.isEmpty {
            space()
            drawMark(segment.provider, atX: x)
            x += markWidth(for: segment.provider)
        }

        if parts.contains(.gauge) {
            space()
            drawRing(percent: segment.percent, color: segment.color, atX: x)
            if parts.contains(.window) {
                drawWindowInitial(segment.window, atX: x)
            }
            x += ring
        }

        if parts.contains(.percent) {
            space()
            let text = label(for: segment)
            let size = text.size(withAttributes: textAttributes)
            text.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: textAttributes)
        }
    }

    /// Monochrome and to scale — see the trademark note on `BrandGlyph`. A
    /// provider with no mark on file falls back to its initial.
    private static func drawMark(_ provider: String, atX x: CGFloat) {
        let width = markWidth(for: provider)
        let box = NSSize(width: width, height: mark)
        NSColor.labelColor.setFill()

        if let path = BrandGlyph.path(for: provider, fitting: box) {
            path.transform(using: AffineTransform(translationByX: x, byY: (height - mark) / 2))
            path.fill()
            return
        }

        let initial = String(provider.prefix(1)).uppercased() as NSString
        let size = initial.size(withAttributes: monogramAttributes)
        initial.draw(
            at: NSPoint(x: x + (width - size.width) / 2, y: (height - size.height) / 2),
            withAttributes: monogramAttributes
        )
    }

    private static func markWidth(for provider: String) -> CGFloat {
        BrandGlyph.width(for: provider, height: mark)
    }

    /// One letter in the hole of the ring, which is the only space a menu bar
    /// item has going spare: `5h` and `week` are otherwise indistinguishable
    /// once both of a provider's windows are on show. Digits are skipped so
    /// that `5h` reads as `h` rather than as `5`.
    static func windowInitial(_ window: String) -> String? {
        guard let initial = window.first(where: \.isLetter) else { return nil }
        return String(initial).lowercased()
    }

    private static func drawWindowInitial(_ window: String, atX x: CGFloat) {
        guard let initial = windowInitial(window) else { return }
        let attributes = windowAttributes
        let text = initial as NSString
        let size = text.size(withAttributes: attributes)
        // Rounded, so a five-pixel letter lands on the pixel grid rather than
        // straddling it and blurring away to nothing.
        text.draw(
            at: NSPoint(
                x: (x + (ring - size.width) / 2).rounded(),
                y: ((height - size.height) / 2).rounded()
            ),
            withAttributes: attributes
        )
    }

    private static func drawRing(percent: Double?, color: Color, atX x: CGFloat) {
        let center = NSPoint(x: x + ring / 2, y: height / 2)
        let radius = (ring - lineWidth) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        track.stroke()

        guard let percent else { return }
        let fraction = min(1, max(0, percent / 100))
        guard fraction > 0 else { return }

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * fraction,
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor(color).setStroke()
        arc.stroke()
    }

    private static func label(for segment: Segment) -> NSString {
        (segment.text ?? "--") as NSString
    }
}
