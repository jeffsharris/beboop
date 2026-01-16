import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Sounds", systemImage: "waveform")
                }

            HighContrastMobileView()
                .tabItem {
                    Label("Mobile", systemImage: "circle.grid.2x2")
                }
        }
        .labelStyle(.iconOnly)
    }
}

#Preview {
    MainTabView()
}
