import SwiftUI

struct SoundTileView: View {
    let index: Int
    let color: Color
    let hasRecording: Bool
    let isRecording: Bool
    let playbackSpeed: Float
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onPlay: () -> Void
    let onClear: () -> Void
    let onShare: () -> Void
    let onSpeedChange: (Float) -> Void
    let onResetSpeed: () -> Void

    @State private var isPressed = false
    @State private var dragOffset: CGSize = .zero
    @State private var recordingPulse = false
    @State private var playBounce = false
    @State private var showMenu = false
    @State private var isAdjustingSpeed = false
    @State private var speedDragStart: Float = 1.0

    // Gesture thresholds
    private let tapThreshold: CGFloat = 15
    private let gestureThreshold: CGFloat = 25
    private let menuRevealThreshold: CGFloat = 60

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Menu buttons (revealed on horizontal swipe)
                if showMenu {
                    menuButtons(size: size)
                }

                // Main tile
                mainTile(size: size)
                    .offset(x: showMenu ? -size * 0.4 : dragOffset.width * 0.3,
                            y: isAdjustingSpeed ? dragOffset.height * 0.1 : 0)

                // Speed indicator overlay
                if isAdjustingSpeed || playbackSpeed != 1.0 {
                    speedIndicator(size: size)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Main Tile

    @ViewBuilder
    private func mainTile(size: CGFloat) -> some View {
        ZStack {
            // Background circle
            Circle()
                .fill(backgroundColor)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: hasRecording ? 0 : 3)
                )
                .shadow(color: color.opacity(0.4), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)

            // Recording pulse animation
            if isRecording {
                Circle()
                    .stroke(color, lineWidth: 4)
                    .scaleEffect(recordingPulse ? 1.3 : 1.0)
                    .opacity(recordingPulse ? 0 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: false),
                        value: recordingPulse
                    )
            }

            // Icon
            tileIcon(size: size)
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showMenu)
        .gesture(mainGesture)
        .onChange(of: isRecording) { _, newValue in
            recordingPulse = newValue
        }
    }

    @ViewBuilder
    private func tileIcon(size: CGFloat) -> some View {
        if isRecording {
            // Recording indicator
            Circle()
                .fill(Color.red)
                .frame(width: size * 0.25, height: size * 0.25)
                .scaleEffect(recordingPulse ? 1.1 : 0.9)
                .animation(
                    .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                    value: recordingPulse
                )
        } else if hasRecording {
            // Play icon
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(playBounce ? 1.2 : 1.0)
        } else {
            // Microphone icon for empty tile
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.25, weight: .medium))
                .foregroundColor(color.opacity(0.5))
        }
    }

    // MARK: - Menu Buttons

    @ViewBuilder
    private func menuButtons(size: CGFloat) -> some View {
        HStack(spacing: 8) {
            Spacer()

            // Reset speed button (only show if speed is modified)
            if playbackSpeed != 1.0 {
                menuButton(
                    icon: "arrow.counterclockwise",
                    backgroundColor: Color.blue,
                    size: size * 0.35
                ) {
                    onResetSpeed()
                    closeMenu()
                }
            }

            // Share button
            menuButton(
                icon: "square.and.arrow.up",
                backgroundColor: Color.green,
                size: size * 0.35
            ) {
                onShare()
                closeMenu()
            }

            // Delete button
            menuButton(
                icon: "trash.fill",
                backgroundColor: Color.red,
                size: size * 0.35
            ) {
                onClear()
                closeMenu()
            }
        }
        .padding(.trailing, 8)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private func menuButton(icon: String, backgroundColor: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(backgroundColor)
                .clipShape(Circle())
                .shadow(color: backgroundColor.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speed Indicator

    @ViewBuilder
    private func speedIndicator(size: CGFloat) -> some View {
        VStack(spacing: 4) {
            // Speed arrows
            if isAdjustingSpeed {
                Image(systemName: dragOffset.height < 0 ? "chevron.up" : "chevron.down")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(abs(dragOffset.height) > gestureThreshold ? 1.0 : 0.5)
            }

            // Speed value
            Text(speedText)
                .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(speedBackgroundColor.opacity(0.9))
                .clipShape(Capsule())
        }
        .animation(.easeOut(duration: 0.15), value: playbackSpeed)
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

        if showMenu {
            // If menu is open, track horizontal drag to close
            if translation.width > 30 {
                closeMenu()
            }
            return
        }

        if hasRecording {
            handleRecordedTileDrag(translation)
        } else {
            // For empty tiles: start recording on press
            if !isPressed && !isRecording {
                isPressed = true
                onStartRecording()
            }
        }
    }

    private func handleRecordedTileDrag(_ translation: CGSize) {
        let absX = abs(translation.width)
        let absY = abs(translation.height)

        // Determine gesture direction with threshold
        if absX < gestureThreshold && absY < gestureThreshold {
            // Still within tap zone
            if !isPressed {
                isPressed = true
            }
        } else if absY > absX && absY > gestureThreshold {
            // Vertical drag - speed control
            if !isAdjustingSpeed {
                isAdjustingSpeed = true
                speedDragStart = playbackSpeed
                // Light haptic when entering speed mode
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            dragOffset = translation

            // Calculate new speed based on drag
            // Dragging up = faster, dragging down = slower
            let speedDelta = Float(-translation.height / 150) // 150pt = 1x speed change
            let newSpeed = speedDragStart + speedDelta
            onSpeedChange(newSpeed)

        } else if absX > absY && absX > gestureThreshold {
            // Horizontal drag - prepare for menu
            dragOffset = translation
            isPressed = false
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let translation = value.translation
        let absX = abs(translation.width)
        let absY = abs(translation.height)

        defer {
            isPressed = false
            dragOffset = .zero
            isAdjustingSpeed = false
        }

        if showMenu {
            // Menu is already shown, close on any gesture end
            return
        }

        if hasRecording {
            if absX < tapThreshold && absY < tapThreshold {
                // This was a tap - play the sound
                playBounce = true
                onPlay()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    playBounce = false
                }
            } else if absX > absY && absX > menuRevealThreshold && translation.width < 0 {
                // Horizontal swipe left - show menu
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showMenu = true
                }
            }
            // Vertical drag (speed) is handled in onChanged, just reset state here
        } else {
            // Stop recording
            if isRecording {
                onStopRecording()
            }
        }
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showMenu = false
        }
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
