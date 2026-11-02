import AppKit
import SwiftUI

/// Draws real rows off screen and reads the pixels, because what these pin
/// (where the bar lands, which ink a figure gets) only exists once rendered.
@MainActor
enum UsageRowRenderTests {
    private static let padding = 10
    private static let width = 380

    private struct Sample {
        let bitmap: NSBitmapImageRep
        let metrics: RowMetrics
        let background: Double

        var trackStart: Int { padding + Int(metrics.label + metrics.gap) }
        var figureEnd: Int { padding + width - Int(metrics.reset + metrics.gap) }
        var figureStart: Int { figureEnd - Int(metrics.percent) }
        var trackEnd: Int { figureStart - Int(metrics.gap) }

        func luminance(x: Int, y: Int) -> Double {
            guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
            let red = 0.299 * colour.redComponent
            let green = 0.587 * colour.greenComponent
            let blue = 0.114 * colour.blueComponent
            return (red + green + blue) * 255
        }

        /// Rows of the bar, in a column clear of both the fill and the pace tick.
        var trackRows: [Int] {
            let x = trackEnd - 20
            return (0..<bitmap.pixelsHigh).filter { abs(luminance(x: x, y: $0) - background) > 3 }
        }

        var figureBrightness: Double {
            (figureStart..<figureEnd).flatMap { x in
                (0..<bitmap.pixelsHigh).map { luminance(x: x, y: $0) }
            }.max() ?? 0
        }

        var figureRows: [Int] {
            let threshold = background + (figureBrightness - background) / 2
            return (0..<bitmap.pixelsHigh).filter { y in
                (figureStart..<figureEnd).contains { luminance(x: $0, y: y) > threshold }
            }
        }
    }

    static func run() {
        _ = NSApplication.shared
        for metrics in [RowMetrics.menu, RowMetrics.card] {
            testBarKeepsItsHeightAndCentresOnTheFigure(metrics)
            testLiveZeroIsNotGrey(metrics)
        }
    }

    /// The tick is taller than the bar and used to stretch it to the tick's own
    /// height, which also pushed it below the figures.
    private static func testBarKeepsItsHeightAndCentresOnTheFigure(_ metrics: RowMetrics) {
        let sample = render(metrics: metrics, dimmed: false)
        let track = sample.trackRows
        let figure = sample.figureRows
        check(track.count == Int(metrics.trackHeight), "a bar with a tick must stay \(metrics.trackHeight)pt tall, got \(track.count)")
        check(abs(centre(track) - centre(figure)) <= 1, "the bar must centre on its figure: bar \(track), figure \(figure)")
    }

    /// Grey means a carried reading, so a fresh 0% must not share its look.
    private static func testLiveZeroIsNotGrey(_ metrics: RowMetrics) {
        let live = render(metrics: metrics, dimmed: false)
        let carried = render(metrics: metrics, dimmed: true)
        check(live.figureBrightness > 230, "a live 0% must be full ink, got \(live.figureBrightness)")
        check(carried.figureBrightness < 190, "a carried 0% must stay dimmed, got \(carried.figureBrightness)")

        let stub = live.bitmap.colorAt(x: live.trackStart + 3, y: Int(centre(live.trackRows)))?.usingColorSpace(.sRGB)
        let tint = (stub?.greenComponent ?? 0) - (stub?.redComponent ?? 0)
        check(tint > 0.1, "a live 0% stub must keep the pace colour, got green-red \(tint)")
    }

    private static func render(metrics: RowMetrics, dimmed: Bool) -> Sample {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let window = UsageWindow(
            label: "5h",
            percent: 0,
            resetsAt: Int(now.timeIntervalSince1970) + 4 * 3600,
            windowSeconds: 5 * 3600
        )
        let renderer = ImageRenderer(content:
            UsageRow(window: window, metrics: metrics, timing: Pace.Timing(now: now), dimmed: dimmed)
                .frame(width: CGFloat(width))
                .padding(CGFloat(padding))
                .background(Color(white: 0.2))
        )
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            fail("the row did not render")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let corner = Sample(bitmap: bitmap, metrics: metrics, background: 0).luminance(x: 0, y: 0)
        return Sample(bitmap: bitmap, metrics: metrics, background: corner)
    }

    private static func centre(_ rows: [Int]) -> Double {
        Double((rows.first ?? 0) + (rows.last ?? 0)) / 2
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
