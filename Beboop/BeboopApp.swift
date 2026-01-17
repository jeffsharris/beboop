import SwiftUI
import UIKit
import Foundation

@main
struct BeboopApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ModeSwitcherView()
        }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }
}

enum AudioHandoff {
    static let stopNotification = Notification.Name("audioHandoffStop")
    static let startDelay: TimeInterval = 0.2

    static func notifyStop() {
        NotificationCenter.default.post(name: stopNotification, object: nil)
    }
}
