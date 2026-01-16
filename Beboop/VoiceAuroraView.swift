import SwiftUI
import AVFoundation
import CoreAudioTypes
import CoreMedia

struct VoiceAuroraView: View {
    private enum Edge {
        case left
        case right
        case top
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

    @StateObject private var audioProcessor = AuroraAudioProcessor()
    @State private var waves: [Wave] = []
    @State private var lastUpdateTime: Date = Date()
    @State private var lastWaveTime: Date = .distantPast

    private let waveCooldown: TimeInterval = 0.16
    private let waveMinLevel: Double = 0.08
    private let waveMaxAge: Double = 2.9
    private let waveBaseSpeed: Double = 170

    var body: some View {
        GeometryReader { geometry in
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
            .overlay(alignment: .bottomLeading) {
                if !audioProcessor.debugText.isEmpty {
                    Text(audioProcessor.debugText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.leading, 12)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
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

    private func updateWaves(at date: Date) {
        let currentTime = date.timeIntervalSinceReferenceDate
        let level = Double(audioProcessor.smoothedLevel)
        let pitch = Double(audioProcessor.dominantPitch)
        let source = audioProcessor.sourcePoint

        if level > waveMinLevel, date.timeIntervalSince(lastWaveTime) > waveCooldown {
            let amplitude = ((level - waveMinLevel) / max(0.001, 1 - waveMinLevel)).clamped(to: 0...1)
            let edge = nearestEdge(for: source)
            let position = edgePosition(for: source, edge: edge)
            let wave = Wave(edge: edge,
                            edgePosition: position,
                            startTime: currentTime,
                            amplitude: amplitude,
                            pitch: pitch,
                            phase: Double.random(in: 0...(.pi * 2)))
            waves.append(wave)
            lastWaveTime = date
        }

        waves.removeAll { currentTime - $0.startTime > waveMaxAge }
        lastUpdateTime = date
    }

    private func nearestEdge(for point: CGPoint) -> Edge {
        let left = point.x
        let right = 1 - point.x
        let top = point.y
        let bottom = 1 - point.y
        let minValue = min(left, right, top, bottom)

        if minValue == left { return .left }
        if minValue == right { return .right }
        if minValue == top { return .top }
        return .bottom
    }

    private func edgePosition(for point: CGPoint, edge: Edge) -> CGFloat {
        switch edge {
        case .left, .right:
            return point.y.clamped(to: 0.05...0.95)
        case .top, .bottom:
            return point.x.clamped(to: 0.05...0.95)
        }
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
        switch wave.edge {
        case .left:
            return (CGPoint(x: 0, y: wave.edgePosition * size.height),
                    CGPoint(x: min(size.width, depth), y: wave.edgePosition * size.height))
        case .right:
            return (CGPoint(x: size.width, y: wave.edgePosition * size.height),
                    CGPoint(x: max(0, size.width - depth), y: wave.edgePosition * size.height))
        case .top:
            return (CGPoint(x: wave.edgePosition * size.width, y: 0),
                    CGPoint(x: wave.edgePosition * size.width, y: min(size.height, depth)))
        case .bottom:
            return (CGPoint(x: wave.edgePosition * size.width, y: size.height),
                    CGPoint(x: wave.edgePosition * size.width, y: max(0, size.height - depth)))
        }
    }

    private func waveBandPath(for wave: Wave,
                              size: CGSize,
                              time: Double,
                              radius: Double,
                              thickness: Double) -> Path {
        let segments = 120
        let chaos = 6.0 + wave.amplitude * 18.0
        let band = radius + thickness + 70

        let length: CGFloat
        let center: CGFloat
        switch wave.edge {
        case .left, .right:
            length = size.height
            center = wave.edgePosition * size.height
        case .top, .bottom:
            length = size.width
            center = wave.edgePosition * size.width
        }

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

            switch wave.edge {
            case .left:
                outer.append(CGPoint(x: outerRadius, y: tangent))
                inner.append(CGPoint(x: clippedInner, y: tangent))
            case .right:
                outer.append(CGPoint(x: size.width - outerRadius, y: tangent))
                inner.append(CGPoint(x: size.width - clippedInner, y: tangent))
            case .top:
                outer.append(CGPoint(x: tangent, y: outerRadius))
                inner.append(CGPoint(x: tangent, y: clippedInner))
            case .bottom:
                outer.append(CGPoint(x: tangent, y: size.height - outerRadius))
                inner.append(CGPoint(x: tangent, y: size.height - clippedInner))
            }
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

// MARK: - Audio Processor

final class AuroraAudioProcessor: NSObject, ObservableObject {
    @Published var smoothedLevel: Float = 0
    @Published var dominantPitch: Float = 0.5
    @Published var sourcePoint: CGPoint = CGPoint(x: 0.5, y: 0.9)
    @Published var debugText: String = ""

    private let captureQueue = DispatchQueue(label: "VoiceAurora.Capture")
    private let foaLayoutTag: AudioChannelLayoutTag = AudioChannelLayoutTag(kAudioChannelLayoutTag_HOA_ACN_SN3D | 4)

    private var captureSession: AVCaptureSession?
    private var captureInput: AVCaptureDeviceInput?
    private var captureOutput: AVCaptureAudioDataOutput?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var gateMixer: AVAudioMixerNode?
    private var delayNode: AVAudioUnitDelay?
    private var boostNode: AVAudioUnitEQ?
    private var playbackFormat: AVAudioFormat?
    private var pendingBuffers = 0
    private let maxPendingBuffers = 4
    private var isListening = false
    private var levelHistory: [Float] = []
    private let levelHistorySize = 8
    private var echoMix: Float = 0
    private var lastDirectionPoint = CGPoint(x: 0.5, y: 0.85)
    private var lastAzimuth: Float = 0
    private var lastElevation: Float = 0
    private var lastConfidence: Float = 0

    private let echoGateThreshold: Float = 0.1
    private let echoGateAttack: Float = 0.75
    private let echoGateRelease: Float = 0.88
    private let echoWetMixBase: Float = 85
    private let echoWetMixRange: Float = 15
    private let echoFeedback: Float = 45
    private let echoBoostDb: Float = 18
    private let duckingStrength: Float = 0.35
    private let duckingResponse: Float = 0.18
    private let duckingLevelScale: Float = 0.6
    private let directionConfidenceThreshold: Float = 0.06
    private let sourceSmoothing: CGFloat = 0.15
    private var duckingLevel: Float = 1.0
    private var lastDebugUpdate: CFTimeInterval = 0
    private let debugUpdateInterval: CFTimeInterval = 0.2

    func startListening() {
        guard !isListening else { return }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.startSpatialCapture()
                } else {
                    print("Microphone permission denied")
                }
            }
        }
    }

    func stopListening() {
        isListening = false
        captureOutput?.setSampleBufferDelegate(nil, queue: nil)
        captureSession?.stopRunning()
        captureSession = nil
        captureInput = nil
        captureOutput = nil
        captureQueue.async { [weak self] in
            self?.stopPlaybackEngine()
        }
    }

    private func startSpatialCapture() {
        do {
            let session = AVAudioSession.sharedInstance()
            try configureAudioSession(session)

            let sessionCapture = AVCaptureSession()
            sessionCapture.automaticallyConfiguresApplicationAudioSession = false
            sessionCapture.beginConfiguration()

            guard let device = AVCaptureDevice.default(for: .audio) else {
                print("No audio capture device found")
                return
            }

            let input = try AVCaptureDeviceInput(device: device)
            input.multichannelAudioMode = .firstOrderAmbisonics
            guard sessionCapture.canAddInput(input) else {
                print("Unable to add audio capture input")
                return
            }
            sessionCapture.addInput(input)

            let output = AVCaptureAudioDataOutput()
            output.spatialAudioChannelLayoutTag = foaLayoutTag
            output.setSampleBufferDelegate(self, queue: captureQueue)
            guard sessionCapture.canAddOutput(output) else {
                print("Unable to add audio capture output")
                return
            }
            sessionCapture.addOutput(output)

            sessionCapture.commitConfiguration()
            sessionCapture.startRunning()

            captureSession = sessionCapture
            captureInput = input
            captureOutput = output
            isListening = true
        } catch {
            print("Aurora audio setup failed: \(error)")
        }
    }

    private func configureAudioSession(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try session.setMode(.measurement)
        if let inputs = session.availableInputs,
           let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtInMic)
        }
        try session.setActive(true)

        let usesReceiver = session.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
        if usesReceiver {
            // Ensure the echo is audible during capture.
            try session.overrideOutputAudioPort(.speaker)
        }
    }

    private func stopPlaybackEngine() {
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        gateMixer = nil
        delayNode = nil
        boostNode = nil
        playbackFormat = nil
        pendingBuffers = 0
    }

    private func ensurePlaybackEngine(sampleRate: Double) {
        if let playbackFormat = playbackFormat, abs(playbackFormat.sampleRate - sampleRate) < 0.5 {
            return
        }

        stopPlaybackEngine()

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let gateMixer = AVAudioMixerNode()
        gateMixer.outputVolume = 0

        let delay = AVAudioUnitDelay()
        delay.delayTime = 0.5
        delay.feedback = echoFeedback
        delay.lowPassCutoff = 12000
        delay.wetDryMix = 50

        let boost = AVAudioUnitEQ(numberOfBands: 1)
        boost.globalGain = echoBoostDb

        engine.attach(player)
        engine.attach(gateMixer)
        engine.attach(delay)
        engine.attach(boost)
        engine.connect(player, to: gateMixer, format: format)
        engine.connect(gateMixer, to: delay, format: format)
        engine.connect(delay, to: boost, format: format)
        engine.connect(boost, to: engine.mainMixerNode, format: format)

        engine.prepare()
        do {
            try engine.start()
            player.play()
            self.audioEngine = engine
            self.playerNode = player
            self.gateMixer = gateMixer
            self.delayNode = delay
            self.boostNode = boost
            self.playbackFormat = format
        } catch {
            print("Aurora playback engine failed: \(error)")
        }
    }

    private func processSpatialSamples(frames: Int,
                                       channelCount: Int,
                                       sampleRate: Double,
                                       sampleAt: (_ frame: Int, _ channel: Int) -> Float) {
        guard frames > 0, sampleRate > 0 else { return }
        ensurePlaybackEngine(sampleRate: sampleRate)
        guard let playbackFormat = playbackFormat else { return }

        let frameCount = AVAudioFrameCount(frames)
        guard let playbackBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount),
              let playbackData = playbackBuffer.floatChannelData?.pointee else {
            return
        }

        var sumW2: Float = 0
        var sumX2: Float = 0
        var sumY2: Float = 0
        var sumZ2: Float = 0
        var sumXW: Float = 0
        var sumYW: Float = 0
        var sumZW: Float = 0
        var zeroCrossings = 0
        var previous = sampleAt(0, 0)

        for i in 0..<frames {
            let w = sampleAt(i, 0)
            let y = sampleAt(i, 1)
            let z = sampleAt(i, 2)
            let x = sampleAt(i, 3)

            playbackData[i] = w

            sumW2 += w * w
            sumX2 += x * x
            sumY2 += y * y
            sumZ2 += z * z
            sumXW += x * w
            sumYW += y * w
            sumZW += z * w

            if i > 0 {
                if (w >= 0 && previous < 0) || (w < 0 && previous >= 0) {
                    zeroCrossings += 1
                }
            }
            previous = w
        }

        playbackBuffer.frameLength = frameCount
        enqueuePlayback(playbackBuffer)

        let rmsW = sqrt(sumW2 / Float(frames))
        let rmsX = sqrt(sumX2 / Float(frames))
        let rmsY = sqrt(sumY2 / Float(frames))
        let rmsZ = sqrt(sumZ2 / Float(frames))
        let normalizedLevel = min(1.0, rmsW * 8.0)
        let curvedLevel = pow(normalizedLevel, 0.7)

        let estimatedFreq = (Double(zeroCrossings) / 2.0) * sampleRate / Double(frames)
        let logFreq = log2(estimatedFreq / 100.0) / 3.3
        let normalizedPitch = Float(min(1.0, max(0.0, logFreq)))

        let direction = resolveDirection(sumXW: sumXW,
                                         sumYW: sumYW,
                                         sumZW: sumZW,
                                         energy: sumW2,
                                         level: normalizedLevel)

        let targetEcho: Float = curvedLevel > echoGateThreshold ? 1.0 : 0.0
        if targetEcho > echoMix {
            echoMix = echoMix * (1 - echoGateAttack) + targetEcho * echoGateAttack
        } else {
            echoMix = echoMix * echoGateRelease + targetEcho * (1 - echoGateRelease)
        }

        let duckingTarget = 1.0 - min(duckingStrength, curvedLevel * duckingLevelScale)
        duckingLevel = duckingLevel * (1 - duckingResponse) + duckingTarget * duckingResponse

        let duckedMix = echoMix * duckingLevel
        let duckedGain = echoBoostDb * duckingLevel

        gateMixer?.outputVolume = duckedMix
        delayNode?.wetDryMix = echoWetMixBase + echoWetMixRange * duckedMix
        boostNode?.globalGain = duckedGain

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.levelHistory.append(curvedLevel)
            if self.levelHistory.count > self.levelHistorySize {
                self.levelHistory.removeFirst()
            }
            self.smoothedLevel = self.levelHistory.reduce(0, +) / Float(self.levelHistory.count)
            self.dominantPitch = self.dominantPitch * 0.85 + normalizedPitch * 0.15

            let nextX = self.sourcePoint.x * (1 - self.sourceSmoothing) + direction.point.x * self.sourceSmoothing
            let nextY = self.sourcePoint.y * (1 - self.sourceSmoothing) + direction.point.y * self.sourceSmoothing
            self.sourcePoint = CGPoint(x: nextX, y: nextY)

            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastDebugUpdate > self.debugUpdateInterval {
                let azimuthDegrees = Double(direction.azimuth * 180 / .pi)
                let elevationDegrees = Double(direction.elevation * 180 / .pi)
                self.debugText = String(format: "ch:%d  sr:%.0f  lvl:%.2f  conf:%.2f  w:%.3f  x:%.3f  y:%.3f  z:%.3f\naz:%.0fdeg  el:%.0fdeg  x:%.2f  y:%.2f",
                                        channelCount,
                                        sampleRate,
                                        Double(normalizedLevel),
                                        Double(direction.confidence),
                                        Double(rmsW),
                                        Double(rmsX),
                                        Double(rmsY),
                                        Double(rmsZ),
                                        azimuthDegrees,
                                        elevationDegrees,
                                        Double(self.sourcePoint.x),
                                        Double(self.sourcePoint.y))
                self.lastDebugUpdate = now
            }
        }
    }

    private func resolveDirection(sumXW: Float,
                                  sumYW: Float,
                                  sumZW: Float,
                                  energy: Float,
                                  level: Float) -> (point: CGPoint, azimuth: Float, elevation: Float, confidence: Float) {
        guard energy > 0 else {
            return (lastDirectionPoint, lastAzimuth, lastElevation, lastConfidence)
        }

        let intensityMagnitude = sqrt(sumXW * sumXW + sumYW * sumYW + sumZW * sumZW)
        let confidence = min(1.0, intensityMagnitude / max(0.000001, energy))

        guard confidence > directionConfidenceThreshold, level > 0.04 else {
            lastConfidence = confidence
            return (lastDirectionPoint, lastAzimuth, lastElevation, confidence)
        }

        let azimuth = atan2(sumYW, sumXW)
        let horizontal = (azimuth / .pi + 1) * 0.5

        let elevation = atan2(sumZW, sqrt(sumXW * sumXW + sumYW * sumYW))
        let vertical = 0.5 - (elevation / (.pi / 2)) * 0.35

        let clamped = CGPoint(x: CGFloat(horizontal).clamped(to: 0.1...0.9),
                              y: CGFloat(vertical).clamped(to: 0.1...0.9))
        lastDirectionPoint = clamped
        lastAzimuth = azimuth
        lastElevation = elevation
        lastConfidence = confidence
        return (clamped, azimuth, elevation, confidence)
    }

    private func enqueuePlayback(_ buffer: AVAudioPCMBuffer) {
        guard let playerNode = playerNode else { return }
        if pendingBuffers >= maxPendingBuffers {
            return
        }

        pendingBuffers += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            self?.captureQueue.async { [weak self] in
                guard let self = self else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
            }
        }
    }
}

extension AuroraAudioProcessor: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return }

        let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
        let bufferCount = isNonInterleaved ? channelCount : 1
        let bufferListSize = AuroraAudioProcessor.audioBufferListSize(maximumBuffers: bufferCount)
        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: bufferListSize,
                                                          alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }

        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        audioBufferList.pointee.mNumberBuffers = UInt32(bufferCount)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return }

        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let sampleRate = asbd.pointee.mSampleRate
        guard sampleRate > 0 else { return }
        if channelCount < 4 {
            DispatchQueue.main.async { [weak self] in
                self?.debugText = String(format: "ch:%d  sr:%.0f  FOA unavailable",
                                         channelCount,
                                         sampleRate)
            }
            return
        }

        if isFloat {
            if isNonInterleaved {
                guard bufferList.count >= 4,
                      let w = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
                      let y = bufferList[1].mData?.assumingMemoryBound(to: Float.self),
                      let z = bufferList[2].mData?.assumingMemoryBound(to: Float.self),
                      let x = bufferList[3].mData?.assumingMemoryBound(to: Float.self) else {
                    return
                }

                processSpatialSamples(frames: frames, channelCount: channelCount, sampleRate: sampleRate) { index, channel in
                    switch channel {
                    case 0: return w[index]
                    case 1: return y[index]
                    case 2: return z[index]
                    default: return x[index]
                    }
                }
            } else {
                guard bufferList.count == 1,
                      let data = bufferList[0].mData?.assumingMemoryBound(to: Float.self) else {
                    return
                }

                processSpatialSamples(frames: frames, channelCount: channelCount, sampleRate: sampleRate) { index, channel in
                    data[index * channelCount + channel]
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 16 {
            if isNonInterleaved {
                guard bufferList.count >= 4,
                      let w = bufferList[0].mData?.assumingMemoryBound(to: Int16.self),
                      let y = bufferList[1].mData?.assumingMemoryBound(to: Int16.self),
                      let z = bufferList[2].mData?.assumingMemoryBound(to: Int16.self),
                      let x = bufferList[3].mData?.assumingMemoryBound(to: Int16.self) else {
                    return
                }

                let scale = 1.0 / Float(Int16.max)
                processSpatialSamples(frames: frames, channelCount: channelCount, sampleRate: sampleRate) { index, channel in
                    switch channel {
                    case 0: return Float(w[index]) * scale
                    case 1: return Float(y[index]) * scale
                    case 2: return Float(z[index]) * scale
                    default: return Float(x[index]) * scale
                    }
                }
            } else {
                guard bufferList.count == 1,
                      let data = bufferList[0].mData?.assumingMemoryBound(to: Int16.self) else {
                    return
                }

                let scale = 1.0 / Float(Int16.max)
                processSpatialSamples(frames: frames, channelCount: channelCount, sampleRate: sampleRate) { index, channel in
                    Float(data[index * channelCount + channel]) * scale
                }
            }
        }
    }

    private static func audioBufferListSize(maximumBuffers: Int) -> Int {
        MemoryLayout<AudioBufferList>.size + (maximumBuffers - 1) * MemoryLayout<AudioBuffer>.size
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
