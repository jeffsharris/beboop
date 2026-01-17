import SwiftUI
import Foundation

enum EchoLabState: String {
    case idle
    case armed
    case capturing
    case injecting
    case tail
    case deafened

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .armed: return "Armed"
        case .capturing: return "Capturing"
        case .injecting: return "Injecting"
        case .tail: return "Tail"
        case .deafened: return "Deafened"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .armed: return .blue
        case .capturing: return .orange
        case .injecting: return .green
        case .tail: return .teal
        case .deafened: return .red
        }
    }
}

enum EchoLabSlot: Int, CaseIterable {
    case a = 0
    case b = 1

    var label: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        }
    }
}

enum EchoLabCalibrationMode {
    case none
    case silence
    case bleed
}

struct EchoLabMacroValues: Equatable {
    let phraseX: Float
    let shieldY: Float
    let spaceX: Float
    let decayY: Float
    let level: Float

    init(phraseX: Float, shieldY: Float, spaceX: Float, decayY: Float, level: Float) {
        self.phraseX = min(1, max(0, phraseX))
        self.shieldY = min(1, max(0, shieldY))
        self.spaceX = min(1, max(0, spaceX))
        self.decayY = min(1, max(0, decayY))
        self.level = min(1, max(0, level))
    }

    static let defaultSlot = EchoLabMacroValues(phraseX: 0.45,
                                                shieldY: 0.62,
                                                spaceX: 0.55,
                                                decayY: 0.55,
                                                level: 0.55)
}

struct EchoLabDebugSnapshot: Equatable {
    var state: EchoLabState = .idle
    var captureElapsed: Double = 0
    var captureMax: Double = 0
    var tailRemaining: Double = 0
    var nextTriggerIn: Double = 0
    var micDB: Float = -160
    var outDB: Float = -160
    var bleedMarginDB: Float = 0
    var lastEventReason: String = "Idle"
    var bleedDeltaDB: Float = 0
    var dynamicThreshold: Float = 0
    var endThreshold: Float = 0
    var lastBlockReason: String = "Idle"
    var eventWetGain: Float = 0
    var calibrationMessage: String?
    var calibrationRemaining: Double = 0
}

struct EchoLabView: View {
    @ObservedObject var audioProcessor: AuroraAudioProcessor
    @Binding var isPresented: Bool
    @State private var isAdvancedExpanded = false

    private var phraseBinding: Binding<Float> {
        Binding(get: { audioProcessor.labPhraseX },
                set: { audioProcessor.updateLabPhraseX($0) })
    }

    private var shieldBinding: Binding<Float> {
        Binding(get: { audioProcessor.labShieldY },
                set: { audioProcessor.updateLabShieldY($0) })
    }

    private var spaceBinding: Binding<Float> {
        Binding(get: { audioProcessor.labSpaceX },
                set: { audioProcessor.updateLabSpaceX($0) })
    }

    private var decayBinding: Binding<Float> {
        Binding(get: { audioProcessor.labDecayY },
                set: { audioProcessor.updateLabDecayY($0) })
    }

    private var levelBinding: Binding<Float> {
        Binding(get: { audioProcessor.labEchoLevel },
                set: { audioProcessor.updateLabEchoLevel($0) })
    }

    private var slotBinding: Binding<EchoLabSlot> {
        Binding(get: { audioProcessor.labActiveSlot },
                set: { audioProcessor.activateLabSlot($0) })
    }

    var body: some View {
        VStack(spacing: 16) {
            EchoLabHeaderView(snapshot: audioProcessor.debugSnapshot)

            if let message = audioProcessor.debugSnapshot.calibrationMessage {
                Text("\(message) \(String(format: "%.1fs", audioProcessor.debugSnapshot.calibrationRemaining))")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView {
                VStack(spacing: 20) {
                    phraseShieldSection
                    spaceDecaySection
                    echoLevelSection
                    quickActionsSection
                    advancedSection
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var phraseShieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EchoLabPad(title: "Phrase × Shield",
                       xLabelLeft: "Short phrase",
                       xLabelRight: "Long phrase",
                       yLabelBottom: "Loose (more triggers)",
                       yLabelTop: "Shielded (no self-trigger)",
                       xValue: phraseBinding,
                       yValue: shieldBinding)

            EchoLabValueGrid(rows: [
                ("maxCapture", String(format: "%.2fs", audioProcessor.echoMaxCaptureDuration)),
                ("hangover", String(format: "%.2fs", audioProcessor.echoEndHangover)),
                ("retrigger", String(format: "%.2fs", audioProcessor.echoRetriggerInterval)),
                ("hardDeafen", String(format: "%.2fs", audioProcessor.echoHardDeafen)),
                ("snrMargin", String(format: "%.1f dB", audioProcessor.echoSnrMarginDB)),
                ("gateThresh", String(format: "%.2f", audioProcessor.echoGateThreshold)),
                ("riseMin", String(format: "%.2f", audioProcessor.riseMinWhenEchoActive))
            ])
        }
    }

    private var spaceDecaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EchoLabPad(title: "Space × Decay",
                       xLabelLeft: "Tight",
                       xLabelRight: "Wide",
                       yLabelBottom: "Short tail",
                       yLabelTop: "Long tail",
                       xValue: spaceBinding,
                       yValue: decayBinding)

            EchoLabValueGrid(rows: [
                ("delayTime", String(format: "%.2fs", audioProcessor.echoDelayTime)),
                ("feedback", String(format: "%.0f%%", audioProcessor.echoFeedback)),
                ("lowpass", String(format: "%.0f Hz", audioProcessor.echoLowPassCutoff)),
                ("estimatedTail", String(format: "%.2fs", estimatedTail(delayTime: audioProcessor.echoDelayTime,
                                                                           feedback: audioProcessor.echoFeedback)))
            ])
        }
    }

    private var echoLevelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Echo Level")
                .font(.headline)

            HStack(spacing: 12) {
                Slider(value: levelBinding, in: 0...1)
                Text(String(format: "%.2f", audioProcessor.labEchoLevel))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 56, alignment: .trailing)
            }

            EchoLabValueGrid(rows: [
                ("masterOutput", String(format: "%.2f", audioProcessor.echoMasterOutput)),
                ("wetGain(event)", String(format: "%.2f", audioProcessor.debugSnapshot.eventWetGain)),
                ("wetBase / wetRange", String(format: "%.0f / %.0f", audioProcessor.echoWetMixBase, audioProcessor.echoWetMixRange))
            ])
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Slot", selection: slotBinding) {
                ForEach(EchoLabSlot.allCases, id: \.rawValue) { slot in
                    Text(slot.label).tag(slot)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button("Save to A") {
                    audioProcessor.saveLabSlot(.a)
                }
                .buttonStyle(.bordered)

                Button("Save to B") {
                    audioProcessor.saveLabSlot(.b)
                }
                .buttonStyle(.bordered)

                Button("Reset to Default") {
                    audioProcessor.resetLabToDefaults()
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 12) {
                Button("Calibrate Silence") {
                    audioProcessor.startSilenceCalibration()
                }
                .buttonStyle(.bordered)

                Button("Calibrate Bleed") {
                    audioProcessor.startBleedCalibration()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable soft lockout", isOn: $audioProcessor.labSoftLockoutEnabled)
                Toggle("Enable output mask", isOn: $audioProcessor.labOutputMaskEnabled)
                Toggle("Enable freeze event gain", isOn: $audioProcessor.labFreezeEventGainEnabled)
                Toggle("Limiter on wet bus", isOn: $audioProcessor.labLimiterEnabled)

                EchoLabNumberField(label: "snrMarginDB", value: $audioProcessor.echoSnrMarginDB)
                EchoLabNumberField(label: "hardDeafen", value: $audioProcessor.echoHardDeafen)
                EchoLabNumberField(label: "bleedTauUp", value: $audioProcessor.bleedTauUp)
                EchoLabNumberField(label: "bleedTauDown", value: $audioProcessor.bleedTauDown)
                EchoLabNumberField(label: "bleedStepCap", value: $audioProcessor.bleedStepCap)
                EchoLabNumberField(label: "threshMul", value: $audioProcessor.echoThreshMul)
                EchoLabNumberField(label: "threshBias", value: $audioProcessor.echoThreshBias)
                EchoLabNumberField(label: "riseMinWhenEchoActive", value: $audioProcessor.riseMinWhenEchoActive)

                VStack(alignment: .leading, spacing: 6) {
                    EchoLabValueRow(label: "bleedDeltaDB", value: String(format: "%.1f dB", audioProcessor.debugSnapshot.bleedDeltaDB))
                    EchoLabValueRow(label: "dynThreshold", value: String(format: "%.2f", audioProcessor.debugSnapshot.dynamicThreshold))
                    EchoLabValueRow(label: "lastBlockReason", value: audioProcessor.debugSnapshot.lastBlockReason)
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
    }

    private func estimatedTail(delayTime: Double, feedback: Float) -> Double {
        let magnitude = abs(feedback) / 100.0
        guard magnitude > 0.01 else { return delayTime + 0.15 }
        let fb = min(0.99, max(0.01, Double(magnitude)))
        let target = 0.01
        let repeats = ceil(log(target) / log(fb))
        guard repeats.isFinite else { return delayTime + 0.15 }
        return delayTime * max(0, repeats) + 0.15
    }
}

struct EchoLabHeaderView: View {
    let snapshot: EchoLabDebugSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.state.label.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(snapshot.state.color)
                    .clipShape(Capsule())

                Spacer()
            }

            HStack(spacing: 16) {
                EchoLabStat(label: "Capture",
                            value: String(format: "%.2f / %.2f", snapshot.captureElapsed, snapshot.captureMax))
                EchoLabStat(label: "Tail",
                            value: String(format: "%.2fs", snapshot.tailRemaining))
                EchoLabStat(label: "Next",
                            value: String(format: "%.2fs", snapshot.nextTriggerIn))
            }

            VStack(spacing: 6) {
                EchoLabMeter(label: "Mic dB", value: snapshot.micDB)
                EchoLabMeter(label: "Out dB", value: snapshot.outDB)
                EchoLabMeter(label: "Bleed margin", value: snapshot.bleedMarginDB)
            }

            Text("Last: \(snapshot.lastEventReason)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct EchoLabPad: View {
    let title: String
    let xLabelLeft: String
    let xLabelRight: String
    let yLabelBottom: String
    let yLabelTop: String
    @Binding var xValue: Float
    @Binding var yValue: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            GeometryReader { proxy in
                let size = proxy.size
                let xPos = CGFloat(xValue) * size.width
                let yPos = (1 - CGFloat(yValue)) * size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                    Path { path in
                        path.move(to: CGPoint(x: xPos, y: 0))
                        path.addLine(to: CGPoint(x: xPos, y: size.height))
                        path.move(to: CGPoint(x: 0, y: yPos))
                        path.addLine(to: CGPoint(x: size.width, y: yPos))
                    }
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)

                    Circle()
                        .fill(Color.primary)
                        .frame(width: 12, height: 12)
                        .position(x: xPos, y: yPos)

                    VStack {
                        Text(yLabelTop)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                        Spacer()
                        Text(yLabelBottom)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 6)
                    }

                    HStack {
                        Text(xLabelLeft)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 6)
                        Spacer()
                        Text(xLabelRight)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 6)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clampedX = min(max(0, value.location.x / size.width), 1)
                            let clampedY = min(max(0, 1 - (value.location.y / size.height)), 1)
                            xValue = Float(clampedX)
                            yValue = Float(clampedY)
                        }
                )
            }
            .frame(height: 180)
        }
    }
}

struct EchoLabValueGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { row in
                EchoLabValueRow(label: row.0, value: row.1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

struct EchoLabValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
        }
    }
}

struct EchoLabNumberField: View {
    let label: String
    @Binding var value: Float

    init(label: String, value: Binding<Float>) {
        self.label = label
        self._value = value
    }

    init(label: String, value: Binding<Double>) {
        self.label = label
        self._value = Binding(
            get: { Float(value.wrappedValue) },
            set: { value.wrappedValue = Double($0) }
        )
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.footnote, design: .monospaced))
                .frame(width: 90)
        }
    }
}

struct EchoLabStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
        }
    }
}

struct EchoLabMeter: View {
    let label: String
    let value: Float

    private var normalized: CGFloat {
        let clamped = min(0, max(-60, value))
        return CGFloat((clamped + 60) / 60)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: proxy.size.width * normalized)
                }
            }
            .frame(height: 6)

            Text(String(format: "%.1f", value))
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
        }
    }
}
