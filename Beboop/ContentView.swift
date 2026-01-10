import SwiftUI

struct ContentView: View {
    @StateObject private var soundPlayer = SoundPlayer()
    @State private var isPressed = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.95, blue: 0.88), Color(red: 0.98, green: 0.88, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Beboop")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.2))

                Text("Tap for a tiny boop")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.43, green: 0.37, blue: 0.33))

                Button(action: handleTap) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.74, blue: 0.3), Color(red: 0.98, green: 0.42, blue: 0.36)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 180, height: 180)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.5), lineWidth: 8)
                            )
                            .shadow(color: Color(red: 0.95, green: 0.5, blue: 0.45).opacity(0.4), radius: 16, x: 0, y: 10)

                        Text("Boop")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            }
            .padding(.horizontal, 24)
        }
    }

    private func handleTap() {
        soundPlayer.play()
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isPressed = false
        }
    }
}

#Preview {
    ContentView()
}
