import AVFoundation
import UIKit

final class AudioManager: ObservableObject, AVAudioPlayerDelegate {
    private var recorder: AVAudioRecorder?
    private var players: [Int: AVAudioPlayer] = [:]
    private let fileManager = FileManager.default
    private var recordingStartDate: Date?
    private let minimumRecordingDuration: TimeInterval = 0.5
    private var meterTimers: [Int: Timer] = [:]

    @Published var isRecording = false
    @Published var currentRecordingTile: Int?
    @Published var playbackSpeeds: [Int: Float] = [:]
    @Published var playbackLevels: [Int: Float] = [:]

    // Speed limits
    static let minSpeed: Float = 0.1
    static let maxSpeed: Float = 10.0
    static let defaultSpeed: Float = 1.0
    static let speedStep: Float = 0.05

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
            recordingStartDate = Date()

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("Recording failed to start: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        let recordedTile = currentRecordingTile
        let recordingDuration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        currentRecordingTile = nil
        recordingStartDate = nil

        if let tileIndex = recordedTile, recordingDuration < minimumRecordingDuration {
            let url = audioFileURL(for: tileIndex)
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    print("Failed to delete short recording: \(error)")
                }
            }
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Playback

    func play(tileIndex: Int) {
        stopPlayback(for: tileIndex)

        let url = audioFileURL(for: tileIndex)

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = playbackSpeeds[tileIndex] ?? Self.defaultSpeed
            player.delegate = self
            player.prepareToPlay()
            player.play()

            players[tileIndex] = player
            startMetering(for: tileIndex, player: player)

            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func startLooping(tileIndex: Int) {
        stopPlayback(for: tileIndex)

        let url = audioFileURL(for: tileIndex)

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = playbackSpeeds[tileIndex] ?? Self.defaultSpeed
            player.numberOfLoops = -1
            player.delegate = self
            player.prepareToPlay()
            player.play()

            players[tileIndex] = player
            startMetering(for: tileIndex, player: player)
        } catch {
            print("Looped playback failed: \(error)")
        }
    }

    func stopLoopingAfterCurrent(tileIndex: Int) {
        guard let player = players[tileIndex] else { return }
        if player.numberOfLoops == -1 {
            player.numberOfLoops = 0
        }
    }

    private func stopPlayback(for tileIndex: Int) {
        players[tileIndex]?.stop()
        players[tileIndex] = nil
        stopMetering(for: tileIndex)
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
        let steppedSpeed = (clampedSpeed / Self.speedStep).rounded() * Self.speedStep
        let normalizedSpeed = min(max(steppedSpeed, Self.minSpeed), Self.maxSpeed)
        playbackSpeeds[tileIndex] = normalizedSpeed

        if let player = players[tileIndex], player.isPlaying {
            player.rate = normalizedSpeed
        }
    }

    func resetPlaybackSpeed(for tileIndex: Int) {
        playbackSpeeds[tileIndex] = Self.defaultSpeed

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Clear Recording

    func clearRecording(for tileIndex: Int) {
        stopPlayback(for: tileIndex)

        playbackSpeeds[tileIndex] = nil
        playbackLevels[tileIndex] = nil

        let url = audioFileURL(for: tileIndex)

        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }

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

    func getShareableURL(for tileIndex: Int) -> URL? {
        let url = audioFileURL(for: tileIndex)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Metering

    private func startMetering(for tileIndex: Int, player: AVAudioPlayer) {
        stopMetering(for: tileIndex)
        playbackLevels[tileIndex] = 0
        player.isMeteringEnabled = true

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self, weak player] _ in
            guard let self = self, let player = player else {
                self?.stopMetering(for: tileIndex)
                return
            }

            guard player.isPlaying else {
                self.stopMetering(for: tileIndex)
                return
            }

            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            let linear = pow(10.0, power / 20.0)
            let normalized = min(1.0, max(0.0, (linear - 0.02) / 0.98))
            self.playbackLevels[tileIndex] = Float(normalized)
        }

        meterTimers[tileIndex] = timer
    }

    private func stopMetering(for tileIndex: Int) {
        meterTimers[tileIndex]?.invalidate()
        meterTimers[tileIndex] = nil
        playbackLevels[tileIndex] = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard let tileIndex = players.first(where: { $0.value === player })?.key else { return }
        players[tileIndex] = nil
        stopMetering(for: tileIndex)
    }
}
