import SwiftUI
import AudioToolbox

struct SoundTileView: View {
    let index: Int
    let color: Color
    let hasRecording: Bool
    let isRecording: Bool
    let playbackSpeed: Float
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
    @State private var showBack = false
    @State private var isAdjustingSpeed = false
    @State private var speedDragStart: Float = 1.0
    @State private var loopWorkItem: DispatchWorkItem?
    @State private var isLoopingPlayback = false

    // Gesture thresholds
    private let tapThreshold: CGFloat = 15
    private let gestureThreshold: CGFloat = 25
    private let flipRevealThreshold: CGFloat = 60
    private let loopStartDelay: TimeInterval = 0.35
    private let cornerRadius: CGFloat = 18

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
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(color.opacity(0.3), lineWidth: hasRecording ? 0 : 2)
                )
                .shadow(color: color.opacity(0.4), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)

            if isRecording {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
            Image(systemName: "waveform")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .scaleEffect(playBounce ? 1.2 : 1.0)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.16, weight: .medium))
                .foregroundColor(color.opacity(0.5))
        }
    }

    // MARK: - Back Tile

    private func backTile(size: CGSize, minSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                )

            VStack(spacing: minSize * 0.14) {
                Spacer()

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

                Spacer()
            }
        }
        .frame(width: size.width, height: size.height)
        .onTapGesture {
            flipBack()
        }
    }

    @ViewBuilder
    private func backTileButton(icon: String, tint: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        let buttonSize = size * 0.32
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.18, weight: .semibold))
                .foregroundColor(.white)
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
        VStack(spacing: 4) {
            if isAdjustingSpeed {
                Image(systemName: dragOffset.height < 0 ? "chevron.up" : "chevron.down")
                    .font(.system(size: size * 0.12, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(abs(dragOffset.height) > gestureThreshold ? 1.0 : 0.5)
            }

            Text(speedText)
                .font(.system(size: size * 0.14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(speedBackgroundColor.opacity(0.9))
                .clipShape(Capsule())
        }
        .animation(.easeOut(duration: 0.15), value: playbackSpeed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, size * 0.08)
    }

    private var speedText: String {
        if playbackSpeed == 1.0 {
            return "1x"
        } else if playbackSpeed < 1.0 {
            return String(format: "%.1fx", playbackSpeed)
        } else {
            return String(format: "%.1fx", playbackSpeed)
        }
    }

    private var speedBackgroundColor: Color {
        if playbackSpeed > 1.0 {
            return .orange
        } else if playbackSpeed < 1.0 {
            return .purple
        } else {
            return .gray
        }
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
                onStartRecording()
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

            let speedDelta = Float(-translation.height / 150)
            let newSpeed = speedDragStart + speedDelta
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
            onStopRecording()
            playInteractionSound(.release)
        }
    }

    private func flipTileState() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showBack.toggle()
        }
        playInteractionSound(.flip)
    }

    private func flipBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showBack = false
        }
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
                .rotation3DEffect(.degrees(showBack ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            backTile(size: size, minSize: minSize)
                .opacity(showBack ? 1.0 : 0.0)
                .rotation3DEffect(.degrees(showBack ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
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
