import Foundation

// §3 scheduling semantics + §6 sound pairs.

enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7, sunday = 1
    var id: Int { rawValue }
    /// Display order: M T W T F S S (§4 day dots).
    static let displayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    var letter: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }
}

/// A wake sound is a pair — one identity, a gentle half and a firm half (§6).
/// Picking a pair picks both halves; they are never mixed and matched.
struct SoundPair: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String

    /// Bundle sound file names (no extension). Phase 1 is the gentle half;
    /// A–E are the firm chain; `continuous` is the in-app loop; `preview` is
    /// the 5 s + 5 s crossfade clip for the Alarm screen; `sleep` backs Wind down.
    var phase1File: String { "\(id)-phase1" }
    func chainFile(_ step: ChainStep) -> String { "\(id)-\(step.rawValue)" }
    var continuousFile: String { "\(id)-continuous" }
    var previewFile: String { "\(id)-preview" }

    static let dawn = SoundPair(id: "dawn", name: "Dawn", description: "warm strings, then chimes")
    static let fountain = SoundPair(id: "fountain", name: "Fountain", description: "water, then bright bells")
    static let all: [SoundPair] = [.dawn, .fountain]
    static func named(_ id: String) -> SoundPair { all.first { $0.id == id } ?? .dawn }
}

enum ChainStep: String, Codable, CaseIterable, Sendable {
    case a, b, c, d, e
}

/// §3 timeline: chain offsets into phase 2, in seconds.
enum ChainTiming {
    static let phase1Duration: TimeInterval = 30
    /// A / B / C / D / E first fires.
    static let offsets: [(ChainStep, TimeInterval)] = [
        (.a, 0), (.b, 30), (.c, 60), (.d, 90), (.e, 120),
    ]
    /// E repeats until dismissed, cap 15 min into phase 2. Each file is 30 s,
    /// so re-fire every 30 s. AlarmKit per-app alarm limits are spec-to-verify
    /// (milestone 1) — if the system rejects the tail, the cap shrinks and we log.
    static let plateauRepeatInterval: TimeInterval = 30
    static let cap: TimeInterval = 15 * 60

    static var plateauRepeatOffsets: [TimeInterval] {
        var out: [TimeInterval] = []
        var t = 120 + plateauRepeatInterval
        while t < cap {
            out.append(t)
            t += plateauRepeatInterval
        }
        return out
    }
}

/// The alarm as configured the night before. Gap G ∈ {3, 6, 9} minutes —
/// chosen with intention, never negotiated half-asleep (principle 1).
struct AlarmModel: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    /// Enabled day dots. Empty = one-shot for the next occurrence of T, then disarms (§3).
    var days: Set<Weekday>
    var gapMinutes: Int = 6
    var pairID: String = SoundPair.dawn.id
    var isEnabled: Bool = true

    var pair: SoundPair { SoundPair.named(pairID) }
    var gap: TimeInterval { TimeInterval(gapMinutes * 60) }

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Next date at which this alarm's phase 1 fires, strictly after `now`.
    func nextFireDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if days.isEmpty {
            return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
        }
        var best: Date?
        for day in days {
            comps.weekday = day.rawValue
            if let d = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime) {
                if best == nil || d < best! { best = d }
            }
        }
        return best
    }

    /// The next `count` phase-1 dates, soonest first. A one-shot alarm has at most one.
    func nextFireDates(count: Int, after now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var from = now
        while dates.count < (days.isEmpty ? 1 : count),
              let d = nextFireDate(after: from, calendar: calendar) {
            dates.append(d)
            from = d
        }
        return dates
    }
}

/// §3 state machine.
enum WakePhase: Equatable, Sendable {
    case idle
    case scheduled(next: Date)
    case phase1Playing(started: Date)
    case gapWaiting(phase2At: Date)
    case phase2(started: Date)   // escalating → plateau is a function of elapsed time
    case done

    var isRinging: Bool {
        switch self {
        case .phase1Playing, .gapWaiting, .phase2: true
        default: false
        }
    }
}
