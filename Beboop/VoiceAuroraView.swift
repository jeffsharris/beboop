import SwiftUI
import AVFoundation

struct VoiceAuroraView: View {
    private struct Ripple: Identifiable {
        let id = UUID()
        let origin: CGPoint
        let startTime: Double
        let amplitude: Double
        let pitch: Double
    }

    @StateObject private var audioProcessor = AuroraAudioProcessor()
    @State private var ripples: [Ripple] = []
    @State private var lastUpdateTime: Date = Date()
    @State private var lastRippleTime: Date = .distantPast

    private let rippleCooldown: TimeInterval = 0.18
    private let rippleMinLevel: Double = 0.08
    private let rippleMaxAge: Double = 2.8
    private let rippleBaseSpeed: Double = 140

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let currentTime = timeline.date.timeIntervalSinceReferenceDate
                    let level = Double(audioProcessor.smoothedLevel)
                    let pitch = Double(audioProcessor.dominantPitch)

                    drawWaterBackground(context: &context, size: size, time: currentTime, level: level, pitch: pitch)
                    drawRipples(context: &context, size: size, time: currentTime)
                }
                .onChange(of: timeline.date) { _, newDate in
                    updateRipples(at: newDate)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            audioProcessor.startListening()
        }
        .onDisappear {
            audioProcessor.stopListening()
        }
    }

    private func updateRipples(at date: Date) {
        let currentTime = date.timeIntervalSinceReferenceDate
        let level = Double(audioProcessor.smoothedLevel)
        let pitch = Double(audioProcessor.dominantPitch)
        let source = audioProcessor.sourcePoint

        if level > rippleMinLevel, date.timeIntervalSince(lastRippleTime) > rippleCooldown {
            let amplitude = ((level - rippleMinLevel) / max(0.001, 1 - rippleMinLevel)).clamped(to: 0...1)
            let ripple = Ripple(origin: source, startTime: currentTime, amplitude: amplitude, pitch: pitch)
            ripples.append(ripple)
            lastRippleTime = date
        }

        ripples.removeAll { currentTime - $0.startTime > rippleMaxAge }
        lastUpdateTime = date
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

    private func drawRipples(context: inout GraphicsContext, size: CGSize, time: Double) {
        for ripple in ripples {
            let age = time - ripple.startTime
            guard age >= 0 else { continue }

            let progress = age / rippleMaxAge
            let radius = rippleBaseSpeed * age + ripple.amplitude * 40
            let intensity = (1 - progress).clamped(to: 0...1) * (0.25 + ripple.amplitude * 0.75)

            let hue = (0.58 - ripple.pitch * 0.35).clamped(to: 0...1)
            let color = Color(hue: hue, saturation: 0.7, brightness: 0.95)

            let origin = CGPoint(x: ripple.origin.x * size.width,
                                 y: ripple.origin.y * size.height)
            let rect = CGRect(
                x: origin.x - radius,
                y: origin.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            let lineWidth = 1.5 + ripple.amplitude * 4
            var rippleContext = context
            rippleContext.addFilter(.blur(radius: 3))
            rippleContext.stroke(Path(ellipseIn: rect),
                                 with: .color(color.opacity(intensity * 0.35)),
                                 lineWidth: lineWidth + 4)

            context.stroke(Path(ellipseIn: rect),
                           with: .color(color.opacity(intensity)),
                           lineWidth: lineWidth)
        }
    }
}

// MARK: - Audio Processor

@MainActor
final class AuroraAudioProcessor: ObservableObject {
    @Published var smoothedLevel: Float = 0
    @Published var dominantPitch: Float = 0.5
    @Published var sourcePoint: CGPoint = CGPoint(x: 0.5, y: 0.9)

    private var audioEngine: AVAudioEngine?
    private var gateMixer: AVAudioMixerNode?
    private var delayNode: AVAudioUnitDelay?
    private var isListening = false
    private var levelHistory: [Float] = []
    private let levelHistorySize = 8
    private var echoMix: Float = 0
    private var isBuiltInMic = true

    private let echoGateThreshold: Float = 0.09
    private let echoGateRelease: Float = 0.9
    private let sourceSmoothing: CGFloat = 0.15

    func startListening() {
        guard !isListening else { return }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.setupAudioEngine()
                }
            }
        }
    }

    func stopListening() {
        isListening = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        gateMixer = nil
        delayNode = nil
    }

    private func setupAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try session.setActive(true)

            isBuiltInMic = session.currentRoute.inputs.contains { $0.portType == .builtInMic }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            let gateMixer = AVAudioMixerNode()
            gateMixer.outputVolume = 0

            let delay = AVAudioUnitDelay()
            delay.delayTime = 0.24
            delay.feedback = 36
            delay.lowPassCutoff = 9000
            delay.wetDryMix = 35

            engine.attach(gateMixer)
            engine.attach(delay)
            engine.connect(inputNode, to: gateMixer, format: format)
            engine.connect(gateMixer, to: delay, format: format)
            engine.connect(delay, to: engine.mainMixerNode, format: format)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.gateMixer = gateMixer
            self.delayNode = delay
            self.isListening = true
        } catch {
            print("Aurora audio setup failed: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        let channelCount = Int(buffer.format.channelCount)
        let rmsLeft = rmsLevel(channelData[0], frames: frames)
        var rms = rmsLeft
        var targetPoint = CGPoint(x: 0.5, y: 0.9)

        if channelCount > 1, isBuiltInMic {
            let rmsRight = rmsLevel(channelData[1], frames: frames)
            rms = (rmsLeft + rmsRight) * 0.5
            let balance = (rmsLeft - rmsRight) / max(0.0001, rmsLeft + rmsRight)
            let x = (0.5 + CGFloat(balance) * 0.35).clamped(to: 0.1...0.9)
            targetPoint = CGPoint(x: x, y: 0.85)
        }

        let normalizedLevel = min(1.0, rms * 8.0)
        let curvedLevel = pow(normalizedLevel, 0.7)

        var zeroCrossings = 0
        let data = channelData[0]
        for i in 1..<frames {
            let current = data[i]
            let previous = data[i - 1]
            if (current >= 0 && previous < 0) || (current < 0 && previous >= 0) {
                zeroCrossings += 1
            }
        }

        let sampleRate = buffer.format.sampleRate
        let estimatedFreq = (Double(zeroCrossings) / 2.0) * sampleRate / Double(frames)
        let logFreq = log2(estimatedFreq / 100.0) / 3.3
        let normalizedPitch = Float(min(1.0, max(0.0, logFreq)))

        let targetEcho: Float = normalizedLevel > echoGateThreshold ? 1.0 : 0.0
        echoMix = echoMix * echoGateRelease + targetEcho * (1 - echoGateRelease)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.levelHistory.append(curvedLevel)
            if self.levelHistory.count > self.levelHistorySize {
                self.levelHistory.removeFirst()
            }
            self.smoothedLevel = self.levelHistory.reduce(0, +) / Float(self.levelHistory.count)
            self.dominantPitch = self.dominantPitch * 0.85 + normalizedPitch * 0.15

            let nextX = self.sourcePoint.x * (1 - self.sourceSmoothing) + targetPoint.x * self.sourceSmoothing
            let nextY = self.sourcePoint.y * (1 - self.sourceSmoothing) + targetPoint.y * self.sourceSmoothing
            self.sourcePoint = CGPoint(x: nextX, y: nextY)

            self.gateMixer?.outputVolume = self.echoMix
            self.delayNode?.wetDryMix = 28 + 32 * self.echoMix
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
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

#Preview {
    VoiceAuroraView()
}
