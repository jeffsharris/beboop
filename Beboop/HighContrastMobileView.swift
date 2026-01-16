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
    @State private var sizeMultiplier: CGFloat = 1.0
    @State private var baselineSpeedMultiplier: CGFloat = 1.0

    // Gesture tracking
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var draggedShapeIndex: Int? = nil
    @State private var lastDragPosition: CGPoint = .zero
    @State private var lastDragTime: Date = .distantPast
    @State private var dragVelocity: CGPoint = .zero

    // Animation state
    @State private var shapes: [ShapeState] = []
    @State private var lastUpdateTime: Date = Date()
    @State private var screenSize: CGSize = .zero

    // Audio
    @StateObject private var chimePlayer = ChimePlayer()

    // Speed and size limits
    private let minSize: CGFloat = 0.5
    private let maxSize: CGFloat = 2.0
    private let minBaselineSpeed: CGFloat = 0.0
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
                        for shape in shapes {
                            draw(shape: shape, in: size, context: &context)
                        }
                    }
                    .onChange(of: timeline.date) { _, newDate in
                        updatePhysics(at: newDate)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear {
                    screenSize = geometry.size
                    initializeShapesIfNeeded(in: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    let oldSize = screenSize
                    screenSize = newSize
                    updateShapesForResize(from: oldSize, to: newSize)
                    initializeShapesIfNeeded(in: newSize)
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
            lastDragTime = value.time
        }

        if let shapeIndex = draggedShapeIndex {
            let dt = value.time.timeIntervalSince(lastDragTime)
            if dt > 0 {
                let dx = location.x - lastDragPosition.x
                let dy = location.y - lastDragPosition.y
                dragVelocity = CGPoint(x: dx / dt, y: dy / dt)
            }

            // Move the shape with the finger
            shapes[shapeIndex].position = clampedPosition(
                for: shapes[shapeIndex],
                proposed: location,
                in: screenSize
            )
            resolveCollisions(iterations: 1)
            lastDragPosition = location
            lastDragTime = value.time
        } else {
            // Control speed/size
            let delta = CGPoint(
                x: location.x - dragStart.x,
                y: location.y - dragStart.y
            )

            // Vertical drag controls baseline speed
            let speedDelta = -delta.y / 200.0
            baselineSpeedMultiplier = min(maxBaselineSpeed, max(minBaselineSpeed, 1.0 + speedDelta))

            // Horizontal drag controls size
            let sizeDelta = delta.x / 200.0
            sizeMultiplier = min(maxSize, max(minSize, 1.0 + sizeDelta))
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if let shapeIndex = draggedShapeIndex {
            var newVelocity = CGPoint(x: dragVelocity.x, y: dragVelocity.y)
            let flingBoost: CGFloat = 1.5
            newVelocity.x *= flingBoost
            newVelocity.y *= flingBoost

            clampVelocity(&newVelocity)
            newVelocity = enforceBaselineVelocity(newVelocity)
            shapes[shapeIndex].velocity = newVelocity
        }

        isDragging = false
        draggedShapeIndex = nil
        dragVelocity = .zero
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

    private func initializeShapesIfNeeded(in size: CGSize) {
        guard shapes.isEmpty, size.width > 1, size.height > 1 else { return }

        initializeShapes(in: size)
    }

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

    private func updateShapesForResize(from oldSize: CGSize, to newSize: CGSize) {
        guard oldSize.width > 1, oldSize.height > 1 else { return }
        guard newSize.width > 1, newSize.height > 1 else { return }

        let scaleX = newSize.width / oldSize.width
        let scaleY = newSize.height / oldSize.height

        for index in shapes.indices {
            let scaled = CGPoint(
                x: shapes[index].position.x * scaleX,
                y: shapes[index].position.y * scaleY
            )
            shapes[index].position = clampedPosition(for: shapes[index], proposed: scaled, in: newSize)
        }
    }

    private func updatePhysics(at date: Date) {
        let dt = date.timeIntervalSince(lastUpdateTime)
        guard dt > 0, dt < 0.5 else {
            lastUpdateTime = date
            return
        }
        guard screenSize.width > 1, screenSize.height > 1 else {
            lastUpdateTime = date
            return
        }
        if shapes.isEmpty {
            initializeShapesIfNeeded(in: screenSize)
            lastUpdateTime = date
            return
        }

        for i in shapes.indices {
            // Skip shape being dragged
            if draggedShapeIndex == i { continue }

            var shape = shapes[i]

            // Apply damping and ease back toward baseline speed
            shape.velocity.x *= damping
            shape.velocity.y *= damping
            clampVelocity(&shape.velocity)

            // Update position
            shape.position.x += shape.velocity.x * dt
            shape.position.y += shape.velocity.y * dt

            shapes[i] = shape
        }

        resolveCollisions(iterations: 2)
        enforceBaselineSpeeds()

        lastUpdateTime = date
    }

    private var baselineSpeed: CGFloat {
        baselineSpeedMultiplier * 80
    }

    private func resolveCollisions(iterations: Int) {
        for _ in 0..<iterations {
            resolveWallCollisions()
            if shapes.count > 1 {
                resolveShapeCollisions()
            }
        }
    }

    private func resolveWallCollisions() {
        for index in shapes.indices {
            let isDragged = draggedShapeIndex == index
            var shape = shapes[index]
            let halfSize = halfSize(for: shape)
            var velocity = isDragged ? dragVelocity : shape.velocity
            var didHitWall = false

            if shape.position.x - halfSize.width < 0 {
                shape.position.x = halfSize.width
                if velocity.x < 0 {
                    velocity.x = isDragged ? 0 : -velocity.x * collisionRestitution
                    didHitWall = true
                }
            } else if shape.position.x + halfSize.width > screenSize.width {
                shape.position.x = screenSize.width - halfSize.width
                if velocity.x > 0 {
                    velocity.x = isDragged ? 0 : -velocity.x * collisionRestitution
                    didHitWall = true
                }
            }

            if shape.position.y - halfSize.height < 0 {
                shape.position.y = halfSize.height
                if velocity.y < 0 {
                    velocity.y = isDragged ? 0 : -velocity.y * collisionRestitution
                    didHitWall = true
                }
            } else if shape.position.y + halfSize.height > screenSize.height {
                shape.position.y = screenSize.height - halfSize.height
                if velocity.y > 0 {
                    velocity.y = isDragged ? 0 : -velocity.y * collisionRestitution
                    didHitWall = true
                }
            }

            if didHitWall {
                let impactSpeed = max(abs(velocity.x), abs(velocity.y))
                playBounceChime(for: shape.kind, velocity: impactSpeed)
            }

            if isDragged {
                dragVelocity = velocity
            } else {
                shape.velocity = velocity
            }
            shapes[index] = shape
        }
    }

    private func resolveShapeCollisions() {
        guard shapes.count > 1 else { return }

        let now = Date()
        for i in 0..<(shapes.count - 1) {
            for j in (i + 1)..<shapes.count {
                let a = shapes[i]
                let b = shapes[j]
                let aRadius = collisionRadius(for: a)
                let bRadius = collisionRadius(for: b)

                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let distance = sqrt(dx * dx + dy * dy)
                let minDistance = aRadius + bRadius

                guard distance < minDistance else { continue }

                let key = "\(min(a.id.uuidString, b.id.uuidString))-\(max(a.id.uuidString, b.id.uuidString))"
                let shouldPlay: Bool
                if let last = lastCollisionTimes[key] {
                    shouldPlay = now.timeIntervalSince(last) >= collisionCooldown
                } else {
                    shouldPlay = true
                }
                if shouldPlay {
                    lastCollisionTimes[key] = now
                }

                let nx: CGFloat
                let ny: CGFloat
                if distance > 0.001 {
                    nx = dx / distance
                    ny = dy / distance
                } else {
                    let angle = Double.random(in: 0..<(2 * .pi))
                    nx = CGFloat(cos(angle))
                    ny = CGFloat(sin(angle))
                }

                let isDraggedA = draggedShapeIndex == i
                let isDraggedB = draggedShapeIndex == j

                let massA = max(1, aRadius * aRadius)
                let massB = max(1, bRadius * bRadius)
                let invMassA: CGFloat = isDraggedA ? 0 : 1 / massA
                let invMassB: CGFloat = isDraggedB ? 0 : 1 / massB
                let totalInvMass = invMassA + invMassB
                if totalInvMass == 0 { continue }

                var va = isDraggedA ? dragVelocity : a.velocity
                var vb = isDraggedB ? dragVelocity : b.velocity

                let relativeVelocity = (vb.x - va.x) * nx + (vb.y - va.y) * ny
                let overlap = minDistance - max(distance, 0.001)
                let correctionPercent: CGFloat = 0.8
                let correctionSlop: CGFloat = 0.5
                let correctionMagnitude = max(overlap - correctionSlop, 0) / totalInvMass * correctionPercent
                let correctionX = correctionMagnitude * nx
                let correctionY = correctionMagnitude * ny

                var newAPosition = a.position
                var newBPosition = b.position

                if invMassA > 0 {
                    newAPosition.x -= correctionX * invMassA
                    newAPosition.y -= correctionY * invMassA
                }
                if invMassB > 0 {
                    newBPosition.x += correctionX * invMassB
                    newBPosition.y += correctionY * invMassB
                }

                let postDx = newBPosition.x - newAPosition.x
                let postDy = newBPosition.y - newAPosition.y
                let postDistance = sqrt(postDx * postDx + postDy * postDy)
                if (isDraggedA || isDraggedB), postDistance < minDistance {
                    let remaining = minDistance - postDistance
                    if isDraggedA {
                        newAPosition.x -= nx * remaining
                        newAPosition.y -= ny * remaining
                    } else {
                        newBPosition.x += nx * remaining
                        newBPosition.y += ny * remaining
                    }
                }

                if relativeVelocity < 0 {
                    let impulse = -(1 + collisionRestitution) * relativeVelocity / totalInvMass
                    let impulseX = impulse * nx
                    let impulseY = impulse * ny

                    if invMassA > 0 {
                        va.x -= impulseX * invMassA
                        va.y -= impulseY * invMassA
                    }
                    if invMassB > 0 {
                        vb.x += impulseX * invMassB
                        vb.y += impulseY * invMassB
                    }
                }

                shapes[i].position = newAPosition
                shapes[j].position = newBPosition
                if !isDraggedA {
                    shapes[i].velocity = va
                }
                if !isDraggedB {
                    shapes[j].velocity = vb
                }

                if shouldPlay {
                    let impactSpeed = abs(relativeVelocity)
                    playBounceChime(for: a.kind, velocity: impactSpeed)
                    playBounceChime(for: b.kind, velocity: impactSpeed)
                }
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

    private func enforceBaselineSpeeds() {
        guard baselineSpeed > 0 else { return }

        for index in shapes.indices {
            if draggedShapeIndex == index { continue }

            var shape = shapes[index]
            let adjusted = enforceBaselineVelocity(shape.velocity)
            shape.velocity = adjusted
            shapes[index] = shape
        }
    }

    private func enforceBaselineVelocity(_ velocity: CGPoint) -> CGPoint {
        guard baselineSpeed > 0 else { return velocity }

        let currentSpeed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if currentSpeed >= baselineSpeed {
            return velocity
        }

        if currentSpeed > 0.01 {
            let scale = baselineSpeed / currentSpeed
            return CGPoint(x: velocity.x * scale, y: velocity.y * scale)
        }

        let angle = Double.random(in: 0..<(2 * .pi))
        return CGPoint(x: cos(angle) * baselineSpeed, y: sin(angle) * baselineSpeed)
    }

    private func clampVelocity(_ velocity: inout CGPoint) {
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if speed > maxVelocity {
            let scale = maxVelocity / speed
            velocity.x *= scale
            velocity.y *= scale
        }
    }

    private func halfSize(for shape: ShapeState) -> CGSize {
        let minDim = min(screenSize.width, screenSize.height)
        let width = minDim * shape.baseSize.width * sizeMultiplier
        let height = minDim * shape.baseSize.height * sizeMultiplier
        return CGSize(width: width / 2, height: height / 2)
    }

    private func collisionRadius(for shape: ShapeState) -> CGFloat {
        let minDim = min(screenSize.width, screenSize.height)
        return minDim * max(shape.baseSize.width, shape.baseSize.height) * sizeMultiplier * 0.5
    }

    private func clampedPosition(for shape: ShapeState, proposed: CGPoint, in size: CGSize) -> CGPoint {
        let half = halfSize(for: shape)
        return CGPoint(
            x: min(max(proposed.x, half.width), size.width - half.width),
            y: min(max(proposed.y, half.height), size.height - half.height)
        )
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
