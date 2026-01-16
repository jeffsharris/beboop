import SwiftUI
import AVFoundation

struct HighContrastMobileView: View {
    private struct ShapeState: Identifiable {
        enum Kind: CaseIterable {
            case circle
            case roundedRect
            case capsule
            case blob

            // Each shape has its own musical note (MIDI note number)
            var midiNote: UInt8 {
                switch self {
                case .circle: return 72      // C5
                case .roundedRect: return 76 // E5
                case .capsule: return 79     // G5
                case .blob: return 84        // C6
                }
            }
        }

        let id = UUID()
        let kind: Kind
        var position: CGPoint      // Current position (absolute pixels)
        var velocity: CGPoint      // Velocity (pixels per second)
        let baseSize: CGSize       // Base size (normalized 0-1)
        let rotation: Angle
    }

    // User-controlled parameters
    @State private var speedMultiplier: CGFloat = 1.0
    @State private var sizeMultiplier: CGFloat = 1.0
    @State private var baselineSpeedMultiplier: CGFloat = 1.0

    // Gesture tracking
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var draggedShapeIndex: Int? = nil
    @State private var lastDragPosition: CGPoint = .zero
    @State private var lastDragTime: Date = Date()

    // Animation state
    @State private var shapes: [ShapeState] = []
    @State private var lastUpdateTime: Date = Date()
    @State private var screenSize: CGSize = .zero

    // Audio
    @StateObject private var chimePlayer = ChimePlayer()

    // Speed and size limits
    private let minSpeed: CGFloat = 0.2
    private let maxSpeed: CGFloat = 3.0
    private let minSize: CGFloat = 0.5
    private let maxSize: CGFloat = 2.0
    private let minBaselineSpeed: CGFloat = 0.2
    private let maxBaselineSpeed: CGFloat = 2.5

    // Physics
    private let damping: CGFloat = 0.985
    private let maxVelocity: CGFloat = 900  // Cap velocity to keep things playable
    private let collisionRestitution: CGFloat = 0.9
    private let collisionCooldown: TimeInterval = 0.12

    // Initial shape configurations
    private let initialConfigs: [(ShapeState.Kind, CGPoint, CGSize, CGFloat, Angle)] = [
        (.circle, CGPoint(x: 0.15, y: 0.2), CGSize(width: 0.22, height: 0.22), 80, .degrees(0)),
        (.roundedRect, CGPoint(x: 0.6, y: 0.4), CGSize(width: 0.26, height: 0.18), 65, .degrees(15)),
        (.capsule, CGPoint(x: 0.3, y: 0.7), CGSize(width: 0.28, height: 0.15), 70, .degrees(-10)),
        (.blob, CGPoint(x: 0.75, y: 0.25), CGSize(width: 0.24, height: 0.2), 55, .degrees(8)),
        (.circle, CGPoint(x: 0.5, y: 0.85), CGSize(width: 0.2, height: 0.2), 90, .degrees(0))
    ]

    @State private var lastCollisionTimes: [String: Date] = [:]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GeometryReader { geometry in
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        updatePhysics(at: timeline.date, screenSize: size)

                        for shape in shapes {
                            draw(shape: shape, in: size, context: &context)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear {
                    screenSize = geometry.size
                    initializeShapes(in: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    screenSize = newSize
                }
                .gesture(combinedGesture)
            }

            // Speed/size indicator overlay
            if isDragging && draggedShapeIndex == nil {
                controlIndicator
            }
        }
    }

    // MARK: - Gestures

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let location = value.location

        // Check if we're starting a new drag
        if !isDragging {
            isDragging = true
            dragStart = value.startLocation

            // Check if we hit a shape
            draggedShapeIndex = hitTest(at: value.startLocation)
            lastDragPosition = location
            lastDragTime = Date()
        }

        if let shapeIndex = draggedShapeIndex {
            // Move the shape with the finger
            shapes[shapeIndex].position = location
            lastDragPosition = location
            lastDragTime = Date()
        } else {
            // Control speed/size
            let delta = CGPoint(
                x: location.x - dragStart.x,
                y: location.y - dragStart.y
            )

            // Vertical drag controls baseline speed
            let speedDelta = -delta.y / 200.0
            baselineSpeedMultiplier = min(maxBaselineSpeed, max(minBaselineSpeed, 1.0 + speedDelta))
            speedMultiplier = baselineSpeedMultiplier

            // Horizontal drag controls size
            let sizeDelta = delta.x / 200.0
            sizeMultiplier = min(maxSize, max(minSize, 1.0 + sizeDelta))
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if let shapeIndex = draggedShapeIndex {
            // Calculate fling velocity from recent movement
            let dt = Date().timeIntervalSince(lastDragTime)
            if dt > 0 && dt < 0.3 {
                let dx = value.location.x - lastDragPosition.x
                let dy = value.location.y - lastDragPosition.y

                // Scale velocity based on recent movement
                let flingMultiplier: CGFloat = 6.0
                var newVelocity = CGPoint(
                    x: dx / dt * flingMultiplier,
                    y: dy / dt * flingMultiplier
                )

                // Cap velocity
                let speed = sqrt(newVelocity.x * newVelocity.x + newVelocity.y * newVelocity.y)
                if speed > maxVelocity {
                    let scale = maxVelocity / speed
                    newVelocity.x *= scale
                    newVelocity.y *= scale
                }

                let adjustedSpeed = sqrt(newVelocity.x * newVelocity.x + newVelocity.y * newVelocity.y)
                if adjustedSpeed < baselineSpeed {
                    let scale = baselineSpeed / max(adjustedSpeed, 0.01)
                    newVelocity.x *= scale
                    newVelocity.y *= scale
                }
                shapes[shapeIndex].velocity = newVelocity
            }
        }

        isDragging = false
        draggedShapeIndex = nil
    }

    private func hitTest(at point: CGPoint) -> Int? {
        let minDim = min(screenSize.width, screenSize.height)

        for (index, shape) in shapes.enumerated().reversed() {
            let width = minDim * shape.baseSize.width * sizeMultiplier
            let height = minDim * shape.baseSize.height * sizeMultiplier

            let shapeRect = CGRect(
                x: shape.position.x - width / 2,
                y: shape.position.y - height / 2,
                width: width,
                height: height
            )

            if shapeRect.contains(point) {
                return index
            }
        }
        return nil
    }

    private var controlIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Label {
                    Text(String(format: "%.1fx", baselineSpeedMultiplier))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "speedometer")
                }

                Label {
                    Text(String(format: "%.1fx", sizeMultiplier))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.black.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.easeOut(duration: 0.2), value: isDragging)
    }

    // MARK: - Physics

    private func initializeShapes(in size: CGSize) {
        shapes = initialConfigs.map { config in
            let (kind, startNorm, baseSize, speed, rotation) = config
            // Randomize initial velocity direction
            let angle = Double.random(in: 0..<(2 * .pi))
            let baselineSpeed = speed * baselineSpeedMultiplier
            let velocity = CGPoint(
                x: cos(angle) * baselineSpeed,
                y: sin(angle) * baselineSpeed
            )
            return ShapeState(
                kind: kind,
                position: CGPoint(x: startNorm.x * size.width, y: startNorm.y * size.height),
                velocity: velocity,
                baseSize: baseSize,
                rotation: rotation
            )
        }
        lastUpdateTime = Date()
    }

    private func updatePhysics(at date: Date, screenSize: CGSize) {
        let dt = date.timeIntervalSince(lastUpdateTime)
        guard dt > 0, dt < 0.5 else {
            lastUpdateTime = date
            return
        }

        resolveShapeCollisions()

        for i in shapes.indices {
            // Skip shape being dragged
            if draggedShapeIndex == i { continue }

            var shape = shapes[i]

            // Apply damping and ease back toward baseline speed
            shape.velocity.x *= damping
            shape.velocity.y *= damping

            let currentSpeed = sqrt(shape.velocity.x * shape.velocity.x + shape.velocity.y * shape.velocity.y)
            if currentSpeed < baselineSpeed {
                let target = baselineSpeed
                if currentSpeed > 0.01 {
                    let scale = target / currentSpeed
                    shape.velocity.x *= scale
                    shape.velocity.y *= scale
                } else {
                    let angle = Double.random(in: 0..<(2 * .pi))
                    shape.velocity.x = cos(angle) * target
                    shape.velocity.y = sin(angle) * target
                }
            }

            // Calculate effective size for collision
            let minDim = min(screenSize.width, screenSize.height)
            let width = minDim * shape.baseSize.width * sizeMultiplier
            let height = minDim * shape.baseSize.height * sizeMultiplier
            let halfW = width / 2
            let halfH = height / 2

            // Update position with speed multiplier
            shape.position.x += shape.velocity.x * dt * speedMultiplier
            shape.position.y += shape.velocity.y * dt * speedMultiplier

            // Bounce off left/right edges
            if shape.position.x - halfW < 0 {
                shape.position.x = halfW
                if shape.velocity.x < 0 {
                    shape.velocity.x = -shape.velocity.x * collisionRestitution
                    playBounceChime(for: shape.kind, velocity: abs(shape.velocity.x))
                }
            } else if shape.position.x + halfW > screenSize.width {
                shape.position.x = screenSize.width - halfW
                if shape.velocity.x > 0 {
                    shape.velocity.x = -shape.velocity.x * collisionRestitution
                    playBounceChime(for: shape.kind, velocity: abs(shape.velocity.x))
                }
            }

            // Bounce off top/bottom edges
            if shape.position.y - halfH < 0 {
                shape.position.y = halfH
                if shape.velocity.y < 0 {
                    shape.velocity.y = -shape.velocity.y * collisionRestitution
                    playBounceChime(for: shape.kind, velocity: abs(shape.velocity.y))
                }
            } else if shape.position.y + halfH > screenSize.height {
                shape.position.y = screenSize.height - halfH
                if shape.velocity.y > 0 {
                    shape.velocity.y = -shape.velocity.y * collisionRestitution
                    playBounceChime(for: shape.kind, velocity: abs(shape.velocity.y))
                }
            }

            shapes[i] = shape
        }

        lastUpdateTime = date
    }

    private var baselineSpeed: CGFloat {
        baselineSpeedMultiplier * 80
    }

    private func resolveShapeCollisions() {
        guard shapes.count > 1 else { return }

        let now = Date()
        for i in 0..<(shapes.count - 1) {
            for j in (i + 1)..<shapes.count {
                let a = shapes[i]
                let b = shapes[j]
                let minDim = min(screenSize.width, screenSize.height)
                let aRadius = minDim * max(a.baseSize.width, a.baseSize.height) * sizeMultiplier * 0.5
                let bRadius = minDim * max(b.baseSize.width, b.baseSize.height) * sizeMultiplier * 0.5

                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let distance = sqrt(dx * dx + dy * dy)
                let minDistance = aRadius + bRadius

                guard distance > 0, distance < minDistance else { continue }

                let key = "\(min(a.id.uuidString, b.id.uuidString))-\(max(a.id.uuidString, b.id.uuidString))"
                if let last = lastCollisionTimes[key], now.timeIntervalSince(last) < collisionCooldown {
                    continue
                }
                lastCollisionTimes[key] = now

                let nx = dx / distance
                let ny = dy / distance

                var va = a.velocity
                var vb = b.velocity

                let relativeVelocity = (vb.x - va.x) * nx + (vb.y - va.y) * ny
                if relativeVelocity > 0 {
                    continue
                }

                let impulse = -(1 + collisionRestitution) * relativeVelocity / 2
                let impulseX = impulse * nx
                let impulseY = impulse * ny

                va.x -= impulseX
                va.y -= impulseY
                vb.x += impulseX
                vb.y += impulseY

                let overlap = minDistance - distance
                let separation = overlap / 2
                let newAPosition = CGPoint(
                    x: a.position.x - nx * separation,
                    y: a.position.y - ny * separation
                )
                let newBPosition = CGPoint(
                    x: b.position.x + nx * separation,
                    y: b.position.y + ny * separation
                )

                shapes[i].position = newAPosition
                shapes[i].velocity = va
                shapes[j].position = newBPosition
                shapes[j].velocity = vb

                playBounceChime(for: a.kind, velocity: abs(relativeVelocity) * 0.5)
                playBounceChime(for: b.kind, velocity: abs(relativeVelocity) * 0.5)
            }
        }
    }

    private func playBounceChime(for kind: ShapeState.Kind, velocity: CGFloat) {
        // Only play if moving fast enough
        guard velocity > 20 else { return }

        // Volume based on velocity
        let volume = min(1.0, Float(velocity) / 300.0)
        chimePlayer.playChime(note: kind.midiNote, volume: volume)
    }

    // MARK: - Drawing

    private func draw(shape: ShapeState, in size: CGSize, context: inout GraphicsContext) {
        let minDimension = min(size.width, size.height)
        let width = minDimension * shape.baseSize.width * sizeMultiplier
        let height = minDimension * shape.baseSize.height * sizeMultiplier

        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let path = path(for: shape.kind, in: rect)

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: shape.position.x, y: shape.position.y)
        transform = transform.rotated(by: CGFloat(shape.rotation.radians))

        let transformedPath = path.applying(transform)
        context.fill(transformedPath, with: .color(.black))
    }

    private func path(for kind: ShapeState.Kind, in rect: CGRect) -> Path {
        switch kind {
        case .circle:
            return Path(ellipseIn: rect)
        case .roundedRect:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.25)
        case .capsule:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.5)
        case .blob:
            return blobPath(in: rect)
        }
    }

    private func blobPath(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y))
        path.addCurve(
            to: CGPoint(x: x + w, y: y + h * 0.4),
            control1: CGPoint(x: x + w * 0.78, y: y + h * 0.02),
            control2: CGPoint(x: x + w, y: y + h * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.72, y: y + h),
            control1: CGPoint(x: x + w, y: y + h * 0.75),
            control2: CGPoint(x: x + w * 0.9, y: y + h)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.2, y: y + h * 0.88),
            control1: CGPoint(x: x + w * 0.48, y: y + h),
            control2: CGPoint(x: x + w * 0.3, y: y + h * 1.05)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.1, y: y + h * 0.35),
            control1: CGPoint(x: x + w * 0.1, y: y + h * 0.8),
            control2: CGPoint(x: x, y: y + h * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Chime Player

@MainActor
final class ChimePlayer: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var sampler: AVAudioUnitSampler?
    private var isSetup = false

    init() {
        setupAudio()
    }

    private func setupAudio() {
        do {
            let engine = AVAudioEngine()
            let sampler = AVAudioUnitSampler()

            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)

            // Use default General MIDI sounds (instrument 14 is tubular bells)
            sampler.sendProgramChange(14, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                       bankLSB: UInt8(kAUSampler_DefaultBankLSB), onChannel: 0)

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.sampler = sampler
            self.isSetup = true
        } catch {
            print("Chime audio setup failed: \(error)")
        }
    }

    func playChime(note: UInt8, volume: Float) {
        guard isSetup, let sampler = sampler else { return }

        let velocity = UInt8(min(127, max(30, volume * 100)))
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)

        // Stop note after short duration for bell-like decay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak sampler] in
            sampler?.stopNote(note, onChannel: 0)
        }
    }
}

#Preview {
    HighContrastMobileView()
}
