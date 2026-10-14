import AVFoundation
import UIKit
import LumaGridServices

/// Sound effects and haptics, both individually switchable in Settings. Sounds are original
/// tones synthesized by Scripts/generate_sounds.py. The audio session is `.ambient`, so the
/// game respects the silent switch and mixes with the player's own music.
@MainActor
final class FeedbackService {
    enum Event {
        case pickUp
        case place
        case invalid
        case clear(lines: Int)
        case combo
        case lumenCharged
        case pulseReady
        case pulse
        case gameOver
    }

    private let settings: () -> GameSettings
    private var players: [String: AVAudioPlayer] = [:]
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    private var audioConfigured = false

    init(settings: @escaping () -> GameSettings) {
        self.settings = settings
    }

    func play(_ event: Event) {
        let current = settings()
        if current.hapticsEnabled { haptic(for: event) }
        if current.soundEnabled, let name = soundName(for: event) { playSound(name) }
    }

    /// Call when a drag starts so the next haptic fires without latency.
    func prepare() {
        guard settings().hapticsEnabled else { return }
        impactLight.prepare()
        impactMedium.prepare()
    }

    private func haptic(for event: Event) {
        switch event {
        case .pickUp: impactLight.impactOccurred(intensity: 0.5)
        case .place: impactLight.impactOccurred()
        case .invalid: notification.notificationOccurred(.warning)
        case .clear: impactMedium.impactOccurred()
        case .combo: notification.notificationOccurred(.success)
        case .lumenCharged: impactLight.impactOccurred(intensity: 0.8)
        case .pulseReady: notification.notificationOccurred(.success)
        case .pulse: impactMedium.impactOccurred(intensity: 1.0)
        case .gameOver: notification.notificationOccurred(.error)
        }
    }

    private func soundName(for event: Event) -> String? {
        switch event {
        case .pickUp: return nil
        case .place: return "place"
        case .invalid: return "invalid"
        case .clear: return "clear"
        case .combo: return "combo"
        case .lumenCharged, .pulseReady: return "charge"
        case .pulse: return "pulse"
        case .gameOver: return "gameover"
        }
    }

    private func playSound(_ name: String) {
        configureAudioSessionIfNeeded()
        let player: AVAudioPlayer
        if let cached = players[name] {
            player = cached
        } else {
            guard
                let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                let created = try? AVAudioPlayer(contentsOf: url)
            else { return }
            created.volume = 0.7
            created.prepareToPlay()
            players[name] = created
            player = created
        }
        player.currentTime = 0
        player.play()
    }

    private func configureAudioSessionIfNeeded() {
        guard !audioConfigured else { return }
        audioConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }
}
