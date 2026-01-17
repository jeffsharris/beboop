import SwiftUI
import AVFoundation
#if canImport(AVFAudio)
import AVFAudio
#endif
import CoreAudioTypes
import CoreMedia

enum SpatialPresetID: String, CaseIterable, Identifiable {
    case optionA
    case optionB
    case optionC
    case optionD

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionA:
            return "Preset A"
        case .optionB:
            return "Preset B"
        case .optionC:
            return "Preset C"
        case .optionD:
            return "Preset D"
        }
    }

    var menuTitle: String {
        switch self {
        case .optionA:
            return "Preset A — Default"
        case .optionB:
            return "Preset B — Stronger Gate"
        case .optionC:
            return "Preset C — Easier Retrigger"
        case .optionD:
            return "Preset D — Tap Resistant"
        }
    }

    var preset: SpatialPreset {
        switch self {
        case .optionA:
            return .optionA
        case .optionB:
            return .optionB
        case .optionC:
            return .optionC
        case .optionD:
            return .optionD
        }
    }
}

struct SpatialPreset {
    let masterOutput: Float
    let outputRatio: Float
    let wetOnly: Bool
    let inputGain: Float
    let inputCurve: Float
    let inputFloor: Float
    let gateThreshold: Float
    let gateAttack: Float
    let gateRelease: Float
    let triggerRise: Float
    let retriggerInterval: Double
    let holdDuration: Double
    let delayTime: Double
    let feedback: Float
    let wetMixBase: Float
    let wetMixRange: Float
    let lowPassCutoff: Float
    let boostDb: Float
    let duckingStrength: Float
    let duckingResponse: Float
    let duckingLevelScale: Float
    let duckingDelay: Double
    let gateHighPassCutoff: Float
    let hardDeafen: Double
    let bleedTauUp: Float
    let bleedTauDown: Float
    let bleedUpStepCap: Float
    let floorMul: Float
    let threshMul: Float
    let threshBias: Float
    let riseMinWhenEchoActive: Float

    static let optionA = SpatialPreset(
        masterOutput: 0.54,
        outputRatio: 0.95,
        wetOnly: true,
        inputGain: 12.0,
        inputCurve: 1.45,
        inputFloor: 0.14,
        gateThreshold: 0.52,
        gateAttack: 0.06,
        gateRelease: 0.28,
        triggerRise: 0.22,
        retriggerInterval: 0.65,
        holdDuration: 0.26,
        delayTime: 0.33,
        feedback: 52,
        wetMixBase: 6,
        wetMixRange: 62,
        lowPassCutoff: 5500,
        boostDb: 0.0,
        duckingStrength: 0.78,
        duckingResponse: 0.06,
        duckingLevelScale: 1.50,
        duckingDelay: 0.02,
        gateHighPassCutoff: 180,
        hardDeafen: 0.20,
        bleedTauUp: 0.70,
        bleedTauDown: 0.20,
        bleedUpStepCap: 0.03,
        floorMul: 1.10,
        threshMul: 1.65,
        threshBias: 0.05,
        riseMinWhenEchoActive: 0.22
    )

    static let optionB = SpatialPreset(
        masterOutput: 0.54,
        outputRatio: 0.95,
        wetOnly: true,
        inputGain: 12.0,
        inputCurve: 1.45,
        inputFloor: 0.14,
        gateThreshold: 0.52,
        gateAttack: 0.06,
        gateRelease: 0.28,
        triggerRise: 0.22,
        retriggerInterval: 0.65,
        holdDuration: 0.26,
        delayTime: 0.33,
        feedback: 48,
        wetMixBase: 6,
        wetMixRange: 55,
        lowPassCutoff: 5500,
        boostDb: 0.0,
        duckingStrength: 0.78,
        duckingResponse: 0.06,
        duckingLevelScale: 1.50,
        duckingDelay: 0.02,
        gateHighPassCutoff: 180,
        hardDeafen: 0.28,
        bleedTauUp: 0.70,
        bleedTauDown: 0.20,
        bleedUpStepCap: 0.03,
        floorMul: 1.10,
        threshMul: 1.85,
        threshBias: 0.05,
        riseMinWhenEchoActive: 0.22
    )

    static let optionC = SpatialPreset(
        masterOutput: 0.54,
        outputRatio: 0.95,
        wetOnly: true,
        inputGain: 12.0,
        inputCurve: 1.45,
        inputFloor: 0.14,
        gateThreshold: 0.52,
        gateAttack: 0.06,
        gateRelease: 0.28,
        triggerRise: 0.18,
        retriggerInterval: 0.65,
        holdDuration: 0.26,
        delayTime: 0.33,
        feedback: 52,
        wetMixBase: 6,
        wetMixRange: 62,
        lowPassCutoff: 5500,
        boostDb: 0.0,
        duckingStrength: 0.78,
        duckingResponse: 0.06,
        duckingLevelScale: 1.50,
        duckingDelay: 0.02,
        gateHighPassCutoff: 180,
        hardDeafen: 0.20,
        bleedTauUp: 0.70,
        bleedTauDown: 0.20,
        bleedUpStepCap: 0.02,
        floorMul: 1.10,
        threshMul: 1.50,
        threshBias: 0.03,
        riseMinWhenEchoActive: 0.18
    )

    static let optionD = SpatialPreset(
        masterOutput: 0.54,
        outputRatio: 0.95,
        wetOnly: true,
        inputGain: 12.0,
        inputCurve: 1.45,
        inputFloor: 0.18,
        gateThreshold: 0.60,
        gateAttack: 0.06,
        gateRelease: 0.28,
        triggerRise: 0.22,
        retriggerInterval: 0.65,
        holdDuration: 0.26,
        delayTime: 0.33,
        feedback: 52,
        wetMixBase: 6,
        wetMixRange: 62,
        lowPassCutoff: 5500,
        boostDb: 0.0,
        duckingStrength: 0.78,
        duckingResponse: 0.06,
        duckingLevelScale: 1.50,
        duckingDelay: 0.02,
        gateHighPassCutoff: 220,
        hardDeafen: 0.20,
        bleedTauUp: 0.70,
        bleedTauDown: 0.20,
        bleedUpStepCap: 0.03,
        floorMul: 1.10,
        threshMul: 1.65,
        threshBias: 0.05,
        riseMinWhenEchoActive: 0.22
    )
}

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
            let bottomInset = max(16, geometry.safeAreaInsets.bottom + 8)

            ZStack {
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

                presetMenu(bottomInset: bottomInset)
            }
        }
        .onAppear {
            audioProcessor.startListening(after: AudioHandoff.startDelay)
        }
        .onDisappear {
            audioProcessor.stopListening()
        }
        .onReceive(NotificationCenter.default.publisher(for: AudioHandoff.stopNotification)) { _ in
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

    private func presetMenu(bottomInset: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack {
                Menu {
                    ForEach(SpatialPresetID.allCases) { preset in
                        Button {
                            audioProcessor.selectPreset(preset)
                        } label: {
                            Text(preset.menuTitle)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(audioProcessor.selectedPreset.label)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
                }
                .padding(.leading, 18)
                .padding(.bottom, bottomInset)
                Spacer()
            }
        }
    }
}

// MARK: - Audio Processor

final class AuroraAudioProcessor: NSObject, ObservableObject {
    private static let settingsVersion = 3
    private static let settingsVersionKey = "voiceAurora.spatial.settingsVersion"
    private static let presetKey = "voiceAurora.spatial.preset"

    @Published var smoothedLevel: Float = 0
    @Published var dominantPitch: Float = 0.5
    @Published var sourcePoint: CGPoint = CGPoint(x: 0.5, y: 0.9)
    @Published private(set) var selectedPreset: SpatialPresetID = .optionA

    private var echoInputGain: Float = SpatialPreset.optionA.inputGain
    private var echoInputCurve: Float = SpatialPreset.optionA.inputCurve
    private var echoInputFloor: Float = SpatialPreset.optionA.inputFloor
    private var echoGateThreshold: Float = SpatialPreset.optionA.gateThreshold
    private var echoGateAttack: Float = SpatialPreset.optionA.gateAttack
    private var echoGateRelease: Float = SpatialPreset.optionA.gateRelease
    private var echoMasterOutput: Float = SpatialPreset.optionA.masterOutput
    private var echoOutputRatio: Float = SpatialPreset.optionA.outputRatio
    private var echoWetOnly: Bool = SpatialPreset.optionA.wetOnly
    private var echoWetMixBase: Float = SpatialPreset.optionA.wetMixBase
    private var echoWetMixRange: Float = SpatialPreset.optionA.wetMixRange
    private var echoDelayTime: Double = SpatialPreset.optionA.delayTime
    private var echoFeedback: Float = SpatialPreset.optionA.feedback
    private var echoLowPassCutoff: Float = SpatialPreset.optionA.lowPassCutoff
    private var echoBoostDb: Float = SpatialPreset.optionA.boostDb
    private var duckingStrength: Float = SpatialPreset.optionA.duckingStrength
    private var duckingResponse: Float = SpatialPreset.optionA.duckingResponse
    private var duckingLevelScale: Float = SpatialPreset.optionA.duckingLevelScale
    private var duckingDelay: Double = SpatialPreset.optionA.duckingDelay
    private var echoTriggerRise: Float = SpatialPreset.optionA.triggerRise
    private var echoRetriggerInterval: Double = SpatialPreset.optionA.retriggerInterval
    private var echoHoldDuration: Double = SpatialPreset.optionA.holdDuration
    private var gateHighPassCutoff: Float = SpatialPreset.optionA.gateHighPassCutoff
    private var hardDeafen: Double = SpatialPreset.optionA.hardDeafen
    private var bleedTauUp: Float = SpatialPreset.optionA.bleedTauUp
    private var bleedTauDown: Float = SpatialPreset.optionA.bleedTauDown
    private var bleedUpStepCap: Float = SpatialPreset.optionA.bleedUpStepCap
    private var floorMul: Float = SpatialPreset.optionA.floorMul
    private var threshMul: Float = SpatialPreset.optionA.threshMul
    private var threshBias: Float = SpatialPreset.optionA.threshBias
    private var riseMinWhenEchoActive: Float = SpatialPreset.optionA.riseMinWhenEchoActive

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
    private var limiterNode: AVAudioUnitDynamicsProcessor?
    private var playbackFormat: AVAudioFormat?
    private var isListening = false
    private var levelHistory: [Float] = []
    private let levelHistorySize = 8
    private var echoMix: Float = 0
    private var lastDirectionPoint = CGPoint(x: 0.5, y: 0.85)
    private var captureSamples: [Float] = []
    private var captureTargetSamples = 0
    private var isCapturing = false
    private var preRollBuffer: [Float] = []
    private var preRollIndex = 0
    private var preRollFilled = false
    private let preRollDuration: Double = 0.05
    private var echoActiveUntil: Double = 0
    private var hardDeafenUntil: Double = 0
    private var nextTriggerAllowedAt: Double = 0
    private var bleedEMA: Float = 0
    private var lastGateSignal: Float = 0
    private var lastGateUpdateTime: Double = 0
    private var lastSampleRate: Double = 0
    private var isInjecting = false
    private var lastTriggerLevel: Float = 0
    private var highPassLastInput: Float = 0
    private var highPassLastOutput: Float = 0

    private let directionConfidenceThreshold: Float = 0.06
    private let sourceSmoothing: CGFloat = 0.15
    private var duckingLevel: Float = 1.0
    private var lastEchoTriggerTime: Double = 0
    private var pendingStartWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        restoreSettings()
    }

    func selectPreset(_ preset: SpatialPresetID) {
        selectedPreset = preset
        applyPreset(preset.preset)
        persistPreset(preset)
    }

    private func restoreSettings() {
        let storedVersion = UserDefaults.standard.integer(forKey: Self.settingsVersionKey)
        if storedVersion != Self.settingsVersion {
            UserDefaults.standard.set(Self.settingsVersion, forKey: Self.settingsVersionKey)
            selectPreset(.optionA)
            return
        }
        if let stored = UserDefaults.standard.string(forKey: Self.presetKey),
           let preset = SpatialPresetID(rawValue: stored) {
            selectPreset(preset)
        } else {
            selectPreset(.optionA)
        }
    }

    private func persistPreset(_ preset: SpatialPresetID) {
        UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey)
    }

    private func applyPreset(_ preset: SpatialPreset) {
        echoInputGain = preset.inputGain
        echoInputCurve = preset.inputCurve
        echoInputFloor = preset.inputFloor
        echoGateThreshold = preset.gateThreshold
        echoGateAttack = preset.gateAttack
        echoGateRelease = preset.gateRelease
        echoMasterOutput = preset.masterOutput
        echoOutputRatio = preset.outputRatio
        echoWetOnly = preset.wetOnly
        echoWetMixBase = preset.wetMixBase
        echoWetMixRange = preset.wetMixRange
        echoDelayTime = preset.delayTime
        echoFeedback = preset.feedback
        echoLowPassCutoff = preset.lowPassCutoff
        echoBoostDb = preset.boostDb
        duckingStrength = preset.duckingStrength
        duckingResponse = preset.duckingResponse
        duckingLevelScale = preset.duckingLevelScale
        duckingDelay = preset.duckingDelay
        echoTriggerRise = preset.triggerRise
        echoRetriggerInterval = preset.retriggerInterval
        echoHoldDuration = preset.holdDuration
        gateHighPassCutoff = preset.gateHighPassCutoff
        hardDeafen = preset.hardDeafen
        bleedTauUp = preset.bleedTauUp
        bleedTauDown = preset.bleedTauDown
        bleedUpStepCap = preset.bleedUpStepCap
        floorMul = preset.floorMul
        threshMul = preset.threshMul
        threshBias = preset.threshBias
        riseMinWhenEchoActive = preset.riseMinWhenEchoActive

        resetGateState()
        updatePlaybackNodes()
    }

    private func resetGateState() {
        echoActiveUntil = 0
        hardDeafenUntil = 0
        nextTriggerAllowedAt = 0
        bleedEMA = 0
        lastGateSignal = 0
        lastGateUpdateTime = 0
        lastTriggerLevel = 0
        echoMix = 0
        duckingLevel = 1.0
        lastEchoTriggerTime = 0
    }

    private func updatePlaybackNodes() {
        delayNode?.delayTime = echoDelayTime.clamped(to: 0.0...2.0)
        delayNode?.feedback = echoFeedback.clamped(to: -100.0...100.0)
        delayNode?.lowPassCutoff = echoLowPassCutoff.clamped(to: 10.0...20_000.0)
        boostNode?.globalGain = echoBoostDb.clamped(to: -96.0...24.0)

        limiterNode?.threshold = -10
        limiterNode?.headRoom = 3
        limiterNode?.attackTime = 0.001
        limiterNode?.releaseTime = 0.06
        limiterNode?.masterGain = 0
    }

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
        resetGateState()

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
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        isListening = false
        let sessionToStop = captureSession
        let inputToStop = captureInput
        let outputToStop = captureOutput
        captureSession = nil
        captureInput = nil
        captureOutput = nil
        captureQueue.async { [weak self] in
            outputToStop?.setSampleBufferDelegate(nil, queue: nil)
            if let sessionToStop = sessionToStop {
                sessionToStop.beginConfiguration()
                if let outputToStop = outputToStop {
                    sessionToStop.removeOutput(outputToStop)
                }
                if let inputToStop = inputToStop {
                    sessionToStop.removeInput(inputToStop)
                }
                sessionToStop.commitConfiguration()
                sessionToStop.stopRunning()
            }
            self?.isCapturing = false
            self?.isInjecting = false
            self?.captureSamples.removeAll()
            self?.captureTargetSamples = 0
            self?.preRollBuffer.removeAll()
            self?.preRollIndex = 0
            self?.preRollFilled = false
            self?.lastSampleRate = 0
            self?.highPassLastInput = 0
            self?.highPassLastOutput = 0
            self?.lastTriggerLevel = 0
            self?.resetGateState()
            self?.stopPlaybackEngine()
            DispatchQueue.main.async { [weak self] in
                self?.deactivateAudioSession()
            }
        }
    }

    private func startSpatialCapture() {
        do {
            deactivateAudioSession()
            let sessionCapture = AVCaptureSession()
            sessionCapture.usesApplicationAudioSession = true
            sessionCapture.automaticallyConfiguresApplicationAudioSession = true
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

            captureSession = sessionCapture
            captureInput = input
            captureOutput = output
            isListening = true

            applyPlaybackOverrides()

            captureQueue.async {
                sessionCapture.startRunning()
            }
        } catch {
            print("Aurora audio setup failed: \(error)")
        }
    }

    private func applyPlaybackOverrides() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredInputNumberOfChannels(4)
        } catch {
            print("Failed to set preferred input channels: \(error)")
        }

        do {
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            print("Failed to override audio output: \(error)")
        }
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Aurora audio deactivation failed: \(error)")
        }
        do {
            try session.setPreferredInputNumberOfChannels(1)
        } catch {
            print("Aurora input channel reset failed: \(error)")
        }
    }

    private func stopPlaybackEngine() {
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        gateMixer = nil
        delayNode = nil
        boostNode = nil
        limiterNode = nil
        playbackFormat = nil
        isInjecting = false
    }

    @discardableResult
    private func ensurePlaybackEngine(sampleRate: Double) -> Bool {
        if let playbackFormat = playbackFormat,
           abs(playbackFormat.sampleRate - sampleRate) < 0.5,
           audioEngine?.isRunning == true {
            return true
        }

        stopPlaybackEngine()

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let gateMixer = AVAudioMixerNode()
        gateMixer.outputVolume = 0

        let delay = AVAudioUnitDelay()
        delay.wetDryMix = 50

        let boost = AVAudioUnitEQ(numberOfBands: 1)

        let limiter = AVAudioUnitDynamicsProcessor()

        engine.attach(player)
        engine.attach(gateMixer)
        engine.attach(delay)
        engine.attach(boost)
        engine.attach(limiter)
        engine.connect(player, to: gateMixer, format: format)
        engine.connect(gateMixer, to: delay, format: format)
        engine.connect(delay, to: boost, format: format)
        engine.connect(boost, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)

        engine.prepare()
        do {
            try engine.start()
            player.play()
            self.audioEngine = engine
            self.playerNode = player
            self.gateMixer = gateMixer
            self.delayNode = delay
            self.boostNode = boost
            self.limiterNode = limiter
            self.playbackFormat = format
            self.updatePlaybackNodes()
            return true
        } catch {
            print("Aurora playback engine failed: \(error)")
            return false
        }
    }

    private func processSpatialSamples(frames: Int,
                                       sampleRate: Double,
                                       sampleAt: (_ frame: Int, _ channel: Int) -> Float) {
        guard frames > 0, sampleRate > 0 else { return }
        _ = ensurePlaybackEngine(sampleRate: sampleRate)

        if abs(sampleRate - lastSampleRate) > 0.5 {
            configurePreRoll(sampleRate: sampleRate)
            lastSampleRate = sampleRate
            highPassLastInput = 0
            highPassLastOutput = 0
        }

        let frameDuration = Double(frames) / sampleRate
        let highPassAlpha = highPassCoefficient(sampleRate: sampleRate,
                                                 cutoff: Double(gateHighPassCutoff))

        var sumW2: Float = 0
        var sumGate2: Float = 0
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

            sumW2 += w * w
            sumXW += x * w
            sumYW += y * w
            sumZW += z * w

            let filtered = highPassAlpha * (highPassLastOutput + w - highPassLastInput)
            highPassLastInput = w
            highPassLastOutput = filtered
            sumGate2 += filtered * filtered

            appendPreRollSample(w)
            if isCapturing {
                captureSamples.append(w)
            }

            if i > 0 {
                if (w >= 0 && previous < 0) || (w < 0 && previous >= 0) {
                    zeroCrossings += 1
                }
            }
            previous = w
        }

        if isCapturing, captureSamples.count >= captureTargetSamples {
            finalizeCapture(sampleRate: sampleRate)
        }

        let rms = sqrt(sumGate2 / Float(frames))
        let inputGain = echoInputGain.clamped(to: 0.0...24.0)
        let inputCurve = echoInputCurve.clamped(to: 0.2...2.5)
        let normalizedLevel = min(1.0, rms * inputGain)
        let inputFloor = echoInputFloor.clamped(to: 0.0...1.5)
        let effectiveLevel: Float = normalizedLevel < inputFloor ? 0 : normalizedLevel
        let curvedLevel = pow(effectiveLevel, inputCurve)

        let estimatedFreq = (Double(zeroCrossings) / 2.0) * sampleRate / Double(frames)
        let logFreq = log2(estimatedFreq / 100.0) / 3.3
        let normalizedPitch = Float(min(1.0, max(0.0, logFreq)))

        let directionPoint = resolveDirectionPoint(sumXW: sumXW,
                                                   sumYW: sumYW,
                                                   sumZW: sumZW,
                                                   energy: sumW2,
                                                   level: effectiveLevel)

        let now = CFAbsoluteTimeGetCurrent()
        let gateThreshold = echoGateThreshold.clamped(to: 0.0...2.0)
        let triggerRise = max(0, echoTriggerRise)
        let holdDuration = max(0, echoHoldDuration)

        updateBleedEstimate(gateSignal: curvedLevel, now: now)

        var dynamicFloor = inputFloor
        var dynamicThreshold = gateThreshold
        var dynamicRise = triggerRise
        if now < echoActiveUntil {
            dynamicFloor = max(dynamicFloor, bleedEMA * floorMul)
            dynamicThreshold = max(dynamicThreshold, bleedEMA * threshMul + threshBias)
            dynamicRise = max(dynamicRise, riseMinWhenEchoActive)
        }

        let gateSignal: Float = normalizedLevel < dynamicFloor ? 0 : pow(normalizedLevel, inputCurve)
        let rise = gateSignal - lastGateSignal
        lastGateSignal = gateSignal

        let canTrigger = !isCapturing && now >= hardDeafenUntil && now >= nextTriggerAllowedAt
        if canTrigger && gateSignal > dynamicThreshold && rise > dynamicRise {
            lastTriggerLevel = gateSignal
            beginCapture(preRoll: snapshotPreRoll(),
                         holdDuration: holdDuration,
                         sampleRate: sampleRate)
        }

        let targetEcho: Float = now < echoActiveUntil ? 1.0 : 0.0
        let attackSeconds = max(0.01, Double(echoGateAttack))
        let releaseSeconds = max(0.01, Double(echoGateRelease))
        let attackCoeff = exp(-frameDuration / attackSeconds)
        let releaseCoeff = exp(-frameDuration / releaseSeconds)
        if targetEcho > echoMix {
            echoMix = echoMix * Float(attackCoeff) + targetEcho * Float(1 - attackCoeff)
        } else {
            echoMix = echoMix * Float(releaseCoeff) + targetEcho * Float(1 - releaseCoeff)
        }

        let duckingDelayValue = max(0, duckingDelay)
        let duckingStrengthValue = duckingStrength.clamped(to: 0.0...1.0)
        let duckingResponseValue = duckingResponse.clamped(to: 0.0...1.0)
        let duckingLevelScaleValue = max(0, duckingLevelScale)
        let bypassDucking = now - lastEchoTriggerTime < duckingDelayValue
        let duckingTarget = bypassDucking ? 1.0 : (1.0 - min(duckingStrengthValue, curvedLevel * duckingLevelScaleValue))
        duckingLevel = duckingLevel * (1 - duckingResponseValue) + duckingTarget * duckingResponseValue

        let outputLevel = echoMasterOutput.clamped(to: 0.0...1.0)
        let outputRatio = echoOutputRatio.clamped(to: 0.0...1.0)
        let inputScale = (1 - outputRatio) + outputRatio * lastTriggerLevel
        var outputGain = outputLevel * inputScale
        delayNode?.delayTime = echoDelayTime.clamped(to: 0.0...2.0)
        delayNode?.feedback = echoFeedback.clamped(to: -100.0...100.0)
        delayNode?.lowPassCutoff = echoLowPassCutoff.clamped(to: 10.0...20_000.0)
        let wetBase = echoWetMixBase.clamped(to: 0.0...100.0)
        let wetRange = echoWetMixRange.clamped(to: 0.0...100.0)
        let wetMixValue = wetBase + wetRange * echoMix
        if echoWetOnly {
            delayNode?.wetDryMix = 100
            let wetGain = min(100, max(0, wetMixValue)) / 100
            outputGain *= wetGain
        } else {
            let wetMix = min(100, max(0, wetMixValue))
            delayNode?.wetDryMix = wetMix
        }
        boostNode?.globalGain = echoBoostDb.clamped(to: -96.0...24.0)
        gateMixer?.outputVolume = isInjecting ? outputGain * duckingLevel : 0

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.levelHistory.append(curvedLevel)
            if self.levelHistory.count > self.levelHistorySize {
                self.levelHistory.removeFirst()
            }
            self.smoothedLevel = self.levelHistory.reduce(0, +) / Float(self.levelHistory.count)
            self.dominantPitch = self.dominantPitch * 0.85 + normalizedPitch * 0.15

            let nextX = self.sourcePoint.x * (1 - self.sourceSmoothing) + directionPoint.x * self.sourceSmoothing
            let nextY = self.sourcePoint.y * (1 - self.sourceSmoothing) + directionPoint.y * self.sourceSmoothing
            self.sourcePoint = CGPoint(x: nextX, y: nextY)
        }

    }

    private func configurePreRoll(sampleRate: Double) {
        let capacity = max(1, Int(sampleRate * preRollDuration))
        preRollBuffer = Array(repeating: 0, count: capacity)
        preRollIndex = 0
        preRollFilled = false
    }

    private func appendPreRollSample(_ sample: Float) {
        guard !preRollBuffer.isEmpty else { return }
        preRollBuffer[preRollIndex] = sample
        preRollIndex = (preRollIndex + 1) % preRollBuffer.count
        if preRollIndex == 0 {
            preRollFilled = true
        }
    }

    private func snapshotPreRoll() -> [Float] {
        guard !preRollBuffer.isEmpty else { return [] }
        if !preRollFilled {
            return Array(preRollBuffer.prefix(preRollIndex))
        }

        let head = preRollBuffer[preRollIndex..<preRollBuffer.count]
        let tail = preRollBuffer[0..<preRollIndex]
        return Array(head) + Array(tail)
    }

    private func beginCapture(preRoll: [Float], holdDuration: Double, sampleRate: Double) {
        isCapturing = true
        captureSamples = preRoll
        let holdSamples = max(0, Int(sampleRate * holdDuration))
        captureTargetSamples = captureSamples.count + holdSamples

        if captureTargetSamples == 0 || captureSamples.count >= captureTargetSamples {
            finalizeCapture(sampleRate: sampleRate)
        }
    }

    private func finalizeCapture(sampleRate: Double) {
        isCapturing = false
        let targetCount = max(0, captureTargetSamples)
        if targetCount > 0, captureSamples.count > targetCount {
            captureSamples = Array(captureSamples.prefix(targetCount))
        }
        guard !captureSamples.isEmpty else {
            captureSamples.removeAll()
            captureTargetSamples = 0
            return
        }

        scheduleSnippetPlayback(samples: captureSamples, sampleRate: sampleRate)
        captureSamples.removeAll()
        captureTargetSamples = 0
    }

    private func scheduleSnippetPlayback(samples: [Float], sampleRate: Double) {
        guard ensurePlaybackEngine(sampleRate: sampleRate),
              let playbackFormat = playbackFormat,
              let playerNode = playerNode else {
            return
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount),
              let data = buffer.floatChannelData?.pointee else {
            return
        }

        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { pointer in
            if let base = pointer.baseAddress {
                data.assign(from: base, count: samples.count)
            }
        }

        isInjecting = true
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            self?.captureQueue.async { [weak self] in
                self?.isInjecting = false
            }
        }
        playerNode.play()
        onEchoInjected(at: CFAbsoluteTimeGetCurrent())
    }

    private func onEchoInjected(at now: Double) {
        let delayTime = echoDelayTime.clamped(to: 0.0...2.0)
        let feedback = echoFeedback.clamped(to: -100.0...100.0)
        let tail = estimatedTailDuration(delayTime: delayTime, feedback: feedback)
        let retriggerInterval = max(0, echoRetriggerInterval)

        nextTriggerAllowedAt = now + retriggerInterval
        echoActiveUntil = max(echoActiveUntil, now + tail)
        hardDeafenUntil = max(hardDeafenUntil, now + delayTime + hardDeafen)
        lastEchoTriggerTime = now
    }

    private func estimatedTailDuration(delayTime: Double, feedback: Float) -> Double {
        let magnitude = abs(feedback) / 100.0
        guard magnitude > 0.001 else {
            return delayTime + 0.15
        }
        let fb = min(0.99, max(0.01, Double(magnitude)))
        let target = 0.01
        let repeats = ceil(log(target) / log(fb))
        if repeats.isInfinite || repeats.isNaN {
            return delayTime + 0.15
        }
        return delayTime * max(0, repeats) + 0.15
    }

    private func updateBleedEstimate(gateSignal: Float, now: Double) {
        if lastGateUpdateTime == 0 {
            lastGateUpdateTime = now
        }
        let dt = max(0.001, now - lastGateUpdateTime)
        lastGateUpdateTime = now

        if now < echoActiveUntil {
            let cappedTarget = min(gateSignal, bleedEMA + bleedUpStepCap)
            let tau = cappedTarget > bleedEMA ? bleedTauUp : bleedTauDown
            let safeTau = max(0.001, tau)
            let alpha = Float(1.0 - exp(-dt / Double(safeTau)))
            bleedEMA += alpha * (cappedTarget - bleedEMA)
        } else {
            bleedEMA *= 0.90
        }
    }

    private func highPassCoefficient(sampleRate: Double, cutoff: Double) -> Float {
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2.0 * Double.pi * cutoff)
        return Float(rc / (rc + dt))
    }

    private func resolveDirectionPoint(sumXW: Float,
                                       sumYW: Float,
                                       sumZW: Float,
                                       energy: Float,
                                       level: Float) -> CGPoint {
        guard energy > 0 else { return lastDirectionPoint }

        let intensityMagnitude = sqrt(sumXW * sumXW + sumYW * sumYW + sumZW * sumZW)
        let confidence = min(1.0, intensityMagnitude / max(0.000001, energy))

        guard confidence > directionConfidenceThreshold, level > 0.04 else {
            return lastDirectionPoint
        }

        let azimuth = atan2(sumYW, sumXW)
        let horizontal = 1 - (azimuth / .pi + 1) * 0.5

        let elevation = atan2(sumZW, sqrt(sumXW * sumXW + sumYW * sumYW))
        let vertical = 0.5 - (elevation / (.pi / 2)) * 0.35

        let clamped = CGPoint(x: CGFloat(horizontal).clamped(to: 0.1...0.9),
                              y: CGFloat(vertical).clamped(to: 0.1...0.9))
        lastDirectionPoint = clamped
        return clamped
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
        guard channelCount >= 4 else { return }

        if isFloat {
            if isNonInterleaved {
                guard bufferList.count >= 4,
                      let w = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
                      let y = bufferList[1].mData?.assumingMemoryBound(to: Float.self),
                      let z = bufferList[2].mData?.assumingMemoryBound(to: Float.self),
                      let x = bufferList[3].mData?.assumingMemoryBound(to: Float.self) else {
                    return
                }

                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
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

                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
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
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
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
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    Float(data[index * channelCount + channel]) * scale
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 32 {
            if isNonInterleaved {
                guard bufferList.count >= 4,
                      let w = bufferList[0].mData?.assumingMemoryBound(to: Int32.self),
                      let y = bufferList[1].mData?.assumingMemoryBound(to: Int32.self),
                      let z = bufferList[2].mData?.assumingMemoryBound(to: Int32.self),
                      let x = bufferList[3].mData?.assumingMemoryBound(to: Int32.self) else {
                    return
                }

                let scale = 1.0 / Float(Int32.max)
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    switch channel {
                    case 0: return Float(w[index]) * scale
                    case 1: return Float(y[index]) * scale
                    case 2: return Float(z[index]) * scale
                    default: return Float(x[index]) * scale
                    }
                }
            } else {
                guard bufferList.count == 1,
                      let data = bufferList[0].mData?.assumingMemoryBound(to: Int32.self) else {
                    return
                }

                let scale = 1.0 / Float(Int32.max)
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
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

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

#Preview {
    VoiceAuroraView()
}
