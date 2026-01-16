import SwiftUI

struct ModeSwitcherView: View {
    private enum AppMode: String, CaseIterable, Identifiable {
        case cozyCoos
        case driftDoodles
        case voiceAurora

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cozyCoos:
                return "Cozy Coos"
            case .driftDoodles:
                return "Drift Doodles"
            case .voiceAurora:
                return "Voice Aurora"
            }
        }

        var iconName: String {
            switch self {
            case .cozyCoos:
                return "waveform"
            case .driftDoodles:
                return "circle.grid.2x2"
            case .voiceAurora:
                return "sparkles"
            }
        }
    }

    @State private var activeMode: AppMode = .cozyCoos
    @State private var isMenuPresented = false

    var body: some View {
        ZStack {
            modeView

            menuButton

            if isMenuPresented {
                menuOverlay
            }
        }
    }

    @ViewBuilder
    private var modeView: some View {
        switch activeMode {
        case .cozyCoos:
            ContentView()
        case .driftDoodles:
            HighContrastMobileView()
        case .voiceAurora:
            VoiceAuroraView()
        }
    }

    private var menuButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isMenuPresented = true
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isMenuPresented = false
                    }
                }

            VStack(spacing: 16) {
                Text("Pick a mode")
                    .font(.headline)
                    .foregroundColor(.primary)

                ForEach(AppMode.allCases) { mode in
                    Button {
                        activeMode = mode
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isMenuPresented = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 28)
                            Text(mode.title)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                            Spacer()
                        }
                        .foregroundColor(.primary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.6))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            .padding(24)
        }
        .transition(.opacity)
    }
}

#Preview {
    ModeSwitcherView()
}
