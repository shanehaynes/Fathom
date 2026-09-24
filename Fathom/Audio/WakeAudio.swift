import Foundation
import AVFoundation

// §7 wake handoff: engaging the system alarm foregrounds the app; AVAudioSession
// (.playback) takes over with the continuous rendition at the correct ramp
// position, computed from wall-clock time since phase-2 start. §3: the climb is
// linear over two minutes (A +0:00 → E +2:00), opening clearly audible, and the
// plateau never gets louder — insistent, never punishing.

@MainActor
final class WakeAudio {
    static let shared = WakeAudio()
    private var player: AVAudioPlayer?
    private var rampTimer: Timer?
    private var fadeTimer: Timer?

    private init() {}

    private func url(for file: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: "m4a")
            ?? Bundle.main.url(forResource: file, withExtension: "caf")
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    /// Continuous in-app rendition for the Wake screen, volume set to the §3
    /// linear ramp position and advanced every second until plateau.
    func startWake(pair: SoundPair, phase2Start: Date) {
        guard let url = url(for: pair.continuousFile) else { return }
        activateSession()
        stopTimers()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        applyRamp(phase2Start: phase2Start)
        player?.play()
        rampTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                WakeAudio.shared.applyRamp(phase2Start: phase2Start)
            }
        }
    }

    private func applyRamp(phase2Start: Date) {
        let m = Date().timeIntervalSince(phase2Start) / 60
        // Engaged during phase 1 or the gap: the gap is silence (§3) — the
        // continuous rendition waits for phase 2.
        guard m >= 0 else {
            player?.volume = 0
            return
        }
        // Continuous is rendered at E energy; the chain's A sits ~3.7 dB below E
        // and each 30 s step adds ~1 dB. Mirror that: open at A's level, climb
        // evenly in dB to E at +2:00, then hold.
        let ramp = min(m / 2, 1)
        player?.volume = Float(pow(10, -3.7 * (1 - ramp) / 20))
    }

    /// Wind down (§4 Tonight): sleep sound with a fade-out timer. The practical
    /// hook that gets the phone plugged in and face-up.
    func startWindDown(pair: SoundPair, fadeOver duration: TimeInterval = 20 * 60) {
        guard let url = url(for: "\(pair.id)-sleep") ?? self.url(for: pair.continuousFile) else { return }
        activateSession()
        stopTimers()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 0.8
        player?.play()
        let started = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                let p = Date().timeIntervalSince(started) / duration
                if p >= 1 {
                    WakeAudio.shared.stop()
                } else {
                    WakeAudio.shared.player?.volume = Float(0.8 * (1 - smoothstep(p)))
                }
            }
        }
    }

    /// Alarm-screen preview: the bundled 5 s gentle → crossfade → 5 s firm clip (§6).
    func preview(pair: SoundPair) {
        guard let url = url(for: pair.previewFile) else { return }
        activateSession()
        stopTimers()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = 0
        player?.volume = 1
        player?.play()
    }

    var isPlaying: Bool { player?.isPlaying ?? false }

    func stop() {
        stopTimers()
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopTimers() {
        rampTimer?.invalidate()
        rampTimer = nil
        fadeTimer?.invalidate()
        fadeTimer = nil
    }
}
