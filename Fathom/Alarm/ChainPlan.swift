import Foundation

/// Pure description of a two-phase wake chain. No AlarmKit here — this is the
/// timing spec from DESIGN.md §3, expressed as data so it can be inspected and tested.
struct ChainPlan {
    struct Step: Identifiable {
        let id = UUID()
        let fireAt: Date
        let soundFile: String
        let stepIndex: Int
        let label: String
    }

    let chainID: String
    let steps: [Step]

    /// Phase-2 file offsets (seconds after phase 2 begins) from DESIGN.md §3.
    static let escalationOffsets: [TimeInterval] = [0, 45, 90, 150, 240]
    static let escalationFiles = ["phase2_a.wav", "phase2_b.wav", "phase2_c.wav", "phase2_d.wav", "phase2_e.wav"]
    static let plateauInterval: TimeInterval = 45

    /// - Parameters:
    ///   - wakeAt: time `T` — phase 1 fires here.
    ///   - gap: seconds between phase 1 and the start of phase 2 (3/6/9 min in production; shorter for testing).
    ///   - plateauRepeats: how many extra repeats of file E after the escalation (production cap ≈ 15 min ⇒ 20 repeats).
    ///   - pairName: the sound pair's display name.
    static func twoPhase(wakeAt: Date, gap: TimeInterval, plateauRepeats: Int, pairName: String) -> ChainPlan {
        let chainID = UUID().uuidString
        var steps: [Step] = []
        steps.append(Step(fireAt: wakeAt, soundFile: "phase1_gentle.wav", stepIndex: 0, label: "\(pairName) · gentle"))

        let phase2Start = wakeAt.addingTimeInterval(gap)
        for (i, offset) in escalationOffsets.enumerated() {
            let phaseLabel = i == escalationOffsets.count - 1 ? "full" : "rising"
            steps.append(Step(fireAt: phase2Start.addingTimeInterval(offset),
                              soundFile: escalationFiles[i],
                              stepIndex: i + 1,
                              label: "\(pairName) · \(phaseLabel)"))
        }
        let lastOffset = escalationOffsets.last ?? 0
        for r in 1...max(plateauRepeats, 1) where plateauRepeats > 0 {
            steps.append(Step(fireAt: phase2Start.addingTimeInterval(lastOffset + plateauInterval * Double(r)),
                              soundFile: escalationFiles.last!,
                              stepIndex: escalationOffsets.count + r,
                              label: "\(pairName) · full"))
        }
        return ChainPlan(chainID: chainID, steps: steps)
    }
}
