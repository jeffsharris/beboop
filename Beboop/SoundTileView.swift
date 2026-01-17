import SwiftUI
import AudioToolbox

struct SoundTileView: View {
    let index: Int
    let color: Color
    let hasRecording: Bool
    let isRecording: Bool
    let playbackSpeed: Float
    let playbackLevel: Float
    let waveformSamples: [Float]?
    @ObservedObject var audioManager: AudioManager
    @Binding var activeBackIndex: Int?

    /// Playback progress for this tile (0.0-1.0), observed directly from AudioManager
    private var playbackProgress: Double? {
        audioManager.playbackProgress[index]
    }
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onPlay: () -> Void
    let onStartLooping: () -> Void
    let onStopLooping: () -> Void
    let onClear: () -> Void
    let onShare: () -> Void
    let onSpeedChange: (Float) -> Void
    let onResetSpeed: () -> Void

    @State private var isPressed = false
    @State private var dragOffset: CGSize = .zero
    @State private var recordingPulse = false
    @State private var playBounce = false
    @State private var isAdjustingSpeed = false
    @State private var speedDragStart: Float = 1.0
    @State private var loopWorkItem: DispatchWorkItem?
    @State private var isLoopingPlayback = false
    @State private var recordingStartWorkItem: DispatchWorkItem?

    // Gesture thresholds
    private let tapThreshold: CGFloat = 15
    private let gestureThreshold: CGFloat = 25
    private let flipRevealThreshold: CGFloat = 60
    private let loopStartDelay: TimeInterval = 0.35
    private let recordHoldDelay: TimeInterval = 0.25
    private let speedOctavePoints: CGFloat = 80
    private let flipAnimation = Animation.easeInOut(duration: 0.4)
    private static let speedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        GeometryReader { geometry in
            let tileSize = geometry.size
            let minSize = min(tileSize.width, tileSize.height)

            ZStack {
                flipTile(size: tileSize, minSize: minSize)

                if (isAdjustingSpeed || playbackSpeed != 1.0) && !showBack {
                    speedIndicator(size: minSize)
                }
            }
            .frame(width: tileSize.width, height: tileSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Main Tile

    @ViewBuilder
    private func mainTile(size: CGSize, minSize: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(backgroundColor)
                .overlay(
                    Rectangle()
                        .stroke(color.opacity(0.3), lineWidth: hasRecording ? 0 : 2)
                )
                .shadow(color: color.opacity(0.4), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)

            if playbackLevel > 0 {
                Rectangle()
                    .fill(color)
                    .opacity(0.15 + Double(playbackLevel) * 0.35)
                    .animation(.easeOut(duration: 0.1), value: playbackLevel)
            }

            if isRecording {
                Rectangle()
                    .stroke(color, lineWidth: 3)
                    .scaleEffect(recordingPulse ? 1.04 : 1.0)
                    .opacity(recordingPulse ? 0 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: false),
                        value: recordingPulse
                    )
            }

            tileIcon(size: minSize)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showBack)
        .gesture(mainGesture)
        .onChange(of: isRecording) { _, newValue in
            recordingPulse = newValue
        }
    }

    @ViewBuilder
    private func tileIcon(size: CGFloat) -> some View {
        if isRecording {
            Circle()
                .fill(Color.red)
                .frame(width: size * 0.2, height: size * 0.2)
                .scaleEffect(recordingPulse ? 1.1 : 0.9)
                .animation(
                    .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                    value: recordingPulse
                )
        } else if hasRecording {
            if let samples = waveformSamples, !samples.isEmpty {
                AudioBlobView(
                    samples: samples,
                    playbackProgress: playbackProgress,
                    color: color,
                    size: size * 0.55
                )
                .scaleEffect(playBounce ? 1.15 : 1.0)
            } else {
                // Fallback to simple circle if no waveform data
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.15, height: size * 0.15)
                    .scaleEffect(playBounce ? 1.2 : 1.0)
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Back Tile

    private func backTile(size: CGSize, minSize: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(color.opacity(0.7))
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                )

            VStack {
                Spacer()

                HStack(spacing: minSize * 0.08) {
                    if playbackSpeed != 1.0 {
                        backTileButton(icon: "arrow.counterclockwise", tint: Color.blue, size: minSize) {
                            onResetSpeed()
                            flipBack()
                        }
                    }

                    backTileButton(icon: "square.and.arrow.up", tint: Color.green, size: minSize) {
                        onShare()
                        flipBack()
                    }

                    backTileButton(icon: "trash.fill", tint: Color.red, size: minSize) {
                        onClear()
                        flipBack()
                    }
                }

                Spacer()
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            flipBack()
        }
        .simultaneousGesture(backSwipeGesture)
    }

    @ViewBuilder
    private func backTileButton(icon: String, tint: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        let buttonSize = size * 0.24
        let iconOffset = -buttonSize * 0.04
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: iconOffset)
                .frame(width: buttonSize, height: buttonSize)
                .background(tint.opacity(0.85))
                .clipShape(Circle())
                .shadow(color: tint.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speed Indicator

    @ViewBuilder
    private func speedIndicator(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            if isAdjustingSpeed {
                Image(systemName: dragOffset.height < 0 ? "chevron.up" : "chevron.down")
                    .font(.system(size: size * 0.06, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }

            Text(speedText)
                .font(.system(size: size * 0.08, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.15), value: playbackSpeed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, size * 0.06)
    }

    private var speedText: String {
        if playbackSpeed == 1.0 {
            return "1x"
        }

        let formatted = Self.speedFormatter.string(from: NSNumber(value: playbackSpeed))
            ?? String(format: "%.2f", playbackSpeed)
        return "\(formatted)x"
    }

    // MARK: - Gesture

    private var mainGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let translation = value.translation

        if closeActiveBackIfNeeded() {
            return
        }

        if showBack {
            if abs(translation.width) > gestureThreshold {
                dragOffset = translation
            }
            return
        }

        if hasRecording {
            handleRecordedTileDrag(translation)
        } else {
            if !isPressed && !isRecording {
                isPressed = true
                playInteractionSound(.press)
                scheduleRecordingStart()
            }
        }
    }

    private func handleRecordedTileDrag(_ translation: CGSize) {
        let absX = abs(translation.width)
        let absY = abs(translation.height)

        if absX > gestureThreshold || absY > gestureThreshold {
            cancelLoopStart()
        }

        if absX < gestureThreshold && absY < gestureThreshold {
            if !isPressed {
                isPressed = true
                scheduleLoopStart()
            }
        } else if absY > absX && absY > gestureThreshold {
            if !isAdjustingSpeed {
                isAdjustingSpeed = true
                speedDragStart = playbackSpeed
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            dragOffset = translation

            let exponent = -translation.height / speedOctavePoints
            let speedScale = Float(pow(2.0, Double(exponent)))
            let newSpeed = speedDragStart * speedScale
            onSpeedChange(newSpeed)

        } else if absX > absY && absX > gestureThreshold {
            dragOffset = translation
            isPressed = false
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let translation = value.translation
        let absX = abs(translation.width)
        let absY = abs(translation.height)

        cancelLoopStart()
        cancelRecordingStart()

        if closeActiveBackIfNeeded() {
            isPressed = false
            dragOffset = .zero
            isAdjustingSpeed = false
            return
        }

        if isRecording {
            onStopRecording()
            playInteractionSound(.release)
            isPressed = false
            dragOffset = .zero
            isAdjustingSpeed = false
            return
        }

        defer {
            isPressed = false
            dragOffset = .zero
            isAdjustingSpeed = false
        }

        if showBack {
            if absX > absY && absX > flipRevealThreshold {
                flipBack()
            }
            return
        }

        if hasRecording {
            if isLoopingPlayback {
                onStopLooping()
                isLoopingPlayback = false
                return
            }

            if absX < tapThreshold && absY < tapThreshold {
                playBounce = true
                onPlay()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    playBounce = false
                }
            } else if absX > absY && absX > flipRevealThreshold {
                flipTileState()
            }
        } else {
            if isPressed && isRecording {
                onStopRecording()
                playInteractionSound(.release)
            }
        }
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: gestureThreshold, coordinateSpace: .local)
            .onEnded { value in
                let translation = value.translation
                let absX = abs(translation.width)
                let absY = abs(translation.height)

                if absX > absY && absX > flipRevealThreshold {
                    flipBack()
                }
            }
    }

    private func flipTileState() {
        withAnimation(flipAnimation) {
            activeBackIndex = index
        }
        playInteractionSound(.flip)
    }

    private func flipBack() {
        withAnimation(flipAnimation) {
            if activeBackIndex == index {
                activeBackIndex = nil
            }
        }
    }

    private func closeActiveBackIfNeeded() -> Bool {
        if let activeIndex = activeBackIndex, activeIndex != index {
            withAnimation(flipAnimation) {
                activeBackIndex = nil
            }
            return true
        }
        return false
    }

    private func scheduleLoopStart() {
        guard hasRecording else { return }
        cancelLoopStart()
        let workItem = DispatchWorkItem {
            guard isPressed && !isAdjustingSpeed && !showBack else { return }
            isLoopingPlayback = true
            onStartLooping()
        }
        loopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + loopStartDelay, execute: workItem)
    }

    private func cancelLoopStart() {
        loopWorkItem?.cancel()
        loopWorkItem = nil
    }

    private var showBack: Bool {
        activeBackIndex == index
    }

    private func scheduleRecordingStart() {
        cancelRecordingStart()
        let recordingWasActive = audioManager.isRecording
        let workItem = DispatchWorkItem {
            guard isPressed,
                  !isRecording,
                  !hasRecording,
                  !showBack,
                  !recordingWasActive,
                  !audioManager.isRecording else { return }
            onStartRecording()
            recordingStartWorkItem = nil
        }
        recordingStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + recordHoldDelay, execute: workItem)
    }

    private func cancelRecordingStart() {
        recordingStartWorkItem?.cancel()
        recordingStartWorkItem = nil
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        if isRecording {
            return color.opacity(0.6)
        } else if hasRecording {
            return color
        } else {
            return color.opacity(0.15)
        }
    }

    private func flipTile(size: CGSize, minSize: CGFloat) -> some View {
        ZStack {
            mainTile(size: size, minSize: minSize)
                .opacity(showBack ? 0.0 : 1.0)
                .rotation3DEffect(
                    .degrees(showBack ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.8
                )

            backTile(size: size, minSize: minSize)
                .opacity(showBack ? 1.0 : 0.0)
                .rotation3DEffect(
                    .degrees(showBack ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.8
                )
        }
        .clipped()
        .animation(flipAnimation, value: showBack)
    }

    private enum InteractionSound {
        case press
        case release
        case flip
    }

    private func playInteractionSound(_ sound: InteractionSound) {
        let soundId: SystemSoundID
        switch sound {
        case .press:
            soundId = 1104
        case .release:
            soundId = 1155
        case .flip:
            soundId = 1113
        }
        AudioServicesPlaySystemSound(soundId)
    }
}

// Toddler-friendly color palette
struct TileColors {
    static let palette: [Color] = [
        Color(red: 1.0, green: 0.4, blue: 0.4),    // Coral Red
        Color(red: 1.0, green: 0.8, blue: 0.2),    // Sunny Yellow
        Color(red: 0.3, green: 0.6, blue: 1.0),    // Ocean Blue
        Color(red: 0.4, green: 0.8, blue: 0.4),    // Grass Green
        Color(red: 0.7, green: 0.5, blue: 0.9),    // Lavender Purple
        Color(red: 1.0, green: 0.6, blue: 0.7),    // Soft Pink
        Color(red: 0.2, green: 0.8, blue: 0.8),    // Teal
        Color(red: 1.0, green: 0.6, blue: 0.2),    // Tangerine Orange
        Color(red: 0.4, green: 0.7, blue: 1.0),    // Sky Blue
        Color(red: 0.5, green: 0.9, blue: 0.7),    // Mint Green
    ]

    static func color(for index: Int) -> Color {
        palette[index % palette.count]
    }
}
