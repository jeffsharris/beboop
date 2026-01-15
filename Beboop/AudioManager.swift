import AVFoundation
import UIKit

final class AudioManager: ObservableObject {
    private var recorder: AVAudioRecorder?
    private var players: [Int: AVAudioPlayer] = [:]
    private let fileManager = FileManager.default

    @Published var isRecording = false
    @Published var currentRecordingTile: Int?
    @Published var playbackSpeeds: [Int: Float] = [:]

    // Speed limits
    static let minSpeed: Float = 0.5
    static let maxSpeed: Float = 2.0
    static let defaultSpeed: Float = 1.0

    init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: - Recording

    func startRecording(for tileIndex: Int) {
        // Request microphone permission if needed
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.beginRecording(for: tileIndex)
                } else {
                    print("Microphone permission denied")
                }
            }
        }
    }

    private func beginRecording(for tileIndex: Int) {
        // Stop any existing recording
        stopRecording()

        let url = audioFileURL(for: tileIndex)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.prepareToRecord()
            recorder?.record()

            isRecording = true
            currentRecordingTile = tileIndex

            // Haptic feedback for recording start
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("Recording failed to start: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        recorder?.stop()
        recorder = nil
        isRecording = false
        currentRecordingTile = nil

        // Haptic feedback for recording stop
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Playback

    func play(tileIndex: Int) {
        let url = audioFileURL(for: tileIndex)

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            // Create a new player for this tile (allows simultaneous playback)
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = playbackSpeeds[tileIndex] ?? Self.defaultSpeed
            player.prepareToPlay()
            player.play()

            // Store the player to keep it alive
            players[tileIndex] = player

            // Haptic feedback for playback
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func hasRecording(for tileIndex: Int) -> Bool {
        let url = audioFileURL(for: tileIndex)
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Playback Speed

    func getPlaybackSpeed(for tileIndex: Int) -> Float {
        return playbackSpeeds[tileIndex] ?? Self.defaultSpeed
    }

    func setPlaybackSpeed(for tileIndex: Int, speed: Float) {
        let clampedSpeed = min(max(speed, Self.minSpeed), Self.maxSpeed)
        playbackSpeeds[tileIndex] = clampedSpeed

        // Update currently playing audio if any
        if let player = players[tileIndex], player.isPlaying {
            player.rate = clampedSpeed
        }
    }

    func resetPlaybackSpeed(for tileIndex: Int) {
        playbackSpeeds[tileIndex] = Self.defaultSpeed

        // Haptic feedback for reset
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Clear Recording

    func clearRecording(for tileIndex: Int) {
        // Stop playback if playing
        players[tileIndex]?.stop()
        players[tileIndex] = nil

        // Clear speed setting
        playbackSpeeds[tileIndex] = nil

        let url = audioFileURL(for: tileIndex)

        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }

            // Haptic feedback for clear
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        } catch {
            print("Failed to delete recording: \(error)")
        }
    }

    // MARK: - File Management

    func audioFileURL(for tileIndex: Int) -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("tile_\(tileIndex).m4a")
    }

    // For sharing - returns the URL if recording exists
    func getShareableURL(for tileIndex: Int) -> URL? {
        let url = audioFileURL(for: tileIndex)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
