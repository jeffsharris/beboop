import AVFoundation
import UIKit

final class SoundPlayer: ObservableObject {
    private var player: AVAudioPlayer?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    func play() {
        guard let url = Bundle.main.url(forResource: "boop", withExtension: "wav") else {
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Audio playback failed: \(error)")
        }

        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }
}
