import CoreHaptics
import UIKit

/// One short, crisp tick per key. A Core Haptics engine is started when the keyboard opens and kept
/// running, so each tick plays right away: UIImpactFeedbackGenerator wakes the vibration motor lazily,
/// which made ticks land late and sometimes feel doubled (Tony, build 16-17). Falls back to it when
/// Core Haptics isn't available.
final class KeyHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private let fallback = UIImpactFeedbackGenerator(style: .soft)
    private var running = false
    /// How strong the tick is (0-1) and how crisp: low sharpness is a rounder, duller tap.
    static let intensity: Float = 0.5, sharpness: Float = 0.35

    func start() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { fallback.prepare(); return }
        do {
            if engine == nil {
                let e = try CHHapticEngine()
                e.playsHapticsOnly = true
                e.isAutoShutdownEnabled = false
                e.resetHandler = { [weak self] in self?.running = false; self?.player = nil; self?.start() }
                e.stoppedHandler = { [weak self] _ in self?.running = false }
                engine = e
            }
            if !running { try engine?.start(); running = true }
            if player == nil {
                // a rounder, duller tap than the first tick (intensity 0.4, sharpness 0.55), a little stronger (Hieu)
                let tick = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Self.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.sharpness)], relativeTime: 0)
                player = try engine?.makePlayer(with: CHHapticPattern(events: [tick], parameters: []))
            }
        } catch {
            engine = nil; player = nil; running = false
            fallback.prepare()
        }
    }

    func stop() { engine?.stop(completionHandler: nil); running = false }

    func tick() {
        if running, let p = player, (try? p.start(atTime: CHHapticTimeImmediate)) != nil { return }
        fallback.impactOccurred(intensity: 0.6)
        fallback.prepare()
    }
}
