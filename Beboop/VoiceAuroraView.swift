import SwiftUI
import AVFoundation
import Foundation
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

    @EnvironmentObject private var audioCoordinator: AudioCoordinator
    @StateObject private var audioProcessor = AuroraAudioProcessor()
    @State private var waves: [Wave] = []
    @State private var lastUpdateTime: Date = Date()
    @State private var lastWaveTime: Date = .distantPast
    @AppStorage("echoLab.presented") private var isEchoLabPresented = false

    private let waveCooldown: TimeInterval = 0.16
    private let waveMinLevel: Double = 0.08
    private let waveMaxAge: Double = 2.9
    private let waveBaseSpeed: Double = 170

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
#if DEBUG
        .sheet(isPresented: $isEchoLabPresented) {
            EchoLabView(audioProcessor: audioProcessor,
                        isPresented: $isEchoLabPresented)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
#endif
        .onAppear {
            audioCoordinator.register(mode: .voiceAurora,
                                      start: {
                                          audioProcessor.startListening()
                                      },
                                      stop: { completion in
                                          audioProcessor.stopListening(completion: completion)
                                      })
        }
        .onDisappear {
            audioCoordinator.unregister(mode: .voiceAurora)
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
    private enum EchoDefaults {
        static let inputGain: Float = 12.0
        static let inputCurve: Float = 1.4
        static let inputFloor: Float = 0.14
        static let gateThreshold: Float = 0.48
        static let gateAttack: Float = 0.05
        static let gateRelease: Float = 0.25
        static let masterOutput: Float = 0.55
        static let outputRatio: Float = 0.65
        static let wetOnly: Bool = true
        static let wetMixBase: Float = 6
        static let wetMixRange: Float = 62
        static let delayTime: Double = 0.33
        static let feedback: Float = 50
        static let lowPassCutoff: Float = 5500
        static let boostDb: Float = 0
        static let duckingStrength: Float = 0.75
        static let duckingResponse: Float = 0.06
        static let duckingLevelScale: Float = 1.5
        static let duckingDelay: Double = 0.02
        static let triggerRise: Float = 0.2
        static let retriggerInterval: Double = 0.55
        static let holdDuration: Double = 0.24
        static let snrMarginDB: Float = 9.0
        static let hardDeafen: Double = 0.22
        static let bleedTauUp: Double = 0.35
        static let bleedTauDown: Double = 0.75
        static let bleedStepCap: Float = 6.0
        static let threshMul: Float = 1.6
        static let threshBias: Float = 0.05
        static let riseMinWhenEchoActive: Float = 0.22
    }

    private enum EchoLabDefaults {
        static let phraseX: Float = 0.45
        static let shieldY: Float = 0.62
        static let spaceX: Float = 0.55
        static let decayY: Float = 0.55
        static let level: Float = 0.55
        static let softLockoutEnabled: Bool = true
        static let outputMaskEnabled: Bool = true
        static let freezeEventGainEnabled: Bool = true
        static let limiterEnabled: Bool = false
    }

    private static let settingsVersion = 4
    private static let settingsVersionKey = "voiceAurora.echo.settingsVersion"
    private static let labSchemaVersion = 1
    private static let labSchemaVersionKey = "voiceAurora.echo.labSchemaVersion"

    private enum EchoSettingKey: String {
        case inputGain = "voiceAurora.echo.inputGain"
        case inputCurve = "voiceAurora.echo.inputCurve"
        case inputFloor = "voiceAurora.echo.inputFloor"
        case gateThreshold = "voiceAurora.echo.gateThreshold"
        case gateAttack = "voiceAurora.echo.gateAttack"
        case gateRelease = "voiceAurora.echo.gateRelease"
        case masterOutput = "voiceAurora.echo.masterOutput"
        case outputRatio = "voiceAurora.echo.outputRatio"
        case wetOnly = "voiceAurora.echo.wetOnly"
        case wetMixBase = "voiceAurora.echo.wetMixBase"
        case wetMixRange = "voiceAurora.echo.wetMixRange"
        case delayTime = "voiceAurora.echo.delayTime"
        case feedback = "voiceAurora.echo.feedback"
        case lowPassCutoff = "voiceAurora.echo.lowPassCutoff"
        case boostDb = "voiceAurora.echo.boostDb"
        case duckingStrength = "voiceAurora.echo.duckingStrength"
        case duckingResponse = "voiceAurora.echo.duckingResponse"
        case duckingLevelScale = "voiceAurora.echo.duckingLevelScale"
        case duckingDelay = "voiceAurora.echo.duckingDelay"
        case triggerRise = "voiceAurora.echo.triggerRise"
        case retriggerInterval = "voiceAurora.echo.retriggerInterval"
        case holdDuration = "voiceAurora.echo.holdDuration"
        case snrMarginDB = "voiceAurora.echo.snrMarginDB"
        case hardDeafen = "voiceAurora.echo.hardDeafen"
        case bleedTauUp = "voiceAurora.echo.bleedTauUp"
        case bleedTauDown = "voiceAurora.echo.bleedTauDown"
        case bleedStepCap = "voiceAurora.echo.bleedStepCap"
        case threshMul = "voiceAurora.echo.threshMul"
        case threshBias = "voiceAurora.echo.threshBias"
        case riseMinWhenEchoActive = "voiceAurora.echo.riseMinWhenEchoActive"
    }

    private enum EchoLabKey: String {
        case phraseX = "voiceAurora.echo.lab.phraseX"
        case shieldY = "voiceAurora.echo.lab.shieldY"
        case spaceX = "voiceAurora.echo.lab.spaceX"
        case decayY = "voiceAurora.echo.lab.decayY"
        case level = "voiceAurora.echo.lab.level"
        case activeSlot = "voiceAurora.echo.lab.activeSlot"
        case slotAPhraseX = "voiceAurora.echo.lab.slotA.phraseX"
        case slotAShieldY = "voiceAurora.echo.lab.slotA.shieldY"
        case slotASpaceX = "voiceAurora.echo.lab.slotA.spaceX"
        case slotADecayY = "voiceAurora.echo.lab.slotA.decayY"
        case slotALevel = "voiceAurora.echo.lab.slotA.level"
        case slotBPhraseX = "voiceAurora.echo.lab.slotB.phraseX"
        case slotBShieldY = "voiceAurora.echo.lab.slotB.shieldY"
        case slotBSpaceX = "voiceAurora.echo.lab.slotB.spaceX"
        case slotBDecayY = "voiceAurora.echo.lab.slotB.decayY"
        case slotBLevel = "voiceAurora.echo.lab.slotB.level"
        case softLockoutEnabled = "voiceAurora.echo.lab.softLockoutEnabled"
        case outputMaskEnabled = "voiceAurora.echo.lab.outputMaskEnabled"
        case freezeEventGainEnabled = "voiceAurora.echo.lab.freezeEventGainEnabled"
        case limiterEnabled = "voiceAurora.echo.lab.limiterEnabled"
    }

    @Published var smoothedLevel: Float = 0
    @Published var dominantPitch: Float = 0.5
    @Published var sourcePoint: CGPoint = CGPoint(x: 0.5, y: 0.9)
    @Published var echoInputGain: Float = EchoDefaults.inputGain {
        didSet { persistSetting(.inputGain, value: echoInputGain) }
    }
    @Published var echoInputCurve: Float = EchoDefaults.inputCurve {
        didSet { persistSetting(.inputCurve, value: echoInputCurve) }
    }
    @Published var echoInputFloor: Float = EchoDefaults.inputFloor {
        didSet { persistSetting(.inputFloor, value: echoInputFloor) }
    }
    @Published var echoGateThreshold: Float = EchoDefaults.gateThreshold {
        didSet { persistSetting(.gateThreshold, value: echoGateThreshold) }
    }
    @Published var echoGateAttack: Float = EchoDefaults.gateAttack {
        didSet { persistSetting(.gateAttack, value: echoGateAttack) }
    }
    @Published var echoGateRelease: Float = EchoDefaults.gateRelease {
        didSet { persistSetting(.gateRelease, value: echoGateRelease) }
    }
    @Published var echoMasterOutput: Float = EchoDefaults.masterOutput {
        didSet { persistSetting(.masterOutput, value: echoMasterOutput) }
    }
    @Published var echoOutputRatio: Float = EchoDefaults.outputRatio {
        didSet { persistSetting(.outputRatio, value: echoOutputRatio) }
    }
    @Published var echoWetOnly: Bool = EchoDefaults.wetOnly {
        didSet { persistSetting(.wetOnly, value: echoWetOnly) }
    }
    @Published var echoWetMixBase: Float = EchoDefaults.wetMixBase {
        didSet { persistSetting(.wetMixBase, value: echoWetMixBase) }
    }
    @Published var echoWetMixRange: Float = EchoDefaults.wetMixRange {
        didSet { persistSetting(.wetMixRange, value: echoWetMixRange) }
    }
    @Published var echoDelayTime: Double = EchoDefaults.delayTime {
        didSet { persistSetting(.delayTime, value: echoDelayTime) }
    }
    @Published var echoFeedback: Float = EchoDefaults.feedback {
        didSet { persistSetting(.feedback, value: echoFeedback) }
    }
    @Published var echoLowPassCutoff: Float = EchoDefaults.lowPassCutoff {
        didSet { persistSetting(.lowPassCutoff, value: echoLowPassCutoff) }
    }
    @Published var echoBoostDb: Float = EchoDefaults.boostDb {
        didSet { persistSetting(.boostDb, value: echoBoostDb) }
    }
    @Published var duckingStrength: Float = EchoDefaults.duckingStrength {
        didSet { persistSetting(.duckingStrength, value: duckingStrength) }
    }
    @Published var duckingResponse: Float = EchoDefaults.duckingResponse {
        didSet { persistSetting(.duckingResponse, value: duckingResponse) }
    }
    @Published var duckingLevelScale: Float = EchoDefaults.duckingLevelScale {
        didSet { persistSetting(.duckingLevelScale, value: duckingLevelScale) }
    }
    @Published var duckingDelay: Double = EchoDefaults.duckingDelay {
        didSet { persistSetting(.duckingDelay, value: duckingDelay) }
    }
    @Published var echoTriggerRise: Float = EchoDefaults.triggerRise {
        didSet { persistSetting(.triggerRise, value: echoTriggerRise) }
    }
    @Published var echoRetriggerInterval: Double = EchoDefaults.retriggerInterval {
        didSet { persistSetting(.retriggerInterval, value: echoRetriggerInterval) }
    }
    @Published var echoHoldDuration: Double = EchoDefaults.holdDuration {
        didSet { persistSetting(.holdDuration, value: echoHoldDuration) }
    }
    @Published private(set) var labPhraseX: Float = EchoLabDefaults.phraseX
    @Published private(set) var labShieldY: Float = EchoLabDefaults.shieldY
    @Published private(set) var labSpaceX: Float = EchoLabDefaults.spaceX
    @Published private(set) var labDecayY: Float = EchoLabDefaults.decayY
    @Published private(set) var labEchoLevel: Float = EchoLabDefaults.level
    @Published private(set) var labActiveSlot: EchoLabSlot = .a
    @Published var labSoftLockoutEnabled: Bool = EchoLabDefaults.softLockoutEnabled {
        didSet { persistLabSetting(.softLockoutEnabled, value: labSoftLockoutEnabled) }
    }
    @Published var labOutputMaskEnabled: Bool = EchoLabDefaults.outputMaskEnabled {
        didSet { persistLabSetting(.outputMaskEnabled, value: labOutputMaskEnabled) }
    }
    @Published var labFreezeEventGainEnabled: Bool = EchoLabDefaults.freezeEventGainEnabled {
        didSet { persistLabSetting(.freezeEventGainEnabled, value: labFreezeEventGainEnabled) }
    }
    @Published var labLimiterEnabled: Bool = EchoLabDefaults.limiterEnabled {
        didSet { persistLabSetting(.limiterEnabled, value: labLimiterEnabled) }
    }
    @Published var echoSnrMarginDB: Float = EchoDefaults.snrMarginDB {
        didSet { persistSetting(.snrMarginDB, value: echoSnrMarginDB) }
    }
    @Published var echoHardDeafen: Double = EchoDefaults.hardDeafen {
        didSet { persistSetting(.hardDeafen, value: echoHardDeafen) }
    }
    @Published var bleedTauUp: Double = EchoDefaults.bleedTauUp {
        didSet { persistSetting(.bleedTauUp, value: bleedTauUp) }
    }
    @Published var bleedTauDown: Double = EchoDefaults.bleedTauDown {
        didSet { persistSetting(.bleedTauDown, value: bleedTauDown) }
    }
    @Published var bleedStepCap: Float = EchoDefaults.bleedStepCap {
        didSet { persistSetting(.bleedStepCap, value: bleedStepCap) }
    }
    @Published var echoThreshMul: Float = EchoDefaults.threshMul {
        didSet { persistSetting(.threshMul, value: echoThreshMul) }
    }
    @Published var echoThreshBias: Float = EchoDefaults.threshBias {
        didSet { persistSetting(.threshBias, value: echoThreshBias) }
    }
    @Published var riseMinWhenEchoActive: Float = EchoDefaults.riseMinWhenEchoActive {
        didSet { persistSetting(.riseMinWhenEchoActive, value: riseMinWhenEchoActive) }
    }
    @Published var echoMaxCaptureDuration: Double = 0.6
    @Published var echoEndHangover: Double = 0.2
    @Published var echoPreRollDuration: Double = 0.05
    @Published var debugSnapshot = EchoLabDebugSnapshot()

    private var isRestoringSettings = false
    private var isRestoringLabSettings = false
    private var isApplyingMacroMapping = false
    private var labSlotA = EchoLabMacroValues.defaultSlot
    private var labSlotB = EchoLabMacroValues.defaultSlot

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
    private var smoothedDelayTime: Double = 0
    private var smoothedFeedback: Float = 0
    private var smoothedLowPass: Float = 0
    private var smoothedOutputGain: Float = 0
    private var smoothedWetMix: Float = 0
    private var playbackFormat: AVAudioFormat?
    private var isListening = false
    private var levelHistory: [Float] = []
    private let levelHistorySize = 8
    private var echoMix: Float = 0
    private var eventActiveUntil: Double = 0
    private var eventWetGain: Float = 0
    private var eventWetMix: Float = 0
    private var eventMasterOutput: Float = 0
    private var eventOutputRatio: Float = 0
    private var eventMixAtTrigger: Float = 0
    private var pendingEventMix: Float = 0
    private var lastDirectionPoint = CGPoint(x: 0.5, y: 0.85)
    private var captureSamples: [Float] = []
    private var captureTargetSamples = 0
    private var captureMinSamples = 0
    private var captureHangoverSamples = 0
    private var captureSilenceSamples = 0
    private var capturePreRollCount = 0
    private var captureStartTime: Double = 0
    private var isCapturing = false
    private var preRollBuffer: [Float] = []
    private var preRollIndex = 0
    private var preRollFilled = false
    private let minCaptureDuration: Double = 0.18
    private var lastConfiguredPreRollDuration: Double = 0
    private var cooldownUntil: Double = 0
    private var deafenUntil: Double = 0
    private var lastSampleRate: Double = 0
    private var isInjecting = false
    private var lastTriggerLevel: Float = 0
    private var highPassLastInput: Float = 0
    private var highPassLastOutput: Float = 0
    private var gateHighPassCutoff: Float = 180

    private let directionConfidenceThreshold: Float = 0.06
    private let sourceSmoothing: CGFloat = 0.15
    private var duckingLevel: Float = 1.0
    private var lastCurvedLevel: Float = 0
    private var lastEchoTriggerTime: Double = 0
    private var pendingStartWorkItem: DispatchWorkItem?
    private var lastMicDB: Float = -160
    private var bleedDeltaDB: Float = -18
    private let bleedRiseGuardDB: Float = 1.5
    private let outDBFloor: Float = -160
    private let outDBMeter = AtomicFloat(initialValue: -160)
    private var isWetTapInstalled = false
    private var wetMeterNode: AVAudioNode?
    private var lastDebugPublishTime: Double = 0
    private var lastEventReason: String = "Idle"
    private var lastBlockReason: String = "Idle"
    private var currentDynamicThreshold: Float = 0
    private var currentEndThreshold: Float = 0
    private var calibrationMode: EchoLabCalibrationMode = .none
    private var calibrationSamples: [Float] = []
    private var calibrationStartTime: Double = 0
    private var calibrationEndTime: Double = 0

    override init() {
        super.init()
        restoreSettings()
        restoreLabSettings()
    }

    func resetEchoDefaults() {
        echoInputGain = EchoDefaults.inputGain
        echoInputCurve = EchoDefaults.inputCurve
        echoInputFloor = EchoDefaults.inputFloor
        echoGateThreshold = EchoDefaults.gateThreshold
        echoGateAttack = EchoDefaults.gateAttack
        echoGateRelease = EchoDefaults.gateRelease
        echoMasterOutput = EchoDefaults.masterOutput
        echoOutputRatio = EchoDefaults.outputRatio
        echoWetOnly = EchoDefaults.wetOnly
        echoWetMixBase = EchoDefaults.wetMixBase
        echoWetMixRange = EchoDefaults.wetMixRange
        echoDelayTime = EchoDefaults.delayTime
        echoFeedback = EchoDefaults.feedback
        echoLowPassCutoff = EchoDefaults.lowPassCutoff
        echoBoostDb = EchoDefaults.boostDb
        duckingStrength = EchoDefaults.duckingStrength
        duckingResponse = EchoDefaults.duckingResponse
        duckingLevelScale = EchoDefaults.duckingLevelScale
        duckingDelay = EchoDefaults.duckingDelay
        echoTriggerRise = EchoDefaults.triggerRise
        echoRetriggerInterval = EchoDefaults.retriggerInterval
        echoHoldDuration = EchoDefaults.holdDuration
        echoSnrMarginDB = EchoDefaults.snrMarginDB
        echoHardDeafen = EchoDefaults.hardDeafen
        bleedTauUp = EchoDefaults.bleedTauUp
        bleedTauDown = EchoDefaults.bleedTauDown
        bleedStepCap = EchoDefaults.bleedStepCap
        echoThreshMul = EchoDefaults.threshMul
        echoThreshBias = EchoDefaults.threshBias
        riseMinWhenEchoActive = EchoDefaults.riseMinWhenEchoActive
        resetLabDefaults()
    }

    private func resetEventState() {
        cooldownUntil = 0
        deafenUntil = 0
        eventActiveUntil = 0
        eventWetGain = 0
        eventWetMix = 0
        eventMasterOutput = 0
        eventOutputRatio = 0
        eventMixAtTrigger = 0
        pendingEventMix = 0
        echoMix = 0
        lastTriggerLevel = 0
        lastCurvedLevel = 0
        lastEchoTriggerTime = 0
        lastMicDB = outDBFloor
        bleedDeltaDB = -18
        outDBMeter.set(outDBFloor)
        lastEventReason = "Idle"
        lastBlockReason = "Idle"
        captureSilenceSamples = 0
        captureMinSamples = 0
        captureHangoverSamples = 0
        capturePreRollCount = 0
        captureStartTime = 0
        currentDynamicThreshold = 0
        currentEndThreshold = 0
    }

    private func restoreSettings() {
        isRestoringSettings = true
        let storedVersion = UserDefaults.standard.integer(forKey: Self.settingsVersionKey)
        if storedVersion != Self.settingsVersion {
            isRestoringSettings = false
            resetEchoDefaults()
            UserDefaults.standard.set(Self.settingsVersion, forKey: Self.settingsVersionKey)
            return
        }
        echoInputGain = loadFloat(.inputGain, fallback: EchoDefaults.inputGain)
        echoInputCurve = loadFloat(.inputCurve, fallback: EchoDefaults.inputCurve)
        echoInputFloor = loadFloat(.inputFloor, fallback: EchoDefaults.inputFloor)
        echoGateThreshold = loadFloat(.gateThreshold, fallback: EchoDefaults.gateThreshold)
        echoGateAttack = loadFloat(.gateAttack, fallback: EchoDefaults.gateAttack)
        echoGateRelease = loadFloat(.gateRelease, fallback: EchoDefaults.gateRelease)
        echoMasterOutput = loadFloat(.masterOutput, fallback: EchoDefaults.masterOutput)
        echoOutputRatio = loadFloat(.outputRatio, fallback: EchoDefaults.outputRatio)
        echoWetOnly = loadBool(.wetOnly, fallback: EchoDefaults.wetOnly)
        echoWetMixBase = loadFloat(.wetMixBase, fallback: EchoDefaults.wetMixBase)
        echoWetMixRange = loadFloat(.wetMixRange, fallback: EchoDefaults.wetMixRange)
        echoDelayTime = loadDouble(.delayTime, fallback: EchoDefaults.delayTime)
        echoFeedback = loadFloat(.feedback, fallback: EchoDefaults.feedback)
        echoLowPassCutoff = loadFloat(.lowPassCutoff, fallback: EchoDefaults.lowPassCutoff)
        echoBoostDb = loadFloat(.boostDb, fallback: EchoDefaults.boostDb)
        duckingStrength = loadFloat(.duckingStrength, fallback: EchoDefaults.duckingStrength)
        duckingResponse = loadFloat(.duckingResponse, fallback: EchoDefaults.duckingResponse)
        duckingLevelScale = loadFloat(.duckingLevelScale, fallback: EchoDefaults.duckingLevelScale)
        duckingDelay = loadDouble(.duckingDelay, fallback: EchoDefaults.duckingDelay)
        echoTriggerRise = loadFloat(.triggerRise, fallback: EchoDefaults.triggerRise)
        echoRetriggerInterval = loadDouble(.retriggerInterval, fallback: EchoDefaults.retriggerInterval)
        echoHoldDuration = loadDouble(.holdDuration, fallback: EchoDefaults.holdDuration)
        echoSnrMarginDB = loadFloat(.snrMarginDB, fallback: EchoDefaults.snrMarginDB)
        echoHardDeafen = loadDouble(.hardDeafen, fallback: EchoDefaults.hardDeafen)
        bleedTauUp = loadDouble(.bleedTauUp, fallback: EchoDefaults.bleedTauUp)
        bleedTauDown = loadDouble(.bleedTauDown, fallback: EchoDefaults.bleedTauDown)
        bleedStepCap = loadFloat(.bleedStepCap, fallback: EchoDefaults.bleedStepCap)
        echoThreshMul = loadFloat(.threshMul, fallback: EchoDefaults.threshMul)
        echoThreshBias = loadFloat(.threshBias, fallback: EchoDefaults.threshBias)
        riseMinWhenEchoActive = loadFloat(.riseMinWhenEchoActive, fallback: EchoDefaults.riseMinWhenEchoActive)
        isRestoringSettings = false
    }

    private func resetLabDefaults() {
        labSoftLockoutEnabled = EchoLabDefaults.softLockoutEnabled
        labOutputMaskEnabled = EchoLabDefaults.outputMaskEnabled
        labFreezeEventGainEnabled = EchoLabDefaults.freezeEventGainEnabled
        labLimiterEnabled = EchoLabDefaults.limiterEnabled
        labActiveSlot = .a
        UserDefaults.standard.set(labActiveSlot.rawValue, forKey: EchoLabKey.activeSlot.rawValue)
        let defaults = EchoLabMacroValues.defaultSlot
        labSlotA = defaults
        labSlotB = defaults
        updateMacroValues(phraseX: defaults.phraseX,
                          shieldY: defaults.shieldY,
                          spaceX: defaults.spaceX,
                          decayY: defaults.decayY,
                          level: defaults.level,
                          persist: true)
        persistLabSlot(.a, values: labSlotA)
        persistLabSlot(.b, values: labSlotB)
        UserDefaults.standard.set(Self.labSchemaVersion, forKey: Self.labSchemaVersionKey)
    }

    private func restoreLabSettings() {
        isRestoringLabSettings = true
        let storedVersion = UserDefaults.standard.integer(forKey: Self.labSchemaVersionKey)
        if storedVersion != Self.labSchemaVersion {
            isRestoringLabSettings = false
            resetLabDefaults()
            return
        }

        labSoftLockoutEnabled = loadLabBool(.softLockoutEnabled, fallback: EchoLabDefaults.softLockoutEnabled)
        labOutputMaskEnabled = loadLabBool(.outputMaskEnabled, fallback: EchoLabDefaults.outputMaskEnabled)
        labFreezeEventGainEnabled = loadLabBool(.freezeEventGainEnabled, fallback: EchoLabDefaults.freezeEventGainEnabled)
        labLimiterEnabled = loadLabBool(.limiterEnabled, fallback: EchoLabDefaults.limiterEnabled)
        labSlotA = loadLabSlot(.a)
        labSlotB = loadLabSlot(.b)
        let slotRaw = UserDefaults.standard.integer(forKey: EchoLabKey.activeSlot.rawValue)
        labActiveSlot = EchoLabSlot(rawValue: slotRaw) ?? .a

        let phraseX = loadLabFloat(.phraseX, fallback: EchoLabDefaults.phraseX)
        let shieldY = loadLabFloat(.shieldY, fallback: EchoLabDefaults.shieldY)
        let spaceX = loadLabFloat(.spaceX, fallback: EchoLabDefaults.spaceX)
        let decayY = loadLabFloat(.decayY, fallback: EchoLabDefaults.decayY)
        let level = loadLabFloat(.level, fallback: EchoLabDefaults.level)
        isRestoringLabSettings = false
        updateMacroValues(phraseX: phraseX,
                          shieldY: shieldY,
                          spaceX: spaceX,
                          decayY: decayY,
                          level: level,
                          persist: false)
    }

    func resetLabToDefaults() {
        resetLabDefaults()
    }

    func activateLabSlot(_ slot: EchoLabSlot) {
        labActiveSlot = slot
        UserDefaults.standard.set(slot.rawValue, forKey: EchoLabKey.activeSlot.rawValue)
        let values = slot == .a ? labSlotA : labSlotB
        updateMacroValues(phraseX: values.phraseX,
                          shieldY: values.shieldY,
                          spaceX: values.spaceX,
                          decayY: values.decayY,
                          level: values.level,
                          persist: true)
    }

    func saveLabSlot(_ slot: EchoLabSlot) {
        let values = EchoLabMacroValues(phraseX: labPhraseX,
                                        shieldY: labShieldY,
                                        spaceX: labSpaceX,
                                        decayY: labDecayY,
                                        level: labEchoLevel)
        if slot == .a {
            labSlotA = values
        } else {
            labSlotB = values
        }
        persistLabSlot(slot, values: values)
    }

    func updateLabPhraseX(_ value: Float) {
        updateMacroValues(phraseX: value,
                          shieldY: labShieldY,
                          spaceX: labSpaceX,
                          decayY: labDecayY,
                          level: labEchoLevel,
                          persist: true)
    }

    func updateLabShieldY(_ value: Float) {
        updateMacroValues(phraseX: labPhraseX,
                          shieldY: value,
                          spaceX: labSpaceX,
                          decayY: labDecayY,
                          level: labEchoLevel,
                          persist: true)
    }

    func updateLabSpaceX(_ value: Float) {
        updateMacroValues(phraseX: labPhraseX,
                          shieldY: labShieldY,
                          spaceX: value,
                          decayY: labDecayY,
                          level: labEchoLevel,
                          persist: true)
    }

    func updateLabDecayY(_ value: Float) {
        updateMacroValues(phraseX: labPhraseX,
                          shieldY: labShieldY,
                          spaceX: labSpaceX,
                          decayY: value,
                          level: labEchoLevel,
                          persist: true)
    }

    func updateLabEchoLevel(_ value: Float) {
        updateMacroValues(phraseX: labPhraseX,
                          shieldY: labShieldY,
                          spaceX: labSpaceX,
                          decayY: labDecayY,
                          level: value,
                          persist: true)
    }

    private func updateMacroValues(phraseX: Float,
                                   shieldY: Float,
                                   spaceX: Float,
                                   decayY: Float,
                                   level: Float,
                                   persist: Bool) {
        let values = EchoLabMacroValues(phraseX: phraseX,
                                        shieldY: shieldY,
                                        spaceX: spaceX,
                                        decayY: decayY,
                                        level: level)
        isApplyingMacroMapping = true
        labPhraseX = values.phraseX
        labShieldY = values.shieldY
        labSpaceX = values.spaceX
        labDecayY = values.decayY
        labEchoLevel = values.level
        isApplyingMacroMapping = false
        if persist {
            persistLabMacroValues(values)
        }
        applyMacroMapping()
    }

    private func applyMacroMapping() {
        guard !isApplyingMacroMapping else { return }
        isApplyingMacroMapping = true

        let phrase = Double(labPhraseX)
        let shield = Double(labShieldY)
        let space = Double(labSpaceX)
        let decay = Double(labDecayY)
        let level = Double(labEchoLevel)

        echoPreRollDuration = lerp(0.05, 0.12, phrase)
        echoMaxCaptureDuration = lerp(0.28, 1.10, phrase)
        echoEndHangover = lerp(0.12, 0.45, phrase)
        echoHoldDuration = echoMaxCaptureDuration

        echoRetriggerInterval = lerp(0.35, 1.00, shield)
        echoHardDeafen = lerp(0.16, 0.34, shield)
        echoSnrMarginDB = Float(lerp(7.0, 14.0, shield))
        echoThreshMul = Float(lerp(1.45, 1.95, shield))
        echoThreshBias = Float(lerp(0.03, 0.08, shield))
        riseMinWhenEchoActive = Float(lerp(0.18, 0.26, shield))
        echoInputCurve = Float(lerp(1.30, 1.55, shield))
        echoInputFloor = Float(lerp(0.12, 0.18, shield))
        echoGateThreshold = Float(lerp(0.46, 0.60, shield))
        echoGateAttack = Float(lerp(0.05, 0.08, 1 - shield))
        echoGateRelease = Float(lerp(0.22, 0.35, shield))
        gateHighPassCutoff = Float(lerp(180, 240, shield))

        let delayTime = lerp(0.22, 0.45, space)
        echoDelayTime = delayTime
        let targetTail = lerp(1.1, 3.2, decay)
        let repeats = max(0.01, targetTail / max(0.01, delayTime))
        let feedbackCoeff = pow(0.01, 1 / repeats)
        let feedbackPercent = (feedbackCoeff * 100).clamped(to: 25...62)
        echoFeedback = Float(feedbackPercent)
        echoLowPassCutoff = Float(lerp(7500, 4200, decay))
        duckingStrength = Float(lerp(0.60, 0.82, decay))
        duckingResponse = 0.06
        duckingLevelScale = 1.5
        duckingDelay = 0.02

        echoMasterOutput = Float(lerp(0.40, 0.72, level))
        echoWetMixBase = Float(lerp(4, 10, level))
        echoWetMixRange = Float(lerp(52, 78, level))
        echoOutputRatio = Float(lerp(0.92, 0.98, level))

        isApplyingMacroMapping = false
        if lastSampleRate > 0 {
            configurePreRoll(sampleRate: lastSampleRate)
        }
    }


    private func persistSetting(_ key: EchoSettingKey, value: Float) {
        guard !isRestoringSettings else { return }
        UserDefaults.standard.set(NSNumber(value: value), forKey: key.rawValue)
    }

    private func persistSetting(_ key: EchoSettingKey, value: Double) {
        guard !isRestoringSettings else { return }
        UserDefaults.standard.set(NSNumber(value: value), forKey: key.rawValue)
    }

    private func persistSetting(_ key: EchoSettingKey, value: Bool) {
        guard !isRestoringSettings else { return }
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    private func persistLabSetting(_ key: EchoLabKey, value: Float) {
        guard !isRestoringLabSettings else { return }
        UserDefaults.standard.set(NSNumber(value: value), forKey: key.rawValue)
    }

    private func persistLabSetting(_ key: EchoLabKey, value: Bool) {
        guard !isRestoringLabSettings else { return }
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    private func persistLabMacroValues(_ values: EchoLabMacroValues) {
        persistLabSetting(.phraseX, value: values.phraseX)
        persistLabSetting(.shieldY, value: values.shieldY)
        persistLabSetting(.spaceX, value: values.spaceX)
        persistLabSetting(.decayY, value: values.decayY)
        persistLabSetting(.level, value: values.level)
    }

    private func persistLabSlot(_ slot: EchoLabSlot, values: EchoLabMacroValues) {
        switch slot {
        case .a:
            UserDefaults.standard.set(values.phraseX, forKey: EchoLabKey.slotAPhraseX.rawValue)
            UserDefaults.standard.set(values.shieldY, forKey: EchoLabKey.slotAShieldY.rawValue)
            UserDefaults.standard.set(values.spaceX, forKey: EchoLabKey.slotASpaceX.rawValue)
            UserDefaults.standard.set(values.decayY, forKey: EchoLabKey.slotADecayY.rawValue)
            UserDefaults.standard.set(values.level, forKey: EchoLabKey.slotALevel.rawValue)
        case .b:
            UserDefaults.standard.set(values.phraseX, forKey: EchoLabKey.slotBPhraseX.rawValue)
            UserDefaults.standard.set(values.shieldY, forKey: EchoLabKey.slotBShieldY.rawValue)
            UserDefaults.standard.set(values.spaceX, forKey: EchoLabKey.slotBSpaceX.rawValue)
            UserDefaults.standard.set(values.decayY, forKey: EchoLabKey.slotBDecayY.rawValue)
            UserDefaults.standard.set(values.level, forKey: EchoLabKey.slotBLevel.rawValue)
        }
    }

    private func loadFloat(_ key: EchoSettingKey, fallback: Float) -> Float {
        guard let number = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber else {
            return fallback
        }
        return number.floatValue
    }

    private func loadLabFloat(_ key: EchoLabKey, fallback: Float) -> Float {
        guard let number = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber else {
            return fallback
        }
        return number.floatValue
    }

    private func loadLabBool(_ key: EchoLabKey, fallback: Bool) -> Bool {
        guard let number = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber else {
            return fallback
        }
        return number.boolValue
    }

    private func loadDouble(_ key: EchoSettingKey, fallback: Double) -> Double {
        guard let number = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber else {
            return fallback
        }
        return number.doubleValue
    }

    private func loadBool(_ key: EchoSettingKey, fallback: Bool) -> Bool {
        guard let number = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber else {
            return fallback
        }
        return number.boolValue
    }

    private func loadLabSlot(_ slot: EchoLabSlot) -> EchoLabMacroValues {
        switch slot {
        case .a:
            return EchoLabMacroValues(
                phraseX: loadLabFloat(.slotAPhraseX, fallback: EchoLabDefaults.phraseX),
                shieldY: loadLabFloat(.slotAShieldY, fallback: EchoLabDefaults.shieldY),
                spaceX: loadLabFloat(.slotASpaceX, fallback: EchoLabDefaults.spaceX),
                decayY: loadLabFloat(.slotADecayY, fallback: EchoLabDefaults.decayY),
                level: loadLabFloat(.slotALevel, fallback: EchoLabDefaults.level)
            )
        case .b:
            return EchoLabMacroValues(
                phraseX: loadLabFloat(.slotBPhraseX, fallback: EchoLabDefaults.phraseX),
                shieldY: loadLabFloat(.slotBShieldY, fallback: EchoLabDefaults.shieldY),
                spaceX: loadLabFloat(.slotBSpaceX, fallback: EchoLabDefaults.spaceX),
                decayY: loadLabFloat(.slotBDecayY, fallback: EchoLabDefaults.decayY),
                level: loadLabFloat(.slotBLevel, fallback: EchoLabDefaults.level)
            )
        }
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
        resetEventState()

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

    func stopListening(completion: (() -> Void)? = nil) {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil
        isListening = false
        let sessionToStop = captureSession
        let outputToStop = captureOutput
        captureSession = nil
        captureInput = nil
        captureOutput = nil
        captureQueue.async { [weak self] in
            outputToStop?.setSampleBufferDelegate(nil, queue: nil)
            sessionToStop?.stopRunning()
            self?.isCapturing = false
            self?.isInjecting = false
            self?.captureSamples.removeAll()
            self?.captureTargetSamples = 0
            self?.captureMinSamples = 0
            self?.captureHangoverSamples = 0
            self?.captureSilenceSamples = 0
            self?.capturePreRollCount = 0
            self?.captureStartTime = 0
            self?.preRollBuffer.removeAll()
            self?.preRollIndex = 0
            self?.preRollFilled = false
            self?.cooldownUntil = 0
            self?.lastSampleRate = 0
            self?.highPassLastInput = 0
            self?.highPassLastOutput = 0
            self?.resetEventState()
            self?.calibrationMode = .none
            self?.calibrationSamples.removeAll()
            self?.stopPlaybackEngine()
            DispatchQueue.main.async { [weak self] in
                self?.deactivateAudioSession()
                completion?()
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
            var selectedMode: AVCaptureMultichannelAudioMode?
            if input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) {
                selectedMode = .firstOrderAmbisonics
            } else if input.isMultichannelAudioModeSupported(.stereo) {
                selectedMode = .stereo
            }
            if let selectedMode {
                input.multichannelAudioMode = selectedMode
            } else {
                print("Multichannel audio mode not supported on this device")
            }
            guard sessionCapture.canAddInput(input) else {
                print("Unable to add audio capture input")
                return
            }
            sessionCapture.addInput(input)

            let output = AVCaptureAudioDataOutput()
            if selectedMode == .firstOrderAmbisonics {
                output.spatialAudioChannelLayoutTag = foaLayoutTag
            }
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
    }

    private func stopPlaybackEngine() {
        if isWetTapInstalled {
            wetMeterNode?.removeTap(onBus: 0)
            isWetTapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        gateMixer = nil
        delayNode = nil
        boostNode = nil
        playbackFormat = nil
        isInjecting = false
        outDBMeter.set(outDBFloor)
        wetMeterNode = nil
        smoothedDelayTime = 0
        smoothedFeedback = 0
        smoothedLowPass = 0
        smoothedOutputGain = 0
        smoothedWetMix = 0
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
        delay.delayTime = echoDelayTime.clamped(to: 0.0...2.0)
        delay.feedback = echoFeedback.clamped(to: -100.0...100.0)
        delay.lowPassCutoff = echoLowPassCutoff.clamped(to: 10.0...20_000.0)
        delay.wetDryMix = 50

        let boost = AVAudioUnitEQ(numberOfBands: 1)
        boost.globalGain = echoBoostDb.clamped(to: -96.0...24.0)

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
            self.smoothedDelayTime = delay.delayTime
            self.smoothedFeedback = delay.feedback
            self.smoothedLowPass = delay.lowPassCutoff
            self.smoothedWetMix = delay.wetDryMix
            self.smoothedOutputGain = gateMixer.outputVolume
            installWetMeterTap(on: boost)
            return true
        } catch {
            print("Aurora playback engine failed: \(error)")
            return false
        }
    }

    private func installWetMeterTap(on node: AVAudioNode) {
        guard !isWetTapInstalled else { return }
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData?.pointee else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for i in 0..<frames {
                let value = data[i]
                sum += value * value
            }
            let rms = sqrt(sum / Float(frames))
            let db = 20 * log10(max(rms, 1e-7))
            self?.outDBMeter.set(db)
        }
        isWetTapInstalled = true
        wetMeterNode = node
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
        } else if abs(echoPreRollDuration - lastConfiguredPreRollDuration) > 0.001 {
            configurePreRoll(sampleRate: sampleRate)
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

        let rms = sqrt(sumGate2 / Float(frames))
        let inputGain = echoInputGain.clamped(to: 0.0...24.0)
        let inputCurve = echoInputCurve.clamped(to: 0.2...2.5)
        let normalizedLevel = min(1.0, rms * inputGain)
        let inputFloor = echoInputFloor.clamped(to: 0.0...1.5)
        let effectiveLevel: Float = normalizedLevel < inputFloor ? 0 : normalizedLevel
        let curvedLevel = pow(effectiveLevel, inputCurve)
        let micDB = 20 * log10(max(rms * inputGain, 1e-7))
        let micRiseDB = micDB - lastMicDB
        lastMicDB = micDB

        let estimatedFreq = (Double(zeroCrossings) / 2.0) * sampleRate / Double(frames)
        let logFreq = log2(estimatedFreq / 100.0) / 3.3
        let normalizedPitch = Float(min(1.0, max(0.0, logFreq)))

        let directionPoint = resolveDirectionPoint(sumXW: sumXW,
                                                   sumYW: sumYW,
                                                   sumZW: sumZW,
                                                   energy: sumW2,
                                                   level: effectiveLevel)

        let now = CFAbsoluteTimeGetCurrent()
        handleCalibration(now: now,
                          normalizedLevel: normalizedLevel,
                          micDB: micDB,
                          micRiseDB: micRiseDB)
        let gateThreshold = echoGateThreshold.clamped(to: 0.0...2.0)
        let dynamicThreshold = (gateThreshold * echoThreshMul + echoThreshBias).clamped(to: 0.0...2.0)
        currentDynamicThreshold = dynamicThreshold
        let endThreshold = (gateThreshold * 0.75).clamped(to: 0.0...2.0)
        currentEndThreshold = endThreshold
        let triggerRiseBase = max(0, echoTriggerRise)
        let echoActive = now < eventActiveUntil
        let triggerRise = echoActive ? max(triggerRiseBase, riseMinWhenEchoActive) : triggerRiseBase
        let retriggerInterval = max(0, echoRetriggerInterval)
        let levelRise = curvedLevel - lastCurvedLevel
        let passesMask = shouldTrigger(micDB: micDB,
                                       micRiseDB: micRiseDB,
                                       echoActive: echoActive,
                                       frameDuration: frameDuration)
        let withinCooldown = now < cooldownUntil
        let withinDeafen = labSoftLockoutEnabled && now < deafenUntil
        let shouldAttemptTrigger = !isCapturing && curvedLevel > dynamicThreshold && levelRise > triggerRise
        if shouldAttemptTrigger {
            if withinDeafen {
                lastBlockReason = "Blocked (deafen)"
                lastEventReason = lastBlockReason
            } else if withinCooldown {
                lastBlockReason = "Blocked (cooldown)"
                lastEventReason = lastBlockReason
            } else if !passesMask {
                lastBlockReason = "Blocked (SNR mask)"
                lastEventReason = lastBlockReason
            } else {
                lastEchoTriggerTime = now
                cooldownUntil = now + retriggerInterval
                if labSoftLockoutEnabled {
                    deafenUntil = now + max(0, echoHardDeafen)
                }
                lastTriggerLevel = curvedLevel
                pendingEventMix = min(1.0, max(0.0, curvedLevel))
                lastEventReason = "Triggered (rise)"
                beginCapture(preRoll: snapshotPreRoll(),
                             maxDuration: max(minCaptureDuration, echoMaxCaptureDuration),
                             endHangover: max(0, echoEndHangover),
                             sampleRate: sampleRate,
                             endThreshold: endThreshold)
            }
        }

        if isCapturing {
            if curvedLevel < endThreshold {
                captureSilenceSamples += frames
            } else {
                captureSilenceSamples = 0
            }

            let reachedMax = captureTargetSamples > 0 && captureSamples.count >= captureTargetSamples
            let reachedMin = captureSamples.count >= captureMinSamples
            let hangoverReached = captureHangoverSamples > 0 && captureSilenceSamples >= captureHangoverSamples
            if reachedMax || (reachedMin && hangoverReached) {
                lastEventReason = reachedMax ? "Ended capture (max duration)" : "Ended capture (silence hangover)"
                finalizeCapture(sampleRate: sampleRate)
            }
        }

        let targetEcho: Float = echoActive ? 1.0 : 0.0
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

        let outputLevel = (labFreezeEventGainEnabled && echoActive) ? eventMasterOutput : echoMasterOutput
        let outputRatio = (labFreezeEventGainEnabled && echoActive) ? eventOutputRatio : echoOutputRatio
        let triggerLevel = labFreezeEventGainEnabled ? lastTriggerLevel : curvedLevel
        let inputScale = (1 - outputRatio.clamped(to: 0.0...1.0)) + outputRatio.clamped(to: 0.0...1.0) * triggerLevel
        var outputGain = outputLevel.clamped(to: 0.0...1.0) * inputScale

        let smoothingCoeff = exp(-frameDuration / 0.06)
        let delayTarget = echoDelayTime.clamped(to: 0.0...2.0)
        let feedbackTarget = echoFeedback.clamped(to: -100.0...100.0)
        let lowPassTarget = echoLowPassCutoff.clamped(to: 10.0...20_000.0)
        smoothedDelayTime = smoothedDelayTime * smoothingCoeff + delayTarget * (1 - smoothingCoeff)
        smoothedFeedback = smoothedFeedback * Float(smoothingCoeff) + feedbackTarget * Float(1 - smoothingCoeff)
        smoothedLowPass = smoothedLowPass * Float(smoothingCoeff) + lowPassTarget * Float(1 - smoothingCoeff)
        delayNode?.delayTime = smoothedDelayTime
        delayNode?.feedback = smoothedFeedback
        delayNode?.lowPassCutoff = smoothedLowPass

        if !labFreezeEventGainEnabled, echoActive {
            let wetBase = echoWetMixBase.clamped(to: 0.0...100.0)
            let wetRange = echoWetMixRange.clamped(to: 0.0...100.0)
            let mix = eventMixAtTrigger
            let wetMix = wetBase + wetRange * mix
            eventWetMix = wetMix.clamped(to: 0.0...100.0)
            eventWetGain = min(0.90, max(0.0, eventWetMix / 100.0))
        }

        if echoWetOnly {
            delayNode?.wetDryMix = 100
            let gain = echoActive ? eventWetGain : 0
            outputGain *= gain
        } else {
            let wetMixTarget: Float = echoActive ? eventWetMix : 0
            smoothedWetMix = smoothedWetMix * Float(smoothingCoeff) + wetMixTarget * Float(1 - smoothingCoeff)
            delayNode?.wetDryMix = smoothedWetMix
        }

        boostNode?.globalGain = echoBoostDb.clamped(to: -96.0...24.0)
        if labLimiterEnabled {
            outputGain = min(outputGain, 0.85)
        }

        let targetOutput = isInjecting ? outputGain * duckingLevel : 0
        let outputCoeff = exp(-frameDuration / 0.05)
        smoothedOutputGain = smoothedOutputGain * Float(outputCoeff) + targetOutput * Float(1 - outputCoeff)
        gateMixer?.outputVolume = smoothedOutputGain

        publishDebugSnapshot(now: now,
                             sampleRate: sampleRate,
                             micDB: micDB,
                             echoActive: echoActive)

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

        lastCurvedLevel = curvedLevel
    }

    private func configurePreRoll(sampleRate: Double) {
        let duration = max(0.01, echoPreRollDuration)
        let capacity = max(1, Int(sampleRate * duration))
        preRollBuffer = Array(repeating: 0, count: capacity)
        preRollIndex = 0
        preRollFilled = false
        lastConfiguredPreRollDuration = duration
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

    private func beginCapture(preRoll: [Float],
                              maxDuration: Double,
                              endHangover: Double,
                              sampleRate: Double,
                              endThreshold: Float) {
        isCapturing = true
        captureSamples = preRoll
        capturePreRollCount = preRoll.count
        let maxSamples = max(0, Int(sampleRate * maxDuration))
        let minSamples = max(0, Int(sampleRate * minCaptureDuration))
        captureTargetSamples = capturePreRollCount + maxSamples
        captureMinSamples = capturePreRollCount + minSamples
        captureHangoverSamples = max(0, Int(sampleRate * endHangover))
        captureSilenceSamples = 0
        captureStartTime = CFAbsoluteTimeGetCurrent()
        currentEndThreshold = endThreshold

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
            captureMinSamples = 0
            captureHangoverSamples = 0
            captureSilenceSamples = 0
            capturePreRollCount = 0
            return
        }

        scheduleSnippetPlayback(samples: captureSamples, sampleRate: sampleRate)
        captureSamples.removeAll()
        captureTargetSamples = 0
        captureMinSamples = 0
        captureHangoverSamples = 0
        captureSilenceSamples = 0
        capturePreRollCount = 0
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
                data.update(from: base, count: samples.count)
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

        let now = CFAbsoluteTimeGetCurrent()
        beginEchoEvent(now: now,
                       delayTime: echoDelayTime,
                       feedback: echoFeedback,
                       mixAtTrigger: pendingEventMix)
    }

    private func beginEchoEvent(now: Double,
                                delayTime: Double,
                                feedback: Float,
                                mixAtTrigger: Float) {
        let wetBase = echoWetMixBase.clamped(to: 0.0...100.0)
        let wetRange = echoWetMixRange.clamped(to: 0.0...100.0)
        let mix = max(0, min(1, mixAtTrigger))
        let wetMix = wetBase + wetRange * mix
        eventWetMix = wetMix.clamped(to: 0.0...100.0)
        eventWetGain = min(0.90, max(0.0, eventWetMix / 100.0))
        eventMixAtTrigger = mix
        if labFreezeEventGainEnabled {
            eventMasterOutput = echoMasterOutput
            eventOutputRatio = echoOutputRatio
        } else {
            eventMasterOutput = 0
            eventOutputRatio = 0
        }

        let tail = estimatedTailDuration(delayTime: delayTime, feedback: feedback)
        eventActiveUntil = max(eventActiveUntil, now + tail)
    }

    private func estimatedTailDuration(delayTime: Double, feedback: Float) -> Double {
        let magnitude = abs(feedback) / 100.0
        guard magnitude > 0.01 else { return delayTime + 0.15 }
        let fb = min(0.99, max(0.01, Double(magnitude)))
        let target = 0.01
        let repeats = ceil(log(target) / log(fb))
        guard repeats.isFinite else { return delayTime + 0.15 }
        return delayTime * max(0, repeats) + 0.15
    }

    private func shouldTrigger(micDB: Float,
                               micRiseDB: Float,
                               echoActive: Bool,
                               frameDuration: Double) -> Bool {
        guard labOutputMaskEnabled else { return true }
        guard echoActive else { return true }
        let outDB = outDBMeter.get()

        if abs(micRiseDB) < bleedRiseGuardDB {
            let delta = micDB - outDB
            let stepCap = max(0.1, bleedStepCap)
            let clampedDelta = delta.clamped(to: (bleedDeltaDB - stepCap)...(bleedDeltaDB + stepCap))
            let tau = clampedDelta > bleedDeltaDB ? max(0.01, bleedTauUp) : max(0.01, bleedTauDown)
            let alpha = 1 - exp(-frameDuration / tau)
            bleedDeltaDB = bleedDeltaDB + (clampedDelta - bleedDeltaDB) * Float(alpha)
        }

        let required = outDB + bleedDeltaDB + echoSnrMarginDB
        return micDB >= required
    }

    func startSilenceCalibration() {
        guard calibrationMode == .none else { return }
        calibrationMode = .silence
        calibrationSamples.removeAll()
        calibrationStartTime = CFAbsoluteTimeGetCurrent()
        calibrationEndTime = calibrationStartTime + 1.5
        lastEventReason = "Calibrating silence"
    }

    func startBleedCalibration() {
        guard calibrationMode == .none else { return }
        calibrationMode = .bleed
        calibrationSamples.removeAll()
        calibrationStartTime = CFAbsoluteTimeGetCurrent()
        calibrationEndTime = calibrationStartTime + 2.0
        lastEventReason = "Calibrating bleed"
    }

    private func handleCalibration(now: Double,
                                   normalizedLevel: Float,
                                   micDB: Float,
                                   micRiseDB: Float) {
        guard calibrationMode != .none else { return }

        switch calibrationMode {
        case .silence:
            calibrationSamples.append(normalizedLevel)
            guard now >= calibrationEndTime else { return }
            let noiseFloor = percentile(calibrationSamples, percent: 0.9)
            let inputFloor = (noiseFloor * 1.2).clamped(to: 0.0...1.5)
            let gateThreshold = max(echoGateThreshold, noiseFloor * 1.6 + 0.03)
            DispatchQueue.main.async { [weak self] in
                self?.echoInputFloor = inputFloor
                self?.echoGateThreshold = gateThreshold
            }
            lastEventReason = "Calibrated silence"
            calibrationMode = .none
            calibrationSamples.removeAll()
        case .bleed:
            if abs(micRiseDB) < bleedRiseGuardDB {
                let outDB = outDBMeter.get()
                calibrationSamples.append(micDB - outDB)
            }
            guard now >= calibrationEndTime else { return }
            let averageDelta: Float
            if calibrationSamples.isEmpty {
                averageDelta = bleedDeltaDB
            } else {
                averageDelta = calibrationSamples.reduce(0, +) / Float(calibrationSamples.count)
            }
            bleedDeltaDB = averageDelta
            let newMargin = (averageDelta + 9).clamped(to: 7...14)
            DispatchQueue.main.async { [weak self] in
                self?.echoSnrMarginDB = newMargin
            }
            lastEventReason = "Calibrated bleed"
            calibrationMode = .none
            calibrationSamples.removeAll()
        case .none:
            break
        }
    }

    private func percentile(_ values: [Float], percent: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Float(sorted.count - 1) * percent)
        return sorted[max(0, min(sorted.count - 1, index))]
    }

    private func publishDebugSnapshot(now: Double,
                                      sampleRate: Double,
                                      micDB: Float,
                                      echoActive: Bool) {
        guard now - lastDebugPublishTime >= (1.0 / 30.0) else { return }
        lastDebugPublishTime = now

        let outDB = outDBMeter.get()
        let bleedMargin = micDB - (outDB + bleedDeltaDB)
        let tailRemaining = max(0, eventActiveUntil - now)
        let captureProgressSamples = max(0, captureSamples.count - capturePreRollCount)
        let captureElapsed = isCapturing ? max(0, Double(captureProgressSamples) / max(1, sampleRate)) : 0
        let nextTriggerIn = max(0, max(cooldownUntil, labSoftLockoutEnabled ? deafenUntil : 0) - now)

        let state: EchoLabState
        if !isListening {
            state = .idle
        } else if isCapturing {
            state = .capturing
        } else if isInjecting {
            state = .injecting
        } else if tailRemaining > 0 {
            state = .tail
        } else if labSoftLockoutEnabled && now < deafenUntil {
            state = .deafened
        } else {
            state = .armed
        }

        let calibrationRemaining = calibrationMode == .none ? 0 : max(0, calibrationEndTime - now)
        let calibrationMessage: String?
        switch calibrationMode {
        case .silence:
            calibrationMessage = "Hold still and be quiet..."
        case .bleed:
            calibrationMessage = "Play echo, stay silent..."
        case .none:
            calibrationMessage = nil
        }

        let snapshot = EchoLabDebugSnapshot(state: state,
                                            captureElapsed: captureElapsed,
                                            captureMax: echoMaxCaptureDuration,
                                            tailRemaining: tailRemaining,
                                            nextTriggerIn: nextTriggerIn,
                                            micDB: micDB,
                                            outDB: outDB,
                                            bleedMarginDB: bleedMargin,
                                            lastEventReason: lastEventReason,
                                            bleedDeltaDB: bleedDeltaDB,
                                            dynamicThreshold: currentDynamicThreshold,
                                            endThreshold: currentEndThreshold,
                                            lastBlockReason: lastBlockReason,
                                            eventWetGain: eventWetGain,
                                            calibrationMessage: calibrationMessage,
                                            calibrationRemaining: calibrationRemaining)
        DispatchQueue.main.async { [weak self] in
            self?.debugSnapshot = snapshot
        }
    }

    private func lerp(_ start: Double, _ end: Double, _ t: Double) -> Double {
        start + (end - start) * t
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
        guard channelCount > 0 else { return }

        if isFloat {
            if isNonInterleaved {
                guard let w = bufferList.first?.mData?.assumingMemoryBound(to: Float.self) else {
                    return
                }
                let y = bufferList.count > 1 ? bufferList[1].mData?.assumingMemoryBound(to: Float.self) : nil
                let z = bufferList.count > 2 ? bufferList[2].mData?.assumingMemoryBound(to: Float.self) : nil
                let x = bufferList.count > 3 ? bufferList[3].mData?.assumingMemoryBound(to: Float.self) : nil

                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    switch channel {
                    case 0: return w[index]
                    case 1: return y?[index] ?? 0
                    case 2: return z?[index] ?? 0
                    default: return x?[index] ?? 0
                    }
                }
            } else {
                guard bufferList.count == 1,
                      let data = bufferList[0].mData?.assumingMemoryBound(to: Float.self) else {
                    return
                }

                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    channel < channelCount ? data[index * channelCount + channel] : 0
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 16 {
            if isNonInterleaved {
                guard let w = bufferList.first?.mData?.assumingMemoryBound(to: Int16.self) else {
                    return
                }
                let y = bufferList.count > 1 ? bufferList[1].mData?.assumingMemoryBound(to: Int16.self) : nil
                let z = bufferList.count > 2 ? bufferList[2].mData?.assumingMemoryBound(to: Int16.self) : nil
                let x = bufferList.count > 3 ? bufferList[3].mData?.assumingMemoryBound(to: Int16.self) : nil

                let scale = 1.0 / Float(Int16.max)
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    switch channel {
                    case 0: return Float(w[index]) * scale
                    case 1: return Float(y?[index] ?? 0) * scale
                    case 2: return Float(z?[index] ?? 0) * scale
                    default: return Float(x?[index] ?? 0) * scale
                    }
                }
            } else {
                guard bufferList.count == 1,
                      let data = bufferList[0].mData?.assumingMemoryBound(to: Int16.self) else {
                    return
                }

                let scale = 1.0 / Float(Int16.max)
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    channel < channelCount ? Float(data[index * channelCount + channel]) * scale : 0
                }
            }
        } else if asbd.pointee.mBitsPerChannel == 32 {
            if isNonInterleaved {
                guard let w = bufferList.first?.mData?.assumingMemoryBound(to: Int32.self) else {
                    return
                }
                let y = bufferList.count > 1 ? bufferList[1].mData?.assumingMemoryBound(to: Int32.self) : nil
                let z = bufferList.count > 2 ? bufferList[2].mData?.assumingMemoryBound(to: Int32.self) : nil
                let x = bufferList.count > 3 ? bufferList[3].mData?.assumingMemoryBound(to: Int32.self) : nil

                let scale = 1.0 / Float(Int32.max)
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    switch channel {
                    case 0: return Float(w[index]) * scale
                    case 1: return Float(y?[index] ?? 0) * scale
                    case 2: return Float(z?[index] ?? 0) * scale
                    default: return Float(x?[index] ?? 0) * scale
                    }
                }
            } else {
                guard bufferList.count == 1,
                      let data = bufferList[0].mData?.assumingMemoryBound(to: Int32.self) else {
                    return
                }

                let scale = 1.0 / Float(Int32.max)
                processSpatialSamples(frames: frames, sampleRate: sampleRate) { index, channel in
                    channel < channelCount ? Float(data[index * channelCount + channel]) * scale : 0
                }
            }
        }
    }

    private static func audioBufferListSize(maximumBuffers: Int) -> Int {
        MemoryLayout<AudioBufferList>.size + (maximumBuffers - 1) * MemoryLayout<AudioBuffer>.size
    }
}

private final class AtomicFloat {
    private let lock = NSLock()
    private var value: Float

    init(initialValue: Float) {
        self.value = initialValue
    }

    func set(_ newValue: Float) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Float {
        lock.lock()
        let current = value
        lock.unlock()
        return current
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
        .environmentObject(AudioCoordinator())
}
