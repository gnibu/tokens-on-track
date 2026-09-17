import SwiftUI

/// The material vocabulary the card and the dropdown are both built from:
/// a blurred pane, a diagonal sheen over it, a bright top lip, and controls
/// that read as cut into the glass rather than drawn on top of it.
///
/// Every surface is dark by construction — the sheen is white over blur, so a
/// light appearance would wash the text out. Roots set `\.colorScheme` to dark
/// rather than each call site guessing.
enum Glass {
    static let cardRadius: CGFloat = 22
    static let panelRadius: CGFloat = 20
    static let groupRadius: CGFloat = 14

    /// Text on glass. The design works in white at five or six opacities.
    static func ink(_ opacity: Double) -> Color { .white.opacity(opacity) }

    /// linear-gradient(155deg, …) — the diagonal lift across the pane.
    static func sheen(tint: Color = .white, top: Double = 0.18, bottom: Double = 0.06) -> LinearGradient {
        LinearGradient(
            colors: [tint.opacity(top), .white.opacity(bottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The border and the lit top edge in one stroke.
    ///
    /// The design keeps them separate — `border: 1px rgba(255,255,255,0.2)` all
    /// the way round, and `inset 0 1px 0 rgba(255,255,255,0.4)` only along the
    /// top. Running a single gradient from 0.4 down to 0.08 instead spread the
    /// bright end across the whole upper half: the left border measured 184
    /// where the design measures 85. So the bright stop now ends within the
    /// first few percent of the height and the rest holds at `base`.
    static func rim(top: Double = 0.35, base: Double = 0.2, tint: Color = .white) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(top), location: 0),
                .init(color: tint.opacity(base), location: 0.05),
                .init(color: tint.opacity(base), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The design's blue, laid over the blur.
    ///
    /// The mock ends its backdrop-filter with `saturate(180%)`, which is what
    /// makes the pane read as blue glass rather than as slate. SwiftUI has no
    /// equivalent — materials are composited by the window server, below the
    /// level a `.saturation` modifier reaches — so the colour goes on top of
    /// the blur instead of being recovered from it. Sampled from the mock.
    ///
    /// The trade is that the pane no longer takes the hue of whatever is behind
    /// it. Over a blue desktop that is invisible; over an orange window it will
    /// stay blue, exactly as the mock does.
    ///
    /// The mock's own stops are too light to use directly. It was drawn over a
    /// lit teal canvas, so its top stop is `(69,118,144)` — luminance 110,
    /// against a wallpaper that measures 47. Laying that over a dark corner of
    /// the screen lightens the pane rather than colouring it, which is what
    /// left the dropdown pale beside the card even with the sheen thinned. The
    /// hue and the diagonal are the mock's; the luminance is roughly halved so
    /// the colour lands without the lift.
    static func tone(_ strength: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.149, green: 0.255, blue: 0.311).opacity(0.58 * strength),
                Color(red: 0.055, green: 0.121, blue: 0.169).opacity(0.92 * strength),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The divider used inside a pane: visible in the middle, gone at the ends.
    static var hairline: some View {
        LinearGradient(
            colors: [.white.opacity(0.02), .white.opacity(0.18), .white.opacity(0.02)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

extension View {
    /// A whole pane of glass — the desktop card and the dropdown.
    ///
    /// - `tint` colours the sheen and the rim together, which is how the hot
    ///   state is expressed: the same card, lit red from inside.
    /// - `dim` eases off the sheen. Translucent glass pulls whatever is behind
    ///   it towards its own mid-tone, so the same pane darkens a bright
    ///   backdrop and lightens a dark one: measured over the wallpaper, the
    ///   card came out 31 below its backdrop and the dropdown 23 above its own.
    ///   The card can be dragged onto whatever suits it; the dropdown is pinned
    ///   under the menu bar, so it has to hold up over a dark corner.
    ///
    ///   It works on the sheen rather than by laying black over the blur, which
    ///   was the first attempt: the white gradient is what adds the 23, and a
    ///   scrim heavy enough to cancel it also cancels the blur, leaving a flat
    ///   dark panel with no glass left in it. Thinning the white keeps the
    ///   backdrop showing through, which is the whole effect.
    /// - `tone` lays the design's blue over the blur; see `Glass.tone`.
    /// - `border` scales the rim. The menu bar window draws a hairline of its
    ///   own that nothing in its hierarchy accounts for — the frame view is
    ///   empty and transparent, yet its edge measures 180 where the pane
    ///   measures 50, while the desktop card's edge measures 145 against a
    ///   predicted 144. Ours was landing on top of the system's and reading as
    ///   a white outline, so the dropdown asks for a fraction of it.
    func glassPane(
        radius: CGFloat,
        tint: Color? = nil,
        border: Double = 1,
        dim: Double = 0,
        tone: Double = 0,
        shadow: Bool = true
    ) -> some View {
        let sheen = Glass.sheen(
            tint: tint ?? .white,
            top: (tint == nil ? 0.18 : 0.20) * (1 - dim),
            bottom: 0.06 * (1 - dim)
        )
        // The hot state borrows the design's red border, `rgba(255,140,140,0.34)`.
        let rim = Glass.rim(
            top: (tint == nil ? 0.35 : 0.36) * border,
            base: (tint == nil ? 0.2 : 0.34) * border,
            tint: tint ?? .white
        )
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return background {
            shape
                .fill(.ultraThinMaterial)
                // Colour first, then the sheen over it — the white gradient is
                // meant to lift the glass, not to be tinted by it.
                .overlay(tone > 0 ? shape.fill(Glass.tone(tone)) : nil)
                .overlay(shape.fill(sheen))
        }
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(rim, lineWidth: 1)
        )
        .shadow(color: .black.opacity(shadow ? 0.45 : 0), radius: 28, y: 14)
        .environment(\.colorScheme, .dark)
    }

    /// An inset group inside a pane — the pattern System Settings uses, and
    /// what keeps the settings tab from reading as one undifferentiated list.
    func glassGroup(padding: EdgeInsets = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) -> some View {
        self.padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Glass.groupRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
            )
    }
}

// --------------------------------------------------------------------- //
// Readings
// --------------------------------------------------------------------- //

/// The consumption bar: a groove cut into the glass, a fill that glows, and
/// the current target as a notch straight through both.
struct UsageTrack: View {
    let percent: Double
    let target: Double?
    let palette: Pace.Palette
    var height: CGFloat = 10
    var glows: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let radius = height * 0.6

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        Color.black.opacity(0.22)
                            .shadow(.inner(color: .black.opacity(0.45), radius: 1.5, y: 1))
                            .shadow(.inner(color: .white.opacity(0.10), radius: 0.5, y: -1))
                    )

                fill(in: width, radius: radius)

                // Where usage *should* be if spent evenly across the window.
                if let target, target > 0 {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2, height: height + 6)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .offset(x: min(width - 2, width * target / 100 - 1))
                }
            }
        }
        .frame(height: height)
    }

    /// An untouched window still gets a stub, so the row reads as a track with
    /// nothing in it rather than as a track that failed to draw.
    @ViewBuilder
    private func fill(in width: CGFloat, radius: CGFloat) -> some View {
        let idle = percent < 0.5
        let drawn = max(6, width * min(100, max(0, percent)) / 100)

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(idle ? Pace.idleFill : palette.fill)
            .frame(width: idle ? 6 : drawn)
            .shadow(color: glows && !idle ? palette.base.opacity(0.55) : .clear, radius: 6)
    }
}

/// The donut in the summary line: one glance at the worst window. Carries the
/// same target mark as the tracks, so usage and where it should be now are read
/// off one shape.
struct UsageRing: View {
    let percent: Double
    let color: Color
    var target: Double? = nil
    var size: CGFloat = 40

    var body: some View {
        let line = size * 0.185
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: line)
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: min(1, max(0.005, percent / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if let target, target > 0 {
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: line + 5)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(y: -(size - line) / 2)
                    .rotationEffect(.degrees(min(100, target) / 100 * 360))
            }
        }
        .frame(width: size, height: size)
    }
}

// --------------------------------------------------------------------- //
// Controls
// --------------------------------------------------------------------- //

/// The pill segmented control, used for the tabs, the card layer and the
/// refresh interval. AppKit's own segmented control cannot be made to sit on
/// glass without bringing its own opaque chrome along.
struct GlassSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }

        init(_ value: Value, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    let options: [Option]
    @Binding var selection: Value
    var fontSize: CGFloat = 12
    var verticalPadding: CGFloat = 6
    var enabled: Bool = true

    @Namespace private var slider

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let chosen = option.value == selection

                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: fontSize, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(Glass.ink(chosen ? 1 : 0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, verticalPadding)
                        .contentShape(Rectangle())
                        .background {
                            if chosen {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.24))
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "chosen", in: slider)
                            }
                        }
                }
                .buttonStyle(.plain)
                // The system ring is drawn as a hard rectangle around the whole
                // segment and cuts straight across the pill.
                .focusEffectDisabled()
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.24))
        )
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}

/// A threshold slider. Coarse adjustment by dragging beats aiming at an 8pt
/// stepper arrow, which is what the old settings pane asked for.
struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accessibilityLabel: String
    let accessibilityValue: String
    var step: Double = 1
    var colors: [Color] = [Pace.warn, Pace.bad]
    var enabled: Bool = true

    private let knob: CGFloat = 16
    private let track: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = max(1, width - knob)
            let fraction = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.26))
                    .frame(height: track)

                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: knob / 2 + travel * fraction, height: track)

                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: travel * fraction)
            }
            .frame(height: knob, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard enabled else { return }
                    let position = min(1, max(0, (drag.location.x - knob / 2) / travel))
                    let raw = range.lowerBound + position * (range.upperBound - range.lowerBound)
                    let snapped = (raw / step).rounded() * step
                    value = min(range.upperBound, max(range.lowerBound, snapped))
                }
            )
        }
        .frame(height: knob)
        .opacity(enabled ? 1 : 0.45)
        .focusable(enabled)
        .onKeyPress(keys: [.leftArrow, .downArrow, .rightArrow, .upArrow]) { press in
            switch press.key {
            case .leftArrow, .downArrow:
                adjust(by: -1)
            case .rightArrow, .upArrow:
                adjust(by: 1)
            default:
                return .ignored
            }
            return .handled
        }
        .disabled(!enabled)
        // Keep the glass control on screen, but let assistive technologies
        // operate the native slider semantics they already understand.
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) {
                Text(accessibilityLabel)
            }
            .accessibilityValue(accessibilityValue)
            .disabled(!enabled)
        }
    }

    private func adjust(by steps: Double) {
        guard enabled else { return }
        let raw = value + steps * step
        let snapped = (raw / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }
}

/// A row in an inset group: label, optional second line, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var enabled: Bool = true
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.ink(enabled ? 0.92 : 0.4))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Glass.ink(0.45))
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// A switch that matches the design's green pill without giving up the system
/// control's animation, hit area or keyboard handling.
struct GlassSwitch: View {
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Pace.good)
            .controlSize(.small)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// The loader the glass uses: a short arc turning at a steady clip. AppKit's
/// own spinner brings a heavier, greyer look that reads as a foreign object on
/// the pane, and it cannot carry the design's translucent white.
struct GlassSpinner: View {
    var size: CGFloat = 12
    var color: Color = Glass.ink(0.8)

    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.68)
            .stroke(color, style: StrokeStyle(lineWidth: max(1.4, size * 0.15), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

/// The small glass button in a header — refresh, settings.
struct GlassButton: View {
    let label: String
    var systemImage: String?
    var prominent: Bool = false
    var enabled: Bool = true
    /// Swaps the icon for a spinner while the action it started is in flight,
    /// so pressing refresh reads as something happening rather than as a click
    /// that did nothing.
    var spinning: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if spinning {
                    GlassSpinner(size: 12)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .medium))
                }
                if !label.isEmpty {
                    Text(label).font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(Glass.ink(0.95))
            .padding(.horizontal, label.isEmpty ? 8 : 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(prominent ? 0.24 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// The plain text action the design puts in a footer — "Quit".
struct GlassLink: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Glass.ink(hovering ? 0.95 : 0.62))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}
