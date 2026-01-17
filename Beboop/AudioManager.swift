import AVFoundation
import UIKit

final class AudioManager: NSObject, ObservableObject {
    private struct PlaybackChain {
        let player: AVAudioPlayerNode
        let timePitch: AVAudioUnitTimePitch
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
    private var pendingActivationWorkItem: DispatchWorkItem?

    @Published var isRecording = false
    @Published var currentRecordingTile: Int?
    @Published var playbackSpeeds: [Int: Float] = [:]
    @Published var playbackLevels: [Int: Float] = [:]

    // Speed limits and allowed values
    static let minSpeed: Float = 0.1
    static let maxSpeed: Float = 10.0
    static let defaultSpeed: Float = 1.0

    // Allowed speed values:
    // Slowdown: 1.0, 0.95, 0.90, 0.85, ... down to 0.10 (5% steps)
    // Speedup: 1.0, 1.5, 2.0, 2.5, ... up to 10.0 (0.5x steps)
    static let allowedSpeeds: [Float] = {
        var speeds: [Float] = []
        // Slowdown values: 0.10, 0.15, 0.20, ... 0.95
        var slow: Float = 0.10
        while slow < 1.0 {
            speeds.append(slow)
            slow += 0.05
        }
        // Normal speed
        speeds.append(1.0)
        // Speedup values: 1.5, 2.0, 2.5, ... 10.0
        var fast: Float = 1.5
        while fast <= 10.0 {
            speeds.append(fast)
            fast += 0.5
        }
        return speeds.sorted()
    }()

    override init() {
        super.init()
    }

    func activate(after delay: TimeInterval = 0) {
        pendingActivationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.activateNow()
        }
        pendingActivationWorkItem = workItem

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    func deactivate() {
        pendingActivationWorkItem?.cancel()
        pendingActivationWorkItem = nil
        stopRecording()
        stopAllPlayback()
        engine.stop()
        engine.reset()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Audio session deactivation failed: \(error)")
        }
    }

    private func activateNow() {
        configureAudioSession()
    }

    private func configureAudioSession() {
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
            configureAudioSession()
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
        configureAudioSession()

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

    private func stopAllPlayback() {
        let activeTiles = Set(playbackChains.keys)
            .union(fallbackPlayers.keys)
            .union(loopingTiles)
            .union(activeTaps)

        for tileIndex in activeTiles {
            stopPlayback(for: tileIndex)
        }

        activeTaps.removeAll()
        playbackLevels.removeAll()
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
        let snappedSpeed = Self.snapToAllowedSpeed(clampedSpeed)
        playbackSpeeds[tileIndex] = snappedSpeed

        if let chain = playbackChains[tileIndex] {
            updateTimePitch(for: tileIndex, chain: chain)
        }
        if let fallback = fallbackPlayers[tileIndex], fallback.isPlaying {
            fallback.rate = snappedSpeed
        }
    }

    /// Snaps a speed value to the nearest allowed speed threshold
    private static func snapToAllowedSpeed(_ speed: Float) -> Float {
        var closest = allowedSpeeds[0]
        var smallestDiff = abs(speed - closest)
        for allowed in allowedSpeeds {
            let diff = abs(speed - allowed)
            if diff < smallestDiff {
                smallestDiff = diff
                closest = allowed
            }
        }
        return closest
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
            engine.detach(existing.timePitch)
            engine.detach(existing.mixer)
            playbackChains[tileIndex] = nil
        }

        let wasRunning = engine.isRunning
        if wasRunning {
            engine.stop()
        }

        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        let mixer = AVAudioMixerNode()

        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(mixer)

        // Simple chain: player -> timePitch -> mixer -> mainMixer
        // AVAudioUnitTimePitch handles time-stretching with pitch preservation
        // (like podcast apps using SOLA/phase vocoder algorithms)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        engine.prepare()

        let chain = PlaybackChain(player: player, timePitch: timePitch, mixer: mixer, format: format)
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

    /// Updates the time-pitch unit for podcast-style time-stretching.
    /// AVAudioUnitTimePitch uses a phase vocoder algorithm that preserves pitch
    /// while changing playback speed - the same approach used by podcast apps.
    /// Setting pitch to 0 keeps the original pitch; rate controls the speed.
    private func updateTimePitch(for tileIndex: Int, chain: PlaybackChain) {
        let speed = playbackSpeeds[tileIndex] ?? Self.defaultSpeed
        chain.timePitch.rate = speed
        chain.timePitch.pitch = 0  // Preserve original pitch
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate && lhs.channelCount == rhs.channelCount
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
