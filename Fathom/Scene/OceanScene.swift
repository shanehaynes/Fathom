import SwiftUI

// §5 — the scene. The screen is the water's surface viewed from directly above.
// Every constant here is extracted from prototype/design-prototype.html and must
// not drift from it. Motion on x/y is constant, slow, undirected; depth moves
// only z (brightness, saturation, apparent size) and changes only with the
// time-of-day state. Depth never translates bloom positions.

struct Bloom {
    let cx: Double      // base position, fraction of width
    let cy: Double      // base position, fraction of height
    let r: Double       // base radius, × width
    let hue0: Double    // base hue, degrees
    let hspd: Double    // hue drift, deg/ms
    let spx: Double     // drift speed x
    let spy: Double     // drift speed y
    let ph: Double      // drift phase

    static func make(seed: Double) -> [Bloom] {
        (0..<6).map { i in
            let fi = Double(i)
            return Bloom(
                cx: 0.12 + 0.76 * ((fi * 0.37 + seed).truncatingRemainder(dividingBy: 1)),
                cy: 0.18 + 0.68 * ((fi * 0.53 + seed * 0.7).truncatingRemainder(dividingBy: 1)),
                r: 0.30 + 0.28 * ((fi * 0.71).truncatingRemainder(dividingBy: 1)),
                hue0: (fi * 60 + seed * 360).truncatingRemainder(dividingBy: 360),
                hspd: 0.0018 + 0.0016 * ((fi * 0.43).truncatingRemainder(dividingBy: 1)),
                spx: 0.6 + ((fi * 0.29).truncatingRemainder(dividingBy: 1)),
                spy: 0.4 + ((fi * 0.41).truncatingRemainder(dividingBy: 1)),
                ph: fi * 1.7 + seed * 6
            )
        }
    }
}

/// Shared scene state: one seed per launch so the composition is continuous
/// across screens. Positions are chance (principle: where a bloom sits at any
/// moment is chance) — the seed is not persisted.
@MainActor
final class SceneModel: ObservableObject {
    static let shared = SceneModel()
    let seed = Double.random(in: 0..<1)
    let blooms: [Bloom]
    let epoch = Date()

    private init() {
        blooms = Bloom.make(seed: seed)
    }

    /// Milliseconds since launch — the prototype's `t`.
    func t(at date: Date) -> Double {
        date.timeIntervalSince(epoch) * 1000
    }
}

func smoothstep(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

/// Eased depth: state transitions ease over a few seconds rather than stepping (§5).
struct EasedDepth {
    private(set) var from: Double
    private(set) var to: Double
    private(set) var start: Date
    var duration: TimeInterval = 3

    init(_ value: Double) {
        from = value
        to = value
        start = .distantPast
    }

    mutating func set(_ target: Double, at date: Date = Date()) {
        guard target != to else { return }
        from = value(at: date)
        to = target
        start = date
    }

    func value(at date: Date) -> Double {
        let p = date.timeIntervalSince(start) / duration
        return from + (to - from) * smoothstep(p)
    }
}

/// CSS hsl() is hue/saturation/lightness; SwiftUI Color is HSB. Convert exactly.
func hslColor(hue: Double, sat: Double, light: Double, alpha: Double) -> Color {
    let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
    let s = sat / 100, l = light / 100
    let b = l + s * min(l, 1 - l)
    let sb = b == 0 ? 0 : 2 * (1 - l / b)
    return Color(hue: h, saturation: sb, brightness: b, opacity: alpha)
}

enum SceneMode {
    case normal
    /// Bedside red-shift/blackout: clamp to deep red at minimal luminance (§4).
    case redShift
}

struct OceanScene: View {
    @ObservedObject var model: SceneModel = .shared
    /// Depth I for the current state (already eased/ramped by the caller).
    var depth: Double
    /// Wake screen lifts the veil: opacity 1 − 0.45·I. Others use 1.0 (§5 veil row).
    var veilFactor: Double = 1.0
    var mode: SceneMode = .normal
    /// Bedside night mode drops to sub-1 fps (§4 OLED mitigations).
    var slowUpdates: Bool = false
    /// Bedside slow pixel-drift of the entire composition, ±8 px over minutes.
    var pixelDrift: Bool = false

    var body: some View {
        TimelineView(schedule) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, date: timeline.date)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var schedule: AnimationTimelineSchedule {
        // AnimationTimelineSchedule with a large minimum interval approximates
        // .periodic for the bedside case while keeping one view type.
        slowUpdates ? .animation(minimumInterval: 1.5) : .animation
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let t = model.t(at: date)
        let W = size.width, H = size.height
        let I = min(max(depth, 0), 1)

        // Ground
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink))

        // Bedside composition drift: the entire scene wanders ±8 px over minutes.
        if pixelDrift {
            let s = date.timeIntervalSince(model.epoch)
            let dx = 8 * sin(2 * .pi * s / 420)
            let dy = 8 * cos(2 * .pi * s / 560)
            context.translateBy(x: dx, y: dy)
        }

        // Blooms — additive
        context.blendMode = .plusLighter
        let sat = 40 + 45 * I
        let lig = 30 + 28 * I
        let alpha = 0.07 + 0.34 * I
        for b in model.blooms {
            let x = (b.cx + 0.10 * sin(t * 0.00013 * b.spx + b.ph)) * W
            let y = (b.cy + 0.07 * cos(t * 0.00011 * b.spy + b.ph * 1.3)) * H
            let r = b.r * W * (0.85 + 0.55 * I)
            let hue: Double
            let satEff: Double
            let ligEff: Double
            switch mode {
            case .normal:
                hue = (b.hue0 + t * b.hspd).truncatingRemainder(dividingBy: 360)
                satEff = sat
                ligEff = lig
            case .redShift:
                hue = 4
                satEff = 70
                ligEff = min(lig, 16)
            }
            let core = hslColor(hue: hue, sat: satEff, light: ligEff, alpha: alpha)
            let edge = hslColor(hue: hue, sat: satEff, light: ligEff, alpha: 0)
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [core, edge]),
                    center: CGPoint(x: x, y: y),
                    startRadius: 0,
                    endRadius: r
                )
            )
        }
        context.blendMode = .normal

        // Veil: radial 130%×110% at (50%, 42%), rgba(6,9,14, 0.28 → 0.74).
        // CSS ellipse sizes map to rx = 1.30·W, ry = 1.10·H; Canvas gradients are
        // circular, so scale y while drawing.
        let rx = 1.30 * W
        let ry = 1.10 * H
        var veil = context
        veil.translateBy(x: 0.50 * W, y: 0.42 * H)
        veil.scaleBy(x: 1, y: ry / rx)
        let inner = Theme.ink.opacity(0.28 * veilFactor)
        let outer = Theme.ink.opacity(0.74 * veilFactor)
        veil.fill(
            Path(ellipseIn: CGRect(x: -rx, y: -rx, width: 2 * rx, height: 2 * rx)),
            with: .radialGradient(
                Gradient(colors: [inner, outer]),
                center: .zero,
                startRadius: 0,
                endRadius: rx
            )
        )
    }
}

// §5 depth per state
enum Depth {
    static let night = 0.10
    static let day = 0.85
    /// Wake: 0.14 + 0.86·smoothstep(min(m/4, 1)), m = minutes since phase 2 began.
    static func wake(minutesIntoPhase2 m: Double) -> Double {
        0.14 + 0.86 * smoothstep(min(m / 4, 1))
    }
}
