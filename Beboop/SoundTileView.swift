import SwiftUI

struct SoundTileView: View {
    let index: Int
    let color: Color
    let hasRecording: Bool
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onPlay: () -> Void
    let onClear: () -> Void

    @State private var isPressed = false
    @State private var dragOffset: CGSize = .zero
    @State private var recordingPulse = false
    @State private var playBounce = false

    private let clearThreshold: CGFloat = 80

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

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
                    // Play icon (triangle)
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

                // Swipe-to-clear indicator
                if hasRecording && abs(dragOffset.width) > 20 {
                    Image(systemName: "trash.fill")
                        .font(.system(size: size * 0.2))
                        .foregroundColor(.white.opacity(min(abs(dragOffset.width) / clearThreshold, 1.0)))
                        .offset(x: dragOffset.width > 0 ? -size * 0.25 : size * 0.25)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .offset(x: dragOffset.width * 0.3)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
            .gesture(mainGesture)
            .onChange(of: isRecording) { _, newValue in
                if newValue {
                    recordingPulse = true
                } else {
                    recordingPulse = false
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var backgroundColor: Color {
        if isRecording {
            return color.opacity(0.6)
        } else if hasRecording {
            return color
        } else {
            return color.opacity(0.15)
        }
    }

    // Single unified gesture that handles all interactions
    private var mainGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if hasRecording {
                    // For tiles with recording: track drag for swipe-to-clear
                    if abs(value.translation.width) > 10 {
                        dragOffset = value.translation
                    } else if !isPressed {
                        isPressed = true
                    }
                } else {
                    // For empty tiles: start recording on press
                    if !isPressed && !isRecording {
                        isPressed = true
                        onStartRecording()
                    }
                }
            }
            .onEnded { value in
                if hasRecording {
                    // Check if this was a swipe
                    if abs(value.translation.width) > clearThreshold {
                        onClear()
                    } else if abs(value.translation.width) < 10 {
                        // This was a tap - play the sound
                        playBounce = true
                        onPlay()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            playBounce = false
                        }
                    }
                    dragOffset = .zero
                } else {
                    // Stop recording
                    if isRecording {
                        onStopRecording()
                    }
                }
                isPressed = false
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
