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
    @State private var isTuningPresented = false

    private let waveCooldown: TimeInterval = 0.16
    private let waveMinLevel: Double = 0.08
    private let waveMaxAge: Double = 2.9
    private let waveBaseSpeed: Double = 170

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = max(16, geometry.safeAreaInsets.bottom + 8)
            let panelMaxHeight = min(geometry.size.height * 0.7, 620)

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

                tuningButton(bottomInset: bottomInset)

                if isTuningPresented {
                    tuningPanel(bottomInset: bottomInset, maxHeight: panelMaxHeight)
                }
            }
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

    private func tuningButton(bottomInset: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTuningPresented.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.leading, 18)
                .padding(.bottom, bottomInset)
                Spacer()
            }
        }
    }

    private func tuningPanel(bottomInset: CGFloat, maxHeight: CGFloat) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Echo Tuning")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTuningPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sliderSectionHeader("Output")
                        sliderRow(title: "Master Output",
                                  value: floatBinding(\.echoMasterOutput),
                                  range: 0...1,
                                  step: 0.01,
                                  format: "%.2f")
                        Toggle("Wet Only (no dry monitor)",
                               isOn: boolBinding(\.echoWetOnly))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)

                        sliderSectionHeader("Input Mapping")
                        controlPad(title: "Gain vs Curve",
                                   xLabel: "Gain",
                                   yLabel: "Curve",
                                   xValue: floatBinding(\.echoInputGain),
                                   yValue: floatBinding(\.echoInputCurve),
                                   xRange: 0...24,
                                   yRange: 0.2...2.5)
                        inputCurvePreview()
                            .frame(height: 120)
                        sliderRow(title: "Input Gain",
                                  value: floatBinding(\.echoInputGain),
                                  range: 0...24,
                                  step: 0.2,
                                  format: "%.1f")
                        sliderRow(title: "Input Curve",
                                  value: floatBinding(\.echoInputCurve),
                                  range: 0.2...2.5,
                                  step: 0.05,
                                  format: "%.2f")
                        sliderRow(title: "Input Floor",
                                  value: floatBinding(\.echoInputFloor),
                                  range: 0.0...1.5,
                                  step: 0.01,
                                  format: "%.2f")

                        sliderSectionHeader("Gate")
                        sliderRow(title: "Gate Threshold",
                                  value: floatBinding(\.echoGateThreshold),
                                  range: 0.0...2.0,
                                  step: 0.02,
                                  format: "%.2f")
                        sliderRow(title: "Gate Attack",
                                  value: floatBinding(\.echoGateAttack),
                                  range: 0.05...0.99,
                                  step: 0.02,
                                  format: "%.2f")
                        sliderRow(title: "Gate Release",
                                  value: floatBinding(\.echoGateRelease),
                                  range: 0.05...0.99,
                                  step: 0.02,
                                  format: "%.2f")

                        sliderSectionHeader("Trigger")
                        sliderRow(title: "Trigger Rise",
                                  value: floatBinding(\.echoTriggerRise),
                                  range: 0.0...0.6,
                                  step: 0.02,
                                  format: "%.3f")
                        sliderRow(title: "Retrigger Interval",
                                  value: doubleBinding(\.echoRetriggerInterval),
                                  range: 0.0...8.0,
                                  step: 0.1,
                                  format: "%.2f",
                                  suffix: "s")
                        sliderRow(title: "Hold Duration",
                                  value: doubleBinding(\.echoHoldDuration),
                                  range: 0.0...2.0,
                                  step: 0.05,
                                  format: "%.2f",
                                  suffix: "s")

                        sliderSectionHeader("Echo Tail")
                        controlPad(title: "Delay vs Feedback",
                                   xLabel: "Delay",
                                   yLabel: "Feedback",
                                   xValue: doubleBinding(\.echoDelayTime),
                                   yValue: floatBinding(\.echoFeedback),
                                   xRange: 0.0...2.0,
                                   yRange: -100.0...100.0,
                                   showZeroLine: true)

                        sliderSectionHeader("Delay")
                        sliderRow(title: "Delay Time",
                                  value: doubleBinding(\.echoDelayTime),
                                  range: 0.0...2.0,
                                  step: 0.05,
                                  format: "%.2f",
                                  suffix: "s")
                        sliderRow(title: "Feedback",
                                  value: floatBinding(\.echoFeedback),
                                  range: -100...100,
                                  step: 2,
                                  format: "%.0f")
                        sliderRow(title: "Wet Base",
                                  value: floatBinding(\.echoWetMixBase),
                                  range: 0...100,
                                  step: 1,
                                  format: "%.0f")
                        sliderRow(title: "Wet Range",
                                  value: floatBinding(\.echoWetMixRange),
                                  range: 0...100,
                                  step: 1,
                                  format: "%.0f")

                        sliderSectionHeader("Tone")
                        sliderRow(title: "Low-pass",
                                  value: floatBinding(\.echoLowPassCutoff),
                                  range: 10...20000,
                                  step: 200,
                                  format: "%.0f",
                                  suffix: "Hz")
                        sliderRow(title: "Boost",
                                  value: floatBinding(\.echoBoostDb),
                                  range: -96...24,
                                  step: 1,
                                  format: "%.1f",
                                  suffix: "dB")

                        sliderSectionHeader("Ducking")
                        sliderRow(title: "Strength",
                                  value: floatBinding(\.duckingStrength),
                                  range: 0...1.0,
                                  step: 0.05,
                                  format: "%.2f")
                        sliderRow(title: "Response",
                                  value: floatBinding(\.duckingResponse),
                                  range: 0.01...1.0,
                                  step: 0.02,
                                  format: "%.2f")
                        sliderRow(title: "Level Scale",
                                  value: floatBinding(\.duckingLevelScale),
                                  range: 0...2.0,
                                  step: 0.05,
                                  format: "%.2f")
                        sliderRow(title: "Ducking Delay",
                                  value: doubleBinding(\.duckingDelay),
                                  range: 0...1.0,
                                  step: 0.02,
                                  format: "%.2f",
                                  suffix: "s")
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: maxHeight)

                Button {
                    audioProcessor.resetEchoDefaults()
                } label: {
                    Text("Reset Defaults")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, bottomInset)
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func sliderRow(title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           format: String,
                           suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                Spacer()
                Text(String(format: format, value.wrappedValue) + suffix)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func controlPad(title: String,
                            xLabel: String,
                            yLabel: String,
                            xValue: Binding<Double>,
                            yValue: Binding<Double>,
                            xRange: ClosedRange<Double>,
                            yRange: ClosedRange<Double>,
                            showZeroLine: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(xLabel) \(formatValue(xValue.wrappedValue)) · \(yLabel) \(formatValue(yValue.wrappedValue))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            GeometryReader { proxy in
                let size = proxy.size
                let handlePosition = controlPadPosition(size: size,
                                                        xValue: xValue.wrappedValue,
                                                        yValue: yValue.wrappedValue,
                                                        xRange: xRange,
                                                        yRange: yRange)

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )

                    controlPadGrid(size: size)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)

                    if showZeroLine, yRange.lowerBound < 0, yRange.upperBound > 0 {
                        let zeroY = controlPadZeroLine(size: size, yRange: yRange)
                        Path { path in
                            path.move(to: CGPoint(x: 8, y: zeroY))
                            path.addLine(to: CGPoint(x: size.width - 8, y: zeroY))
                        }
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                    }

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .position(handlePosition)
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let location = CGPoint(x: min(max(0, value.location.x), size.width),
                                                   y: min(max(0, value.location.y), size.height))
                            let normalizedX = location.x / max(1, size.width)
                            let normalizedY = 1 - (location.y / max(1, size.height))

                            xValue.wrappedValue = xRange.lowerBound + normalizedX * (xRange.upperBound - xRange.lowerBound)
                            yValue.wrappedValue = yRange.lowerBound + normalizedY * (yRange.upperBound - yRange.lowerBound)
                        }
                )
            }
            .frame(height: 140)

            HStack {
                Text(xLabel)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(yLabel)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func inputCurvePreview() -> some View {
        let gain = Double(audioProcessor.echoInputGain)
        let curve = Double(audioProcessor.echoInputCurve)
        let floor = Double(audioProcessor.echoInputFloor)
        let threshold = Double(audioProcessor.echoGateThreshold)

        return GeometryReader { proxy in
            let size = proxy.size
            let lineWidth = max(2, size.width * 0.008)
            let path = Path { path in
                let steps = 80
                let clampedCurve = min(2.5, max(0.2, curve))
                for step in 0...steps {
                    let x = Double(step) / Double(steps)
                    let normalized = min(1.0, x * max(0, gain))
                    let effective = normalized < floor ? 0 : normalized
                    let shaped = pow(effective, clampedCurve)
                    let plotX = x * size.width
                    let plotY = size.height - min(1.2, shaped) / 1.2 * size.height

                    if step == 0 {
                        path.move(to: CGPoint(x: plotX, y: plotY))
                    } else {
                        path.addLine(to: CGPoint(x: plotX, y: plotY))
                    }

                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                if gain > 0 {
                    let floorX = min(1.0, floor / max(0.0001, gain)) * size.width
                    Path { path in
                        path.move(to: CGPoint(x: floorX, y: 10))
                        path.addLine(to: CGPoint(x: floorX, y: size.height - 10))
                    }
                    .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                }

                let thresholdY = size.height - min(1.2, max(0, threshold)) / 1.2 * size.height
                Path { path in
                    path.move(to: CGPoint(x: 10, y: thresholdY))
                    path.addLine(to: CGPoint(x: size.width - 10, y: thresholdY))
                }
                .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

                path
                    .stroke(Color.white.opacity(0.85), lineWidth: lineWidth)
            }
        }
    }

    private func sliderSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.top, 6)
    }

    private func floatBinding(_ keyPath: ReferenceWritableKeyPath<AuroraAudioProcessor, Float>) -> Binding<Double> {
        Binding(
            get: { Double(audioProcessor[keyPath: keyPath]) },
            set: { audioProcessor[keyPath: keyPath] = Float($0) }
        )
    }

    private func doubleBinding(_ keyPath: ReferenceWritableKeyPath<AuroraAudioProcessor, Double>) -> Binding<Double> {
        Binding(
            get: { audioProcessor[keyPath: keyPath] },
            set: { audioProcessor[keyPath: keyPath] = $0 }
        )
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<AuroraAudioProcessor, Bool>) -> Binding<Bool> {
        Binding(
            get: { audioProcessor[keyPath: keyPath] },
            set: { audioProcessor[keyPath: keyPath] = $0 }
        )
    }

    private func controlPadPosition(size: CGSize,
                                    xValue: Double,
                                    yValue: Double,
                                    xRange: ClosedRange<Double>,
                                    yRange: ClosedRange<Double>) -> CGPoint {
        let clampedX = min(max(xValue, xRange.lowerBound), xRange.upperBound)
        let clampedY = min(max(yValue, yRange.lowerBound), yRange.upperBound)
        let normalizedX = (clampedX - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)
        let normalizedY = (clampedY - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
        let x = normalizedX * size.width
        let y = (1 - normalizedY) * size.height
        return CGPoint(x: x, y: y)
    }

    private func controlPadGrid(size: CGSize) -> Path {
        Path { path in
            let columns = 4
            let rows = 4
            let xStep = size.width / CGFloat(columns)
            let yStep = size.height / CGFloat(rows)

            for index in 1..<columns {
                let x = CGFloat(index) * xStep
                path.move(to: CGPoint(x: x, y: 8))
                path.addLine(to: CGPoint(x: x, y: size.height - 8))
            }

            for index in 1..<rows {
                let y = CGFloat(index) * yStep
                path.move(to: CGPoint(x: 8, y: y))
                path.addLine(to: CGPoint(x: size.width - 8, y: y))
            }
        }
    }

    private func controlPadZeroLine(size: CGSize, yRange: ClosedRange<Double>) -> CGFloat {
        let normalized = (0 - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
        return (1 - normalized) * size.height
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.0f", value)
        }
        if abs(value) >= 100 {
            return String(format: "%.1f", value)
        }
        if abs(value) >= 10 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }
}

// MARK: - Audio Processor

final class AuroraAudioProcessor: NSObject, ObservableObject {
    private enum EchoDefaults {
        static let inputGain: Float = 8.0
        static let inputCurve: Float = 0.7
        static let inputFloor: Float = 0.08
        static let gateThreshold: Float = 0.1
        static let gateAttack: Float = 0.75
        static let gateRelease: Float = 0.8
        static let masterOutput: Float = 1.0
        static let wetOnly: Bool = false
        static let wetMixBase: Float = 85
        static let wetMixRange: Float = 15
        static let delayTime: Double = 0.7
        static let feedback: Float = 18
        static let lowPassCutoff: Float = 9000
        static let boostDb: Float = 18
        static let duckingStrength: Float = 0.65
        static let duckingResponse: Float = 0.22
        static let duckingLevelScale: Float = 0.8
        static let duckingDelay: Double = 0.12
        static let triggerRise: Float = 0.02
        static let retriggerInterval: Double = 1.0
        static let holdDuration: Double = 0.55
    }

    private enum EchoSettingKey: String {
        case inputGain = "voiceAurora.echo.inputGain"
        case inputCurve = "voiceAurora.echo.inputCurve"
        case inputFloor = "voiceAurora.echo.inputFloor"
        case gateThreshold = "voiceAurora.echo.gateThreshold"
        case gateAttack = "voiceAurora.echo.gateAttack"
        case gateRelease = "voiceAurora.echo.gateRelease"
        case masterOutput = "voiceAurora.echo.masterOutput"
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

    private var isRestoringSettings = false

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

    private let directionConfidenceThreshold: Float = 0.06
    private let sourceSmoothing: CGFloat = 0.15
    private var duckingLevel: Float = 1.0
    private var lastCurvedLevel: Float = 0
    private var lastEchoTriggerTime: Double = 0

    override init() {
        super.init()
        restoreSettings()
    }

    func resetEchoDefaults() {
        echoInputGain = EchoDefaults.inputGain
        echoInputCurve = EchoDefaults.inputCurve
        echoInputFloor = EchoDefaults.inputFloor
        echoGateThreshold = EchoDefaults.gateThreshold
        echoGateAttack = EchoDefaults.gateAttack
        echoGateRelease = EchoDefaults.gateRelease
        echoMasterOutput = EchoDefaults.masterOutput
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
    }

    private func restoreSettings() {
        isRestoringSettings = true
        echoInputGain = loadFloat(.inputGain, fallback: EchoDefaults.inputGain)
        echoInputCurve = loadFloat(.inputCurve, fallback: EchoDefaults.inputCurve)
        echoInputFloor = loadFloat(.inputFloor, fallback: EchoDefaults.inputFloor)
        echoGateThreshold = loadFloat(.gateThreshold, fallback: EchoDefaults.gateThreshold)
        echoGateAttack = loadFloat(.gateAttack, fallback: EchoDefaults.gateAttack)
        echoGateRelease = loadFloat(.gateRelease, fallback: EchoDefaults.gateRelease)
        echoMasterOutput = loadFloat(.masterOutput, fallback: EchoDefaults.masterOutput)
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
        isRestoringSettings = false
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

    private func loadFloat(_ key: EchoSettingKey, fallback: Float) -> Float {
        guard let number = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber else {
            return fallback
        }
        return number.floatValue
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
            sessionCapture.startRunning()

            captureSession = sessionCapture
            captureInput = input
            captureOutput = output
            isListening = true

            applyPlaybackOverrides()
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
        let canPlayback = ensurePlaybackEngine(sampleRate: sampleRate)
        let frameCount = AVAudioFrameCount(frames)
        var playbackBuffer: AVAudioPCMBuffer?
        var playbackData: UnsafeMutablePointer<Float>?
        if canPlayback, let playbackFormat = playbackFormat,
           let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount),
           let data = buffer.floatChannelData?.pointee {
            playbackBuffer = buffer
            playbackData = data
        }

        var sumW2: Float = 0
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

            if let playbackData = playbackData {
                playbackData[i] = w
            }

            sumW2 += w * w
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

        if let playbackBuffer = playbackBuffer {
            playbackBuffer.frameLength = frameCount
            enqueuePlayback(playbackBuffer)
        }

        let rms = sqrt(sumW2 / Float(frames))
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
        let gateAttack = echoGateAttack.clamped(to: 0.0...0.99)
        let gateRelease = echoGateRelease.clamped(to: 0.0...0.99)
        let triggerRise = max(0, echoTriggerRise)
        let retriggerInterval = max(0, echoRetriggerInterval)
        let holdDuration = max(0, echoHoldDuration)
        let levelRise = curvedLevel - lastCurvedLevel
        let canTrigger = now - lastEchoTriggerTime > retriggerInterval
        let triggerEcho = curvedLevel > gateThreshold && levelRise > triggerRise && canTrigger
        if triggerEcho {
            lastEchoTriggerTime = now
        }

        let holdActive = now - lastEchoTriggerTime < holdDuration
        let targetEcho: Float = holdActive ? 1.0 : 0.0
        if targetEcho > echoMix {
            echoMix = echoMix * (1 - gateAttack) + targetEcho * gateAttack
        } else {
            echoMix = echoMix * gateRelease + targetEcho * (1 - gateRelease)
        }

        let duckingDelayValue = max(0, duckingDelay)
        let duckingStrengthValue = duckingStrength.clamped(to: 0.0...1.0)
        let duckingResponseValue = duckingResponse.clamped(to: 0.0...1.0)
        let duckingLevelScaleValue = max(0, duckingLevelScale)
        let bypassDucking = now - lastEchoTriggerTime < duckingDelayValue
        let duckingTarget = bypassDucking ? 1.0 : (1.0 - min(duckingStrengthValue, curvedLevel * duckingLevelScaleValue))
        duckingLevel = duckingLevel * (1 - duckingResponseValue) + duckingTarget * duckingResponseValue

        let duckedMix = echoMix * duckingLevel

        let outputLevel = echoMasterOutput.clamped(to: 0.0...1.0)
        gateMixer?.outputVolume = duckedMix * outputLevel
        delayNode?.delayTime = echoDelayTime.clamped(to: 0.0...2.0)
        delayNode?.feedback = echoFeedback.clamped(to: -100.0...100.0)
        delayNode?.lowPassCutoff = echoLowPassCutoff.clamped(to: 10.0...20_000.0)
        let wetBase = echoWetMixBase.clamped(to: 0.0...100.0)
        let wetRange = echoWetMixRange.clamped(to: 0.0...100.0)
        let wetMixValue = wetBase + wetRange * echoMix
        let wetMix = echoWetOnly ? 100 : min(100, max(0, wetMixValue))
        delayNode?.wetDryMix = wetMix
        boostNode?.globalGain = echoBoostDb.clamped(to: -96.0...24.0)

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
