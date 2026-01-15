import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var tileStates: [Bool] = Array(repeating: false, count: 10)
    @State private var refreshTrigger = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        GeometryReader { geometry in
            let tileHeight = geometry.size.height / 5

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 0.94),
                        Color(red: 0.95, green: 0.92, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(0..<10, id: \.self) { index in
                        SoundTileView(
                            index: index,
                            color: TileColors.color(for: index),
                            hasRecording: audioManager.hasRecording(for: index),
                            isRecording: audioManager.currentRecordingTile == index,
                            playbackSpeed: audioManager.getPlaybackSpeed(for: index),
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
                            onStartLooping: {
                                audioManager.startLooping(tileIndex: index)
                            },
                            onStopLooping: {
                                audioManager.stopLoopingAfterCurrent(tileIndex: index)
                            },
                            onClear: {
                                audioManager.clearRecording(for: index)
                                refreshTileStates()
                            },
                            onShare: {
                                shareTile(index: index)
                            },
                            onSpeedChange: { speed in
                                audioManager.setPlaybackSpeed(for: index, speed: speed)
                            },
                            onResetSpeed: {
                                audioManager.resetPlaybackSpeed(for: index)
                            }
                        )
                        .frame(height: tileHeight)
                        .id("\(index)-\(tileStates[index])-[\(refreshTrigger)]-\(audioManager.playbackSpeeds[index] ?? 1.0)")
                    }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func refreshTileStates() {
        for i in 0..<10 {
            tileStates[i] = audioManager.hasRecording(for: i)
        }
        refreshTrigger.toggle()
    }

    private func shareTile(index: Int) {
        if let url = audioManager.getShareableURL(for: index) {
            shareURL = url
            showShareSheet = true
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
