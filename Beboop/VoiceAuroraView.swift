import SwiftUI
import AVFoundation
import Accelerate

struct VoiceAuroraView: View {
    @StateObject private var audioProcessor = AuroraAudioProcessor()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let currentTime = timeline.date.timeIntervalSinceReferenceDate
                    let level = Double(audioProcessor.smoothedLevel)
                    let pitch = Double(audioProcessor.dominantPitch)

                    drawBackground(context: &context, size: size, time: currentTime, level: level)
                    drawAurora(context: &context, size: size, time: currentTime, level: level, pitch: pitch)
                    drawSparkles(context: &context, size: size, time: currentTime, level: level)
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

    // MARK: - Background

    private func drawBackground(context: inout GraphicsContext, size: CGSize, time: Double, level: Double) {
        let baseBrightness = 0.02 + level * 0.03
        let topHue = 0.7 + sin(time * 0.1) * 0.05
        let bottomHue = 0.85 + cos(time * 0.08) * 0.05

        let topColor = Color(hue: topHue, saturation: 0.8, brightness: baseBrightness)
        let bottomColor = Color(hue: bottomHue, saturation: 0.7, brightness: baseBrightness * 0.5)

        let gradient = Gradient(colors: [topColor, bottomColor])
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )
    }

    // MARK: - Aurora Ribbons

    private func drawAurora(context: inout GraphicsContext, size: CGSize, time: Double, level: Double, pitch: Double) {
        for layer in 0..<5 {
            let layerOffset = Double(layer) * 0.2
            let layerIntensity = 1.0 - Double(layer) * 0.15
            let intensity = level * layerIntensity

            drawAuroraRibbon(
                context: &context,
                size: size,
                time: time,
                layer: layer,
                layerOffset: layerOffset,
                intensity: intensity,
                pitch: pitch
            )
        }
    }

    private func drawAuroraRibbon(
        context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        layer: Int,
        layerOffset: Double,
        intensity: Double,
        pitch: Double
    ) {
        let ribbonPath = createRibbonPath(size: size, time: time, layer: layer, layerOffset: layerOffset, intensity: intensity)
        let ribbonColor = calculateRibbonColor(time: time, layer: layer, pitch: pitch, intensity: intensity)

        let gradient = Gradient(stops: [
            .init(color: ribbonColor.opacity(0.6 + intensity * 0.3), location: 0),
            .init(color: ribbonColor.opacity(0.3 + intensity * 0.2), location: 0.3),
            .init(color: ribbonColor.opacity(0), location: 1)
        ])

        let gradientStart = CGPoint(x: size.width / 2, y: 0)
        let gradientEnd = CGPoint(x: size.width / 2, y: size.height)

        // Blurred glow layer
        var blurredContext = context
        let blurRadius = 20 + intensity * 30
        blurredContext.addFilter(.blur(radius: blurRadius))
        blurredContext.fill(ribbonPath, with: .linearGradient(gradient, startPoint: gradientStart, endPoint: gradientEnd))

        // Sharp overlay for definition
        context.fill(ribbonPath, with: .linearGradient(gradient, startPoint: gradientStart, endPoint: gradientEnd))
    }

    private func createRibbonPath(size: CGSize, time: Double, layer: Int, layerOffset: Double, intensity: Double) -> Path {
        let segments = 60
        let baseY = size.height * (0.3 + layerOffset * 0.4)
        let layerSpeed = 0.5 + Double(layer) * 0.1
        let points = ribbonPoints(
            segments: segments,
            width: size.width,
            baseY: baseY,
            time: time,
            layerSpeed: layerSpeed,
            layerOffset: layerOffset,
            intensity: intensity
        )

        return Path { path in
            for (index, point) in points.enumerated() {
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            path.addLine(to: CGPoint(x: size.width, y: size.height + 50))
            path.addLine(to: CGPoint(x: 0, y: size.height + 50))
            path.closeSubpath()
        }
    }

    private func ribbonPoints(
        segments: Int,
        width: CGFloat,
        baseY: CGFloat,
        time: Double,
        layerSpeed: Double,
        layerOffset: Double,
        intensity: Double
    ) -> [CGPoint] {
        (0...segments).map { index in
            let progress = Double(index) / Double(segments)
            let x = width * CGFloat(index) / CGFloat(segments)

            let wave1 = sin(progress * 4 * .pi + time * layerSpeed) * 40
            let wave2 = sin(progress * 7 * .pi + time * 0.7 + layerOffset) * 25
            let wave3 = sin(progress * 2 * .pi + time * 0.3) * 60
            let audioWave = sin(progress * 10 * .pi + time * 2) * intensity * 80

            let y = baseY + wave1 + wave2 + wave3 + audioWave
            return CGPoint(x: x, y: y)
        }
    }

    private func calculateRibbonColor(time: Double, layer: Int, pitch: Double, intensity: Double) -> Color {
        // Low pitch = warm colors (red/orange), high pitch = cool colors (cyan/blue)
        let pitchHue = 0.5 - pitch * 0.4
        let layerHueOffset = Double(layer) * 0.08
        let timeHueOffset = sin(time * 0.2) * 0.05
        let baseHue = pitchHue + layerHueOffset + timeHueOffset

        var normalizedHue = baseHue.truncatingRemainder(dividingBy: 1.0)
        if normalizedHue < 0 { normalizedHue += 1 }

        let saturation = 0.6 + intensity * 0.4
        let brightness = 0.3 + intensity * 0.5

        return Color(hue: normalizedHue, saturation: saturation, brightness: brightness)
    }

    // MARK: - Sparkles

    private func drawSparkles(context: inout GraphicsContext, size: CGSize, time: Double, level: Double) {
        guard level > 0.1 else { return }

        let sparkleCount = Int(level * 30) + 5

        for i in 0..<sparkleCount {
            drawSingleSparkle(context: &context, size: size, time: time, level: level, index: i)
        }
    }

    private func drawSingleSparkle(context: inout GraphicsContext, size: CGSize, time: Double, level: Double, index: Int) {
        let seed = Double(index) * 1234.5678
        let x = (sin(seed) * 0.5 + 0.5) * size.width
        let baseY = (cos(seed * 1.1) * 0.5 + 0.5) * size.height * 0.7

        let drift = (time * 20 + seed).truncatingRemainder(dividingBy: size.height)
        let y = baseY - drift

        guard y > 0 else { return }

        let twinkle = (sin(time * 5 + seed) + 1) / 2
        let sparkleSize = (2 + level * 4) * twinkle

        // Glow
        let sparkleColor = Color.white.opacity(0.3 + twinkle * 0.5 * level)
        let sparkleRect = CGRect(
            x: x - sparkleSize / 2,
            y: y - sparkleSize / 2,
            width: sparkleSize,
            height: sparkleSize
        )

        var sparkleContext = context
        sparkleContext.addFilter(.blur(radius: 2))
        sparkleContext.fill(Path(ellipseIn: sparkleRect), with: .color(sparkleColor))

        // Bright center
        let centerSize = sparkleSize / 2
        let centerRect = CGRect(
            x: x - centerSize / 2,
            y: y - centerSize / 2,
            width: centerSize,
            height: centerSize
        )
        context.fill(Path(ellipseIn: centerRect), with: .color(.white.opacity(twinkle * level)))
    }
}

// MARK: - Audio Processor

@MainActor
final class AuroraAudioProcessor: ObservableObject {
    @Published var smoothedLevel: Float = 0
    @Published var dominantPitch: Float = 0.5

    private var audioEngine: AVAudioEngine?
    private var isListening = false
    private var levelHistory: [Float] = []
    private let levelHistorySize = 8

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
    }

    private func setupAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.isListening = true
        } catch {
            print("Aurora audio setup failed: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        let data = channelData.pointee

        // Calculate RMS level
        var sum: Float = 0
        for i in 0..<frames {
            let value = data[i]
            sum += value * value
        }
        let rms = sqrt(sum / Float(frames))

        let normalizedLevel = min(1.0, rms * 8.0)
        let curvedLevel = pow(normalizedLevel, 0.7)

        // Estimate pitch using zero-crossing rate
        var zeroCrossings = 0
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

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.levelHistory.append(curvedLevel)
            if self.levelHistory.count > self.levelHistorySize {
                self.levelHistory.removeFirst()
            }
            self.smoothedLevel = self.levelHistory.reduce(0, +) / Float(self.levelHistory.count)
            self.dominantPitch = self.dominantPitch * 0.85 + normalizedPitch * 0.15
        }
    }
}

#Preview {
    VoiceAuroraView()
}
