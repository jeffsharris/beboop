import SwiftUI
import AVFoundation
import UIKit
import CoreMotion

struct HighContrastMobileView: View {
    @EnvironmentObject private var audioCoordinator: AudioCoordinator
    private struct ShapeState: Identifiable {
        enum Kind: CaseIterable {
            case circle
            case roundedRect
            case capsule
            case blob
        }

        let id = UUID()
        let kind: Kind
        var position: CGPoint
        var velocity: CGPoint
        let baseSize: CGSize
        var sizeScale: CGFloat
        var baselineSpeed: CGFloat
        let rotation: Angle
        let color: Color
        let contour: [CGPoint]
    }

    // Gesture tracking
    @State private var draggedShapeIndex: Int? = nil
    @State private var lastDragPosition: CGPoint = .zero
    @State private var lastDragTime: Date = .distantPast
    @State private var dragVelocity: CGPoint = .zero
    @State private var isFrozen = false
    @State private var resizingShapeIndex: Int? = nil
    @State private var resizeStartScale: CGFloat = 1.0
    @State private var resizeStartPoint: CGPoint = .zero

    // Animation state
    @State private var shapes: [ShapeState] = []
    @State private var lastUpdateTime: Date = Date()
    @State private var screenSize: CGSize = .zero

    // Audio
    @StateObject private var chimePlayer = ChimePlayer()
    @StateObject private var motionController = MotionController()

    // Size and speed limits
    private let minShapeScale: CGFloat = 0.6
    private let maxShapeScale: CGFloat = 1.8
    private let minBaselineSpeed: CGFloat = 0.0
    private let maxBaselineSpeed: CGFloat = 240.0
    private let minBaseSize: CGFloat = 0.12
    private let maxBaseSize: CGFloat = 0.24
    private let initialShapeCount = 5
    private let contourPointCount = 48

    // Physics
    private let damping: CGFloat = 0.985
    private let maxVelocity: CGFloat = 900  // Cap velocity to keep things playable
    private let collisionRestitution: CGFloat = 0.9
    private let collisionCooldown: TimeInterval = 0.12
    private let inertialAccelerationScale: CGFloat = 5200
    private let inertialAccelerationThreshold: CGFloat = 0.01

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
                    motionController.start()
                    audioCoordinator.register(mode: .driftDoodles,
                                              start: {
                                                  chimePlayer.start()
                                              },
                                              stop: { completion in
                                                  chimePlayer.stop()
                                                  completion()
                                              })
                }
                .onChange(of: geometry.size) { _, newSize in
                    let oldSize = screenSize
                    screenSize = newSize
                    updateShapesForResize(from: oldSize, to: newSize)
                    initializeShapesIfNeeded(in: newSize)
                }
                .onDisappear {
                    motionController.stop()
                    audioCoordinator.unregister(mode: .driftDoodles)
                }
                .gesture(combinedGesture)
            }
            .overlay(
                FreezeTouchOverlay(
                    hitTestShape: { location in
                        hitTest(at: location)
                    },
                    onFreezeChanged: { isFrozen = $0
                        if !$0 { resizingShapeIndex = nil }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            .overlay(
                FrozenResizeOverlay(
                    isFrozen: { isFrozen },
                    hitTestShape: { location in
                        hitTest(at: location)
                    },
                    onResizeBegan: { index, start in
                        resizingShapeIndex = index
                        resizeStartScale = shapes[index].sizeScale
                        resizeStartPoint = start
                        draggedShapeIndex = nil
                        dragVelocity = .zero
                    },
                    onResizeChanged: { translation in
                        guard isFrozen, let index = resizingShapeIndex else { return }
                        let sizeDelta = -translation.y / 180.0
                        var shape = shapes[index]
                        shape.sizeScale = (resizeStartScale + sizeDelta).clamped(to: minShapeScale...maxShapeScale)
                        shape.position = clampedPosition(for: shape, proposed: shape.position, in: screenSize)
                        shapes[index] = shape
                    },
                    onResizeEnded: {
                        resizingShapeIndex = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
    }

    // MARK: - Gestures

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let location = value.location

        if isFrozen {
            if let shapeIndex = draggedShapeIndex {
                if resizingShapeIndex == nil {
                    resizingShapeIndex = shapeIndex
                    resizeStartScale = shapes[shapeIndex].sizeScale
                    resizeStartPoint = location
                }
                let sizeDelta = -(location.y - resizeStartPoint.y) / 180.0
                var shape = shapes[shapeIndex]
                shape.sizeScale = (resizeStartScale + sizeDelta).clamped(to: minShapeScale...maxShapeScale)
                shape.position = clampedPosition(for: shape, proposed: shape.position, in: screenSize)
                shapes[shapeIndex] = shape
                lastDragPosition = location
                lastDragTime = value.time
            }
            return
        }

        if draggedShapeIndex == nil {
            guard let hit = hitTest(at: value.startLocation) else { return }
            draggedShapeIndex = hit
            dragVelocity = .zero
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
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if isFrozen {
            resizingShapeIndex = nil
            draggedShapeIndex = nil
            dragVelocity = .zero
            return
        }

        if let shapeIndex = draggedShapeIndex {
            var newVelocity = CGPoint(x: dragVelocity.x, y: dragVelocity.y)
            let flingBoost: CGFloat = 1.5
            newVelocity.x *= flingBoost
            newVelocity.y *= flingBoost

            clampVelocity(&newVelocity)
            newVelocity = enforceBaselineVelocity(newVelocity, baselineSpeed: shapes[shapeIndex].baselineSpeed)
            shapes[shapeIndex].velocity = newVelocity
        }

        draggedShapeIndex = nil
        dragVelocity = .zero
        resizingShapeIndex = nil
    }

    // MARK: - Physics

    private func initializeShapesIfNeeded(in size: CGSize) {
        guard shapes.isEmpty, size.width > 1, size.height > 1 else { return }

        shapes = (0..<initialShapeCount).map { _ in
            makeRandomShape(in: size)
        }
        lastUpdateTime = Date()
    }

    private func makeRandomShape(in size: CGSize, position: CGPoint? = nil) -> ShapeState {
        let kind = ShapeState.Kind.allCases.randomElement() ?? .circle
        let baseSize = randomBaseSize(for: kind)
        let sizeScale = CGFloat.random(in: 0.75...1.25).clamped(to: minShapeScale...maxShapeScale)
        let baselineSpeed = CGFloat.random(in: 60...140).clamped(to: minBaselineSpeed...maxBaselineSpeed)
        let angle = Double.random(in: 0..<(2 * .pi))
        let velocity = CGPoint(
            x: cos(angle) * baselineSpeed,
            y: sin(angle) * baselineSpeed
        )
        let rotation = Angle.degrees(Double.random(in: -18...18))
        let color = Color.black
        let contour = contourPoints(for: kind, pointCount: contourPointCount)
        let initialPosition = position ?? randomPosition(for: baseSize, sizeScale: sizeScale, in: size)
        var shape = ShapeState(
            kind: kind,
            position: initialPosition,
            velocity: velocity,
            baseSize: baseSize,
            sizeScale: sizeScale,
            baselineSpeed: baselineSpeed,
            rotation: rotation,
            color: color,
            contour: contour
        )
        shape.position = clampedPosition(for: shape, proposed: shape.position, in: size)
        return shape
    }

    private func randomBaseSize(for kind: ShapeState.Kind) -> CGSize {
        let base = CGFloat.random(in: minBaseSize...maxBaseSize)
        switch kind {
        case .circle:
            return CGSize(width: base, height: base)
        case .roundedRect:
            let width = (base * CGFloat.random(in: 0.9...1.2)).clamped(to: minBaseSize...maxBaseSize)
            let height = (base * CGFloat.random(in: 0.9...1.2)).clamped(to: minBaseSize...maxBaseSize)
            return CGSize(width: width, height: height)
        case .capsule:
            let width = (base * CGFloat.random(in: 1.4...1.9)).clamped(to: minBaseSize...maxBaseSize)
            let height = (base * CGFloat.random(in: 0.6...0.85)).clamped(to: minBaseSize...maxBaseSize)
            return CGSize(width: width, height: height)
        case .blob:
            let width = (base * CGFloat.random(in: 0.9...1.3)).clamped(to: minBaseSize...maxBaseSize)
            let height = (base * CGFloat.random(in: 0.9...1.3)).clamped(to: minBaseSize...maxBaseSize)
            return CGSize(width: width, height: height)
        }
    }

    private func randomPosition(for baseSize: CGSize, sizeScale: CGFloat, in size: CGSize) -> CGPoint {
        let minDim = min(size.width, size.height)
        let width = minDim * baseSize.width * sizeScale
        let height = minDim * baseSize.height * sizeScale
        let insetX = min(width * 0.6, size.width * 0.45)
        let insetY = min(height * 0.6, size.height * 0.45)
        let x = CGFloat.random(in: insetX...(size.width - insetX))
        let y = CGFloat.random(in: insetY...(size.height - insetY))
        return CGPoint(x: x, y: y)
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

        if isFrozen {
            lastUpdateTime = date
            return
        }

        let orientation = currentInterfaceOrientation()
        var acceleration = accelerationVector(from: motionController.latestAcceleration, orientation: orientation)
        let magnitude = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y)
        if magnitude < inertialAccelerationThreshold {
            acceleration = .zero
        }
        let inertialForce = CGPoint(
            x: -acceleration.x * inertialAccelerationScale,
            y: -acceleration.y * inertialAccelerationScale
        )

        for i in shapes.indices {
            if draggedShapeIndex == i { continue }

            var shape = shapes[i]

            shape.velocity.x += inertialForce.x * CGFloat(dt)
            shape.velocity.y += inertialForce.y * CGFloat(dt)

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
            var velocity = isDragged ? dragVelocity : shape.velocity
            var didHitWall = false
            let bounds = polygonBounds(worldContour(for: shape))
            let wallBounds = CGRect(origin: .zero, size: screenSize)
            var impactSpeed: CGFloat = 0

            var offset = CGPoint.zero
            if bounds.minX < wallBounds.minX {
                offset.x = wallBounds.minX - bounds.minX
                let relative = velocity.x
                if relative < 0 {
                    velocity.x = isDragged ? 0 : -relative * collisionRestitution
                    didHitWall = true
                    impactSpeed = max(impactSpeed, abs(relative))
                }
            } else if bounds.maxX > wallBounds.maxX {
                offset.x = wallBounds.maxX - bounds.maxX
                let relative = velocity.x
                if relative > 0 {
                    velocity.x = isDragged ? 0 : -relative * collisionRestitution
                    didHitWall = true
                    impactSpeed = max(impactSpeed, abs(relative))
                }
            }

            if bounds.minY < wallBounds.minY {
                offset.y = wallBounds.minY - bounds.minY
                let relative = velocity.y
                if relative < 0 {
                    velocity.y = isDragged ? 0 : -relative * collisionRestitution
                    didHitWall = true
                    impactSpeed = max(impactSpeed, abs(relative))
                }
            } else if bounds.maxY > wallBounds.maxY {
                offset.y = wallBounds.maxY - bounds.maxY
                let relative = velocity.y
                if relative > 0 {
                    velocity.y = isDragged ? 0 : -relative * collisionRestitution
                    didHitWall = true
                    impactSpeed = max(impactSpeed, abs(relative))
                }
            }

            shape.position.x += offset.x
            shape.position.y += offset.y

            if didHitWall {
                playBounceChime(for: shape, velocity: impactSpeed)
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
        let now = Date()
        for i in 0..<(shapes.count - 1) {
            for j in (i + 1)..<shapes.count {
                let a = shapes[i]
                let b = shapes[j]
                let polyA = worldContour(for: a)
                let polyB = worldContour(for: b)

                guard let collision = satCollision(polyA: polyA, polyB: polyB) else { continue }

                var normal = collision.normal
                let centerDelta = CGPoint(x: b.position.x - a.position.x, y: b.position.y - a.position.y)
                if dot(centerDelta, normal) < 0 {
                    normal.x *= -1
                    normal.y *= -1
                }

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

                let isDraggedA = draggedShapeIndex == i
                let isDraggedB = draggedShapeIndex == j

                let massA = shapeArea(for: a)
                let massB = shapeArea(for: b)
                let invMassA: CGFloat = isDraggedA ? 0 : 1 / massA
                let invMassB: CGFloat = isDraggedB ? 0 : 1 / massB
                let totalInvMass = invMassA + invMassB
                if totalInvMass == 0 { continue }

                let correctionPercent: CGFloat = 0.9
                let correctionMagnitude = collision.overlap / totalInvMass * correctionPercent
                let correctionX = normal.x * correctionMagnitude
                let correctionY = normal.y * correctionMagnitude

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

                var va = isDraggedA ? dragVelocity : a.velocity
                var vb = isDraggedB ? dragVelocity : b.velocity

                let relativeVelocity = (vb.x - va.x) * normal.x + (vb.y - va.y) * normal.y
                if relativeVelocity < 0 {
                    let impulse = -(1 + collisionRestitution) * relativeVelocity / totalInvMass
                    let impulseX = impulse * normal.x
                    let impulseY = impulse * normal.y

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
                    clampVelocity(&va)
                    shapes[i].velocity = va
                }
                if !isDraggedB {
                    clampVelocity(&vb)
                    shapes[j].velocity = vb
                }

                if shouldPlay {
                    let impactSpeed = abs(relativeVelocity)
                    playBounceChime(for: a, velocity: impactSpeed)
                    playBounceChime(for: b, velocity: impactSpeed)
                }
            }
        }
    }

    private func playBounceChime(for shape: ShapeState, velocity: CGFloat) {
        guard velocity > 20 else { return }

        let normalized = min(1.0, velocity / 500.0)
        let shaped = pow(normalized, 1.3)
        let volume = Float(shaped)
        let note = midiNote(for: shape)
        chimePlayer.playChime(note: note, volume: volume)
    }

    private func enforceBaselineSpeeds() {
        for index in shapes.indices {
            if draggedShapeIndex == index { continue }

            var shape = shapes[index]
            let adjusted = enforceBaselineVelocity(shape.velocity, baselineSpeed: shape.baselineSpeed)
            shape.velocity = adjusted
            shapes[index] = shape
        }
    }

    private func enforceBaselineVelocity(_ velocity: CGPoint, baselineSpeed: CGFloat) -> CGPoint {
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

    private func accelerationVector(from acceleration: CMAcceleration,
                                    orientation: UIInterfaceOrientation) -> CGPoint {
        let x = CGFloat(acceleration.x)
        let y = CGFloat(acceleration.y)

        switch orientation {
        case .portrait:
            return CGPoint(x: x, y: -y)
        case .portraitUpsideDown:
            return CGPoint(x: -x, y: y)
        case .landscapeLeft:
            return CGPoint(x: y, y: x)
        case .landscapeRight:
            return CGPoint(x: -y, y: -x)
        default:
            return CGPoint(x: x, y: -y)
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if #available(iOS 26.0, *) {
                    return windowScene.effectiveGeometry.interfaceOrientation
                } else {
                    return windowScene.interfaceOrientation
                }
            }
        }
        return .portrait
    }

    private func shapeArea(for shape: ShapeState) -> CGFloat {
        let minDim = min(screenSize.width, screenSize.height)
        let width = minDim * shape.baseSize.width * shape.sizeScale
        let height = minDim * shape.baseSize.height * shape.sizeScale
        return max(1, width * height)
    }

    private func sizeMetric(for shape: ShapeState) -> CGFloat {
        let minDim = min(screenSize.width, screenSize.height)
        let width = minDim * shape.baseSize.width * shape.sizeScale
        let height = minDim * shape.baseSize.height * shape.sizeScale
        return max(width, height)
    }

    private func midiNote(for shape: ShapeState) -> UInt8 {
        let minDim = min(screenSize.width, screenSize.height)
        let minMetric = minDim * minBaseSize * minShapeScale
        let maxMetric = minDim * maxBaseSize * maxShapeScale
        let normalized = ((sizeMetric(for: shape) - minMetric) / max(maxMetric - minMetric, 1))
            .clamped(to: 0...1)
        let minNote: CGFloat = 60
        let maxNote: CGFloat = 86
        var note = maxNote - normalized * (maxNote - minNote)

        let offset: CGFloat
        switch shape.kind {
        case .circle:
            offset = 2
        case .roundedRect:
            offset = 0
        case .capsule:
            offset = -2
        case .blob:
            offset = 4
        }

        note = min(maxNote, max(minNote, note + offset))
        return UInt8(note.rounded())
    }

    private func contourPoints(for kind: ShapeState.Kind, pointCount: Int) -> [CGPoint] {
        let roundness: CGFloat
        switch kind {
        case .circle:
            roundness = 2.0
        case .roundedRect:
            roundness = CGFloat.random(in: 4.0...5.5)
        case .capsule:
            roundness = CGFloat.random(in: 6.0...7.5)
        case .blob:
            roundness = CGFloat.random(in: 2.4...3.2)
        }

        var points: [CGPoint] = []
        points.reserveCapacity(pointCount)

        for i in 0..<pointCount {
            let t = Double(i) / Double(pointCount) * 2 * Double.pi
            let cosT = cos(t)
            let sinT = sin(t)
            let x = signPreservingPower(cosT, exponent: 2 / roundness) * 0.5
            let y = signPreservingPower(sinT, exponent: 2 / roundness) * 0.5
            points.append(CGPoint(x: x, y: y))
        }

        return points
    }

    private func worldContour(for shape: ShapeState, position: CGPoint? = nil) -> [CGPoint] {
        let center = position ?? shape.position
        let minDim = min(screenSize.width, screenSize.height)
        let width = minDim * shape.baseSize.width * shape.sizeScale
        let height = minDim * shape.baseSize.height * shape.sizeScale
        let rotation = CGFloat(shape.rotation.radians)
        let cosR = cos(rotation)
        let sinR = sin(rotation)

        return shape.contour.map { point in
            let local = CGPoint(x: point.x * width, y: point.y * height)
            let rotated = CGPoint(
                x: local.x * cosR - local.y * sinR,
                y: local.x * sinR + local.y * cosR
            )
            return CGPoint(x: center.x + rotated.x, y: center.y + rotated.y)
        }
    }

    private func polygonBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func satCollision(polyA: [CGPoint], polyB: [CGPoint]) -> (normal: CGPoint, overlap: CGFloat)? {
        var smallestOverlap = CGFloat.greatestFiniteMagnitude
        var smallestAxis = CGPoint.zero

        let axes = polygonAxes(polyA) + polygonAxes(polyB)
        guard !axes.isEmpty else { return nil }
        for axis in axes {
            let projectionA = project(polyA, onto: axis)
            let projectionB = project(polyB, onto: axis)
            if projectionA.max < projectionB.min || projectionB.max < projectionA.min {
                return nil
            }
            let overlap = min(projectionA.max, projectionB.max) - max(projectionA.min, projectionB.min)
            if overlap < smallestOverlap {
                smallestOverlap = overlap
                smallestAxis = axis
            }
        }

        return (normal: smallestAxis, overlap: smallestOverlap)
    }

    private func polygonAxes(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        var axes: [CGPoint] = []
        axes.reserveCapacity(points.count)

        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let edge = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let normal = normalize(CGPoint(x: -edge.y, y: edge.x))
            if normal != .zero {
                axes.append(normal)
            }
        }

        return axes
    }

    private func project(_ points: [CGPoint], onto axis: CGPoint) -> (min: CGFloat, max: CGFloat) {
        guard let first = points.first else { return (0, 0) }
        var minValue = dot(first, axis)
        var maxValue = minValue

        for point in points.dropFirst() {
            let value = dot(point, axis)
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }

        return (minValue, maxValue)
    }

    private func normalize(_ vector: CGPoint) -> CGPoint {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y)
        guard length > 0.001 else { return .zero }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }

    private func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }

    private func signPreservingPower(_ value: Double, exponent: CGFloat) -> CGFloat {
        let sign: Double = value >= 0 ? 1 : -1
        let magnitude = pow(abs(value), Double(exponent))
        return CGFloat(sign * magnitude)
    }

    private func clampedPosition(for shape: ShapeState, proposed: CGPoint, in size: CGSize) -> CGPoint {
        let points = worldContour(for: shape, position: proposed)
        let bounds = polygonBounds(points)
        var clamped = proposed

        if bounds.minX < 0 {
            clamped.x += -bounds.minX
        } else if bounds.maxX > size.width {
            clamped.x -= bounds.maxX - size.width
        }

        if bounds.minY < 0 {
            clamped.y += -bounds.minY
        } else if bounds.maxY > size.height {
            clamped.y -= bounds.maxY - size.height
        }

        return clamped
    }

    private func hitTest(at point: CGPoint) -> Int? {
        for (index, shape) in shapes.enumerated().reversed() {
            let polygon = worldContour(for: shape)
            if pointInPolygon(point, polygon: polygon) {
                return index
            }
        }
        return nil
    }

    private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var contains = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y),
               point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + 0.0001) + pi.x {
                contains.toggle()
            }
            j = i
        }
        return contains
    }

    // MARK: - Drawing

    private func draw(shape: ShapeState, in size: CGSize, context: inout GraphicsContext) {
        let points = worldContour(for: shape)
        guard let first = points.first else { return }

        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        context.fill(path, with: .color(shape.color))
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

private struct FreezeTouchOverlay: UIViewRepresentable {
    var hitTestShape: (CGPoint) -> Int?
    var onFreezeChanged: (Bool) -> Void

    func makeUIView(context: Context) -> FreezeTouchView {
        let view = FreezeTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.hitTestShape = hitTestShape
        view.onFreezeChanged = onFreezeChanged
        return view
    }

    func updateUIView(_ uiView: FreezeTouchView, context: Context) {
        uiView.hitTestShape = hitTestShape
        uiView.onFreezeChanged = onFreezeChanged
    }
}

private final class FreezeTouchView: UIView {
    var hitTestShape: ((CGPoint) -> Int?)?
    var onFreezeChanged: ((Bool) -> Void)?
    private var activeTouchIDs = Set<ObjectIdentifier>()

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let hitTestShape else { return false }
        return hitTestShape(point) == nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = activeTouchIDs.isEmpty
        for touch in touches {
            activeTouchIDs.insert(ObjectIdentifier(touch))
        }
        if wasEmpty, !activeTouchIDs.isEmpty {
            onFreezeChanged?(true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            activeTouchIDs.remove(ObjectIdentifier(touch))
        }
        if activeTouchIDs.isEmpty {
            onFreezeChanged?(false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            activeTouchIDs.remove(ObjectIdentifier(touch))
        }
        if activeTouchIDs.isEmpty {
            onFreezeChanged?(false)
        }
    }
}

private struct FrozenResizeOverlay: UIViewRepresentable {
    var isFrozen: () -> Bool
    var hitTestShape: (CGPoint) -> Int?
    var onResizeBegan: (Int, CGPoint) -> Void
    var onResizeChanged: (CGPoint) -> Void
    var onResizeEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> FrozenResizeView {
        let view = FrozenResizeView()
        view.backgroundColor = .clear
        view.shouldReceiveTouch = { [weak coordinator = context.coordinator] point in
            coordinator?.shouldHandle(point: point) ?? false
        }

        let panGesture = UIPanGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)

        return view
    }

    func updateUIView(_ uiView: FrozenResizeView, context: Context) {
        uiView.shouldReceiveTouch = { [weak coordinator = context.coordinator] point in
            coordinator?.shouldHandle(point: point) ?? false
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let parent: FrozenResizeOverlay
        private var activeIndex: Int?

        init(_ parent: FrozenResizeOverlay) {
            self.parent = parent
        }

        func shouldHandle(point: CGPoint) -> Bool {
            guard parent.isFrozen() else { return false }
            return parent.hitTestShape(point) != nil
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)

            switch recognizer.state {
            case .began:
                guard parent.isFrozen(), let index = parent.hitTestShape(location) else { return }
                activeIndex = index
                parent.onResizeBegan(index, location)
            case .changed:
                guard activeIndex != nil else { return }
                let translation = recognizer.translation(in: view)
                parent.onResizeChanged(CGPoint(x: translation.x, y: translation.y))
            case .ended, .cancelled, .failed:
                if activeIndex != nil {
                    parent.onResizeEnded()
                }
                activeIndex = nil
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view else { return false }
            let location = gestureRecognizer.location(in: view)
            return shouldHandle(point: location)
        }
    }
}

private final class FrozenResizeView: UIView {
    var shouldReceiveTouch: ((CGPoint) -> Bool)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard shouldReceiveTouch?(point) == true else {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

@MainActor
final class MotionController: ObservableObject {
    private let motionManager = CMMotionManager()
    private(set) var latestAcceleration = CMAcceleration(x: 0, y: 0, z: 0)

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            self?.latestAcceleration = motion.userAcceleration
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - Chime Player

@MainActor
final class ChimePlayer: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var sampler: AVAudioUnitSampler?
    private var isSetup = false
    private var pendingStartWorkItem: DispatchWorkItem?

    func start(after delay: TimeInterval = 0) {
        pendingStartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.startNow()
        }
        pendingStartWorkItem = workItem

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    func stop() {
        pendingStartWorkItem?.cancel()
        pendingStartWorkItem = nil

        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine = nil
        sampler = nil
        isSetup = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Chime audio session deactivation failed: \(error)")
        }
    }

    private func startNow() {
        configureAudioSession()
        setupAudioIfNeeded()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Chime audio session setup failed: \(error)")
        }
    }

    private func setupAudioIfNeeded() {
        guard !isSetup || audioEngine?.isRunning != true else { return }

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
            isSetup = false
        }
    }

    func playChime(note: UInt8, volume: Float) {
        if !isSetup || audioEngine?.isRunning != true {
            startNow()
        }
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
        .environmentObject(AudioCoordinator())
}
