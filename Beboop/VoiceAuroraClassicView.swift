import SwiftUI
import AVFoundation

struct VoiceAuroraClassicView: View {
    private enum Edge {
        case bottom
    }

    private struct Wave: Identifiable {
        let id = UUID()
        let edge: Edge
        let edgePosition: CGFloat
        let startTime: Double
        let amplitude: Double
        let pitch: Double
        let phase: Double
    }

    @EnvironmentObject private var audioCoordinator: AudioCoordinator
    @StateObject private var audioProcessor = ClassicAuroraAudioProcessor()
    @State private var waves: [Wave] = []
    @State private var lastWaveTime: Date = .distantPast

    private let waveCooldown: TimeInterval = 0.16
    private let waveMinLevel: Double = 0.08
    private let waveMaxAge: Double = 2.9
    private let waveBaseSpeed: Double = 170
    private let classicSourcePoint = CGPoint(x: 0.5, y: 0.85)

    var body: some View {
        GeometryReader { _ in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let currentTime = timeline.date.timeIntervalSinceReferenceDate
                    let level = Double(audioProcessor.smoothedLevel)
                    let pitch = Double(audioProcessor.dominantPitch)

                    drawWaterBackground(context: &context, size: size, time: currentTime, level: level, pitch: pitch)
                    drawWaves(context: &context, size: size, time: currentTime)
                }
                .onChange(of: timeline.date) { _, newDate in
                    updateWaves(at: newDate)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            audioCoordinator.register(mode: .voiceAuroraClassic,
                                      start: {
                                          audioProcessor.startListening()
                                      },
                                      stop: { completion in
                                          audioProcessor.stopListening(completion: completion)
                                      })
        }
        .onDisappear {
            audioCoordinator.unregister(mode: .voiceAuroraClassic)
        }
    }

    private func updateWaves(at date: Date) {
        let currentTime = date.timeIntervalSinceReferenceDate
        let level = Double(audioProcessor.smoothedLevel)
        let pitch = Double(audioProcessor.dominantPitch)

        if level > waveMinLevel, date.timeIntervalSince(lastWaveTime) > waveCooldown {
            let amplitude = ((level - waveMinLevel) / max(0.001, 1 - waveMinLevel)).clamped(to: 0...1)
            let wave = Wave(edge: .bottom,
                            edgePosition: classicSourcePoint.x,
                            startTime: currentTime,
                            amplitude: amplitude,
                            pitch: pitch,
                            phase: Double.random(in: 0...(.pi * 2)))
            waves.append(wave)
            lastWaveTime = date
        }

        waves.removeAll { currentTime - $0.startTime > waveMaxAge }
    }

    private func drawWaterBackground(context: inout GraphicsContext,
                                     size: CGSize,
                                     time: Double,
                                     level: Double,
                                     pitch: Double) {
        let shimmer = 0.02 * sin(time * 0.7)
        let depth = 0.18 + level * 0.08
        let hueShift = 0.55 - pitch * 0.2

        let topColor = Color(hue: hueShift + 0.02 + shimmer,
                             saturation: 0.6,
                             brightness: depth + 0.05)
        let bottomColor = Color(hue: hueShift + 0.05,
                                saturation: 0.7,
                                brightness: depth * 0.6)

        let gradient = Gradient(colors: [topColor, bottomColor])
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )
    }

    private func drawWaves(context: inout GraphicsContext, size: CGSize, time: Double) {
        for wave in waves {
            let age = time - wave.startTime
            guard age >= 0 else { continue }

            let progress = age / waveMaxAge
            let radius = waveBaseSpeed * age + wave.amplitude * 60
            let intensity = (1 - progress).clamped(to: 0...1)
            let waveAlpha = intensity * (0.35 + wave.amplitude * 0.65)
            let bandThickness = 34.0 + wave.amplitude * 70

            let hueBase = (0.6 - wave.pitch * 0.35).clamped(to: 0...1)
            let hueDrift = sin(age * 1.4 + wave.phase) * 0.08
            let hue1 = (hueBase + hueDrift).truncatingRemainder(dividingBy: 1)
            let hue2 = (hue1 + 0.12).truncatingRemainder(dividingBy: 1)
            let hue3 = (hue1 + 0.24).truncatingRemainder(dividingBy: 1)
            let hue4 = (hue1 + 0.36).truncatingRemainder(dividingBy: 1)
            let baseColor = Color(hue: hue1, saturation: 0.84, brightness: 0.96)
            let midColor = Color(hue: hue2, saturation: 0.78, brightness: 0.98)
            let accentColor = Color(hue: hue3, saturation: 0.7, brightness: 1.0)
            let highlightColor = Color(hue: hue4, saturation: 0.62, brightness: 1.0)

            let path = waveBandPath(for: wave,
                                    size: size,
                                    time: time,
                                    radius: radius,
                                    thickness: bandThickness)
            guard !path.isEmpty else { continue }

            var glowContext = context
            glowContext.addFilter(.blur(radius: 16))
            glowContext.fill(path,
                             with: .color(baseColor.opacity(waveAlpha * 0.3)))

            let depth = CGFloat(min(radius + bandThickness + 40, Double(max(size.width, size.height))))
            let (gradientStart, gradientEnd) = waveGradientPoints(for: wave, size: size, depth: depth)
            let gradient = Gradient(stops: [
                .init(color: baseColor.opacity(waveAlpha * 0.95), location: 0),
                .init(color: midColor.opacity(waveAlpha * 0.75), location: 0.4),
                .init(color: accentColor.opacity(waveAlpha * 0.55), location: 0.75),
                .init(color: highlightColor.opacity(waveAlpha * 0.35), location: 0.95),
                .init(color: .clear, location: 1)
            ])

            var colorContext = context
            colorContext.blendMode = .screen
            colorContext.fill(path,
                              with: .linearGradient(gradient,
                                                    startPoint: gradientStart,
                                                    endPoint: gradientEnd))
            colorContext.stroke(path,
                                with: .color(accentColor.opacity(waveAlpha * 0.45)),
                                lineWidth: 0.9)
        }
    }

    private func waveGradientPoints(for wave: Wave,
                                    size: CGSize,
                                    depth: CGFloat) -> (CGPoint, CGPoint) {
        return (CGPoint(x: wave.edgePosition * size.width, y: size.height),
                CGPoint(x: wave.edgePosition * size.width, y: max(0, size.height - depth)))
    }

    private func waveBandPath(for wave: Wave,
                              size: CGSize,
                              time: Double,
                              radius: Double,
                              thickness: Double) -> Path {
        let segments = 120
        let chaos = 6.0 + wave.amplitude * 18.0
        let band = radius + thickness + 70

        let length = size.width
        let center = wave.edgePosition * size.width

        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        outer.reserveCapacity(segments + 1)
        inner.reserveCapacity(segments + 1)

        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let tangent = CGFloat(t) * length
            let delta = Double(tangent - center)

            if abs(delta) > band { continue }

            let base = max(0, radius * radius - delta * delta)
            let radial = sqrt(base)
            let noise = sin(delta * 0.08 + time * 1.2 + wave.phase) * chaos
                + sin(delta * 0.18 + time * 0.7 + wave.phase * 0.7) * (chaos * 0.4)
            let noiseInner = sin(delta * 0.12 + time * 1.05 + wave.phase * 0.6) * (chaos * 0.35)
            let outerRadius = max(0, radial + noise + thickness * 0.5)
            let innerRadius = max(0, radial - thickness + noiseInner)
            let clippedInner = min(innerRadius, max(0, outerRadius - 2))

            guard outerRadius > 0 else { continue }

            outer.append(CGPoint(x: tangent, y: size.height - outerRadius))
            inner.append(CGPoint(x: tangent, y: size.height - clippedInner))
        }

        guard outer.count > 2, inner.count > 2 else { return Path() }

        var path = Path()
        path.move(to: outer[0])
        for point in outer.dropFirst() {
            path.addLine(to: point)
        }
        for point in inner.reversed() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

final class ClassicAuroraAudioProcessor: NSObject, ObservableObject {
    @Published var smoothedLevel: Float = 0
    @Published var dominantPitch: Float = 0.5

    private var audioEngine: AVAudioEngine?
    private var gateMixer: AVAudioMixerNode?
    private var delayNode: AVAudioUnitDelay?
    private var boostNode: AVAudioUnitEQ?
    private var isListening = false
    private var levelHistory: [Float] = []
    private let levelHistorySize = 8
    private var echoMix: Float = 0
    private var pendingStartWorkItem: DispatchWorkItem?

    private let echoGateThreshold: Float = 0.1
    private let echoGateAttack: Float = 0.75
    private let echoGateRelease: Float = 0.88
    private let echoWetMixBase: Float = 85
    private let echoWetMixRange: Float = 15
    private let echoBoostDb: Float = 18

    func startListening(after delay: TimeInterval = 0) {
        pendingStartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.startListeningNow()
        }
        pendingStartWorkItem = workItem

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    private func startListeningNow() {
        guard !isListening else { return }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.setupAudioEngine()
                } else {
                    print("Microphone permission denied")
                }
            }
        }
    }

    func stopListening(completion: (() -> Void)? = nil) {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        isListening = false
        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        gateMixer = nil
        delayNode = nil
        boostNode = nil
        deactivateAudioSession()
        completion?()
    }

    private func setupAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            deactivateAudioSession()
            try configureAudioSession(session)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: format.sampleRate,
                                          channels: format.channelCount,
                                          interleaved: false) ?? format

            let gateMixer = AVAudioMixerNode()
            gateMixer.outputVolume = 0

            let delay = AVAudioUnitDelay()
            delay.delayTime = 0.5
            delay.feedback = 68
            delay.lowPassCutoff = 12_000
            delay.wetDryMix = 50

            let boost = AVAudioUnitEQ(numberOfBands: 1)
            boost.globalGain = echoBoostDb

            engine.attach(gateMixer)
            engine.attach(delay)
            engine.attach(boost)
            engine.connect(inputNode, to: gateMixer, format: format)
            engine.connect(gateMixer, to: delay, format: format)
            engine.connect(delay, to: boost, format: format)
            engine.connect(boost, to: engine.mainMixerNode, format: format)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.gateMixer = gateMixer
            self.delayNode = delay
            self.boostNode = boost
            self.isListening = true
        } catch {
            print("Aurora classic audio setup failed: \(error)")
        }
    }

    private func configureAudioSession(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
        try session.setMode(.voiceChat)
        try session.setActive(true)

        let usesReceiver = session.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
        if usesReceiver {
            try session.overrideOutputAudioPort(.speaker)
        }
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Aurora classic audio deactivation failed: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var rms: Float = 0
        var zeroCrossings = 0
        if let channelData = buffer.floatChannelData {
            rms = rmsLevel(channelData[0], frames: frames)
            let data = channelData[0]
            for i in 1..<frames {
                let current = data[i]
                let previous = data[i - 1]
                if (current >= 0 && previous < 0) || (current < 0 && previous >= 0) {
                    zeroCrossings += 1
                }
            }
        } else if let channelData = buffer.int16ChannelData {
            rms = rmsLevelInt16(channelData[0], frames: frames)
            let data = channelData[0]
            for i in 1..<frames {
                let current = data[i]
                let previous = data[i - 1]
                if (current >= 0 && previous < 0) || (current < 0 && previous >= 0) {
                    zeroCrossings += 1
                }
            }
        } else {
            return
        }

        let normalizedLevel = min(1.0, rms * 8.0)
        let curvedLevel = pow(normalizedLevel, 0.7)

        let sampleRate = buffer.format.sampleRate
        let estimatedFreq = (Double(zeroCrossings) / 2.0) * sampleRate / Double(frames)
        let logFreq = log2(estimatedFreq / 100.0) / 3.3
        let normalizedPitch = Float(min(1.0, max(0.0, logFreq)))

        let targetEcho: Float = curvedLevel > echoGateThreshold ? 1.0 : 0.0
        if targetEcho > echoMix {
            echoMix = echoMix * (1 - echoGateAttack) + targetEcho * echoGateAttack
        } else {
            echoMix = echoMix * echoGateRelease + targetEcho * (1 - echoGateRelease)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.levelHistory.append(curvedLevel)
            if self.levelHistory.count > self.levelHistorySize {
                self.levelHistory.removeFirst()
            }
            self.smoothedLevel = self.levelHistory.reduce(0, +) / Float(self.levelHistory.count)
            self.dominantPitch = self.dominantPitch * 0.85 + normalizedPitch * 0.15

            self.gateMixer?.outputVolume = self.echoMix
            self.delayNode?.wetDryMix = self.echoWetMixBase + self.echoWetMixRange * self.echoMix
        }
    }

    private func rmsLevel(_ data: UnsafePointer<Float>, frames: Int) -> Float {
        var sum: Float = 0
        for i in 0..<frames {
            let value = data[i]
            sum += value * value
        }
        return sqrt(sum / Float(frames))
    }

    private func rmsLevelInt16(_ data: UnsafePointer<Int16>, frames: Int) -> Float {
        var sum: Float = 0
        let scale = 1.0 / Float(Int16.max)
        for i in 0..<frames {
            let value = Float(data[i]) * scale
            sum += value * value
        }
        return sqrt(sum / Float(frames))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

#Preview {
    VoiceAuroraClassicView()
        .environmentObject(AudioCoordinator())
}
