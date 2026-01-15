import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var tileStates: [Bool] = Array(repeating: false, count: 10)
    @State private var refreshTrigger = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            // Soft gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.94),
                    Color(red: 0.95, green: 0.92, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                Text("Beboop")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.3, green: 0.25, blue: 0.35))

                Text(instructionText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.45, blue: 0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Tile Grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<10, id: \.self) { index in
                        SoundTileView(
                            index: index,
                            color: TileColors.color(for: index),
                            hasRecording: audioManager.hasRecording(for: index),
                            isRecording: audioManager.currentRecordingTile == index,
                            onStartRecording: {
                                audioManager.startRecording(for: index)
                            },
                            onStopRecording: {
                                audioManager.stopRecording()
                                refreshTileStates()
                            },
                            onPlay: {
                                audioManager.play(tileIndex: index)
                            },
                            onClear: {
                                audioManager.clearRecording(for: index)
                                refreshTileStates()
                            }
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .id("\(index)-\(tileStates[index])-\(refreshTrigger)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
            }
            .padding(.top, 16)
        }
    }

    private var instructionText: String {
        if audioManager.isRecording {
            return "Recording... Release to stop"
        } else {
            return "Hold to record, Tap to play, Swipe to clear"
        }
    }

    private func refreshTileStates() {
        // Toggle to force UI refresh
        for i in 0..<10 {
            tileStates[i] = audioManager.hasRecording(for: i)
        }
        refreshTrigger.toggle()
    }
}

#Preview {
    ContentView()
}
