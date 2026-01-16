import AVFoundation
import UIKit

final class AudioManager: NSObject, ObservableObject {
    private struct PlaybackChain {
        let player: AVAudioPlayerNode
        let timePitchA: AVAudioUnitTimePitch
        let timePitchB: AVAudioUnitTimePitch
        let mixer: AVAudioMixerNode
        let format: AVAudioFormat
    }

    private let engine = AVAudioEngine()
    private var recorder: AVAudioRecorder?
    private var playbackChains: [Int: PlaybackChain] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var loopingTiles: Set<Int> = []
    private var activeTaps: Set<Int> = []
    private var fallbackPlayers: [Int: AVAudioPlayer] = [:]
    private var fallbackMeterTimers: [Int: Timer] = [:]
    private let fileManager = FileManager.default
    private var recordingStartDate: Date?
    private let minimumRecordingDuration: TimeInterval = 0.5

    @Published var isRecording = false
    @Published var currentRecordingTile: Int?
    @Published var playbackSpeeds: [Int: Float] = [:]
    @Published var playbackLevels: [Int: Float] = [:]

    // Speed limits
    static let minSpeed: Float = 0.1
    static let maxSpeed: Float = 10.0
    static let defaultSpeed: Float = 1.0
    static let speedStep: Float = 0.05

    override init() {
        super.init()
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

    private func ensureEngineRunning() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Audio engine failed to restart: \(error)")
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

        if let tileIndex = recordedTile {
            buffers[tileIndex] = nil

            if recordingDuration < minimumRecordingDuration {
                let url = audioFileURL(for: tileIndex)
                if fileManager.fileExists(atPath: url.path) {
                    do {
                        try fileManager.removeItem(at: url)
                    } catch {
                        print("Failed to delete short recording: \(error)")
                    }
                }
            }
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Playback

    func play(tileIndex: Int) {
        stopPlayback(for: tileIndex)
        loopingTiles.remove(tileIndex)

        guard let buffer = buffer(for: tileIndex) else {
            return
        }
        guard buffer.frameLength > 0 else {
            return
        }

        let chain = playbackChain(for: tileIndex, format: buffer.format)
        updateTimePitch(for: tileIndex, chain: chain)

        chain.player.stop()
        ensureEngineRunning()
        guard engine.isRunning, chain.player.engine === engine else {
            playFallback(tileIndex: tileIndex, loop: false)
            return
        }
        chain.player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                self?.stopPlayback(for: tileIndex)
            }
        }
        if !chain.player.isPlaying {
            chain.player.play()
        }

        startMetering(for: tileIndex, on: chain.mixer)

        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    func startLooping(tileIndex: Int) {
        stopPlayback(for: tileIndex)

        guard let buffer = buffer(for: tileIndex) else {
            return
        }
        guard buffer.frameLength > 0 else {
            return
        }

        let chain = playbackChain(for: tileIndex, format: buffer.format)
        updateTimePitch(for: tileIndex, chain: chain)

        ensureEngineRunning()
        guard engine.isRunning, chain.player.engine === engine else {
            playFallback(tileIndex: tileIndex, loop: true)
            return
        }
        loopingTiles.insert(tileIndex)
        scheduleLoop(for: tileIndex, buffer: buffer, chain: chain)
    }

    func stopLoopingAfterCurrent(tileIndex: Int) {
        if let fallback = fallbackPlayers[tileIndex], fallback.numberOfLoops == -1 {
            fallback.numberOfLoops = 0
        }
        loopingTiles.remove(tileIndex)
    }

    private func scheduleLoop(for tileIndex: Int, buffer: AVAudioPCMBuffer, chain: PlaybackChain) {
        ensureEngineRunning()
        guard engine.isRunning, chain.player.engine === engine else {
            playFallback(tileIndex: tileIndex, loop: true)
            return
        }
        chain.player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.loopingTiles.contains(tileIndex) {
                    self.scheduleLoop(for: tileIndex, buffer: buffer, chain: chain)
                } else {
                    self.stopPlayback(for: tileIndex)
                }
            }
        }

        ensureEngineRunning()
        if !chain.player.isPlaying {
            chain.player.play()
        }

        startMetering(for: tileIndex, on: chain.mixer)
    }

    private func stopPlayback(for tileIndex: Int) {
        loopingTiles.remove(tileIndex)
        if let chain = playbackChains[tileIndex] {
            chain.player.stop()
            stopMetering(for: tileIndex, on: chain.mixer)
        }
        if let fallback = fallbackPlayers[tileIndex] {
            fallback.stop()
            fallbackPlayers[tileIndex] = nil
            stopFallbackMetering(for: tileIndex)
        }
    }

    func hasRecording(for tileIndex: Int) -> Bool {
        let url = audioFileURL(for: tileIndex)
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Playback Speed

    func getPlaybackSpeed(for tileIndex: Int) -> Float {
        playbackSpeeds[tileIndex] ?? Self.defaultSpeed
    }

    func setPlaybackSpeed(for tileIndex: Int, speed: Float) {
        let clampedSpeed = min(max(speed, Self.minSpeed), Self.maxSpeed)
        let steppedSpeed = (clampedSpeed / Self.speedStep).rounded() * Self.speedStep
        let normalizedSpeed = min(max(steppedSpeed, Self.minSpeed), Self.maxSpeed)
        playbackSpeeds[tileIndex] = normalizedSpeed

        if let chain = playbackChains[tileIndex] {
            updateTimePitch(for: tileIndex, chain: chain)
        }
        if let fallback = fallbackPlayers[tileIndex], fallback.isPlaying {
            fallback.rate = normalizedSpeed
        }
    }

    func resetPlaybackSpeed(for tileIndex: Int) {
        playbackSpeeds[tileIndex] = Self.defaultSpeed

        if let chain = playbackChains[tileIndex] {
            updateTimePitch(for: tileIndex, chain: chain)
        }
        if let fallback = fallbackPlayers[tileIndex], fallback.isPlaying {
            fallback.rate = Self.defaultSpeed
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Clear Recording

    func clearRecording(for tileIndex: Int) {
        stopPlayback(for: tileIndex)

        playbackSpeeds[tileIndex] = nil
        playbackLevels[tileIndex] = nil
        buffers[tileIndex] = nil

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

    // MARK: - Playback Helpers

    private func playbackChain(for tileIndex: Int, format: AVAudioFormat) -> PlaybackChain {
        if let chain = playbackChains[tileIndex], formatsMatch(chain.format, format) {
            return chain
        }

        if let existing = playbackChains[tileIndex] {
            stopMetering(for: tileIndex, on: existing.mixer)
            engine.detach(existing.player)
            engine.detach(existing.timePitchA)
            engine.detach(existing.timePitchB)
            engine.detach(existing.mixer)
            playbackChains[tileIndex] = nil
        }

        let wasRunning = engine.isRunning
        if wasRunning {
            engine.stop()
        }

        let player = AVAudioPlayerNode()
        let timePitchA = AVAudioUnitTimePitch()
        let timePitchB = AVAudioUnitTimePitch()
        let mixer = AVAudioMixerNode()

        engine.attach(player)
        engine.attach(timePitchA)
        engine.attach(timePitchB)
        engine.attach(mixer)

        engine.connect(player, to: timePitchA, format: format)
        engine.connect(timePitchA, to: timePitchB, format: format)
        engine.connect(timePitchB, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        engine.prepare()

        let chain = PlaybackChain(player: player, timePitchA: timePitchA, timePitchB: timePitchB, mixer: mixer, format: format)
        playbackChains[tileIndex] = chain
        updateTimePitch(for: tileIndex, chain: chain)

        if wasRunning {
            ensureEngineRunning()
        }

        return chain
    }

    private func buffer(for tileIndex: Int) -> AVAudioPCMBuffer? {
        if let cached = buffers[tileIndex] {
            return cached
        }

        let url = audioFileURL(for: tileIndex)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }
            try file.read(into: buffer)
            buffers[tileIndex] = buffer
            return buffer
        } catch {
            print("Failed to load audio buffer: \(error)")
            return nil
        }
    }

    private func updateTimePitch(for tileIndex: Int, chain: PlaybackChain) {
        let speed = playbackSpeeds[tileIndex] ?? Self.defaultSpeed
        let rateComponent = Float(sqrt(Double(speed)))
        chain.timePitchA.rate = rateComponent
        chain.timePitchB.rate = rateComponent
        chain.timePitchB.pitch = pitchCents(for: speed)
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate && lhs.channelCount == rhs.channelCount
    }

    private func pitchCents(for speed: Float) -> Float {
        guard speed != 1.0 else { return 0 }
        let octaves = log2(Double(speed))

        if speed > 1.0 {
            let boosted = Float(octaves * 1200.0 * 1.25)
            return min(boosted, 2400)
        } else {
            let softened = Float(octaves * 1200.0 * 0.35)
            return max(softened, -600)
        }
    }

    // MARK: - Metering

    private func startMetering(for tileIndex: Int, on node: AVAudioNode) {
        stopMetering(for: tileIndex, on: node)

        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.rmsLevel(from: buffer)
            DispatchQueue.main.async {
                self.playbackLevels[tileIndex] = level
            }
        }

        activeTaps.insert(tileIndex)
    }

    private func stopMetering(for tileIndex: Int, on node: AVAudioNode) {
        if activeTaps.contains(tileIndex) {
            node.removeTap(onBus: 0)
            activeTaps.remove(tileIndex)
        }
        playbackLevels[tileIndex] = 0
    }

    private func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        let data = channelData.pointee
        var sum: Float = 0
        for index in 0..<frames {
            let value = data[index]
            sum += value * value
        }
        let rms = sqrt(sum / Float(frames))
        let normalized = min(1.0, max(0.0, rms * 6.0))
        return normalized
    }

    // MARK: - Fallback Playback

    private func playFallback(tileIndex: Int, loop: Bool) {
        stopFallbackMetering(for: tileIndex)

        let url = audioFileURL(for: tileIndex)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = playbackSpeeds[tileIndex] ?? Self.defaultSpeed
            player.numberOfLoops = loop ? -1 : 0
            player.isMeteringEnabled = true
            player.prepareToPlay()
            player.play()

            fallbackPlayers[tileIndex] = player
            startFallbackMetering(for: tileIndex, player: player)
        } catch {
            print("Fallback playback failed: \(error)")
        }
    }

    private func startFallbackMetering(for tileIndex: Int, player: AVAudioPlayer) {
        stopFallbackMetering(for: tileIndex)

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self, weak player] _ in
            guard let self = self, let player = player else {
                self?.stopFallbackMetering(for: tileIndex)
                return
            }

            guard player.isPlaying else {
                self.stopFallbackMetering(for: tileIndex)
                self.fallbackPlayers[tileIndex] = nil
                return
            }

            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            let linear = pow(10.0, power / 20.0)
            let normalized = min(1.0, max(0.0, (linear - 0.02) / 0.98))
            self.playbackLevels[tileIndex] = Float(normalized)
        }

        fallbackMeterTimers[tileIndex] = timer
    }

    private func stopFallbackMetering(for tileIndex: Int) {
        fallbackMeterTimers[tileIndex]?.invalidate()
        fallbackMeterTimers[tileIndex] = nil
        playbackLevels[tileIndex] = 0
    }
}
