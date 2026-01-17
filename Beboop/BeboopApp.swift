import SwiftUI
import UIKit
import Foundation

@main
struct BeboopApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audioCoordinator = AudioCoordinator()

    var body: some Scene {
        WindowGroup {
            ModeSwitcherView()
                .environmentObject(audioCoordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }
}

enum AppMode: String, CaseIterable, Identifiable {
    case cozyCoos
    case driftDoodles
    case voiceAurora
    case voiceAuroraClassic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cozyCoos:
            return "Cozy Coos"
        case .driftDoodles:
            return "Drift Doodles"
        case .voiceAurora:
            return "Spatial Voice"
        case .voiceAuroraClassic:
            return "Aurora Voice"
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
        case .voiceAuroraClassic:
            return "circle"
        }
    }
}

final class AudioCoordinator: ObservableObject {
    typealias StopHandler = (@escaping () -> Void) -> Void

    private struct Handler {
        let start: () -> Void
        let stop: StopHandler
    }

    private let transitionDelay: TimeInterval = 0.12
    private var handlers: [AppMode: Handler] = [:]
    private var desiredMode: AppMode?
    private var isTransitioning = false

    @Published private(set) var activeMode: AppMode?

    func register(mode: AppMode, start: @escaping () -> Void, stop: @escaping StopHandler) {
        handlers[mode] = Handler(start: start, stop: stop)
        startDesiredIfReady()
    }

    func unregister(mode: AppMode) {
        handlers.removeValue(forKey: mode)
        if activeMode == mode {
            activeMode = nil
        }
    }

    func requestMode(_ mode: AppMode) {
        desiredMode = mode
        transitionIfNeeded()
    }

    private func transitionIfNeeded() {
        guard !isTransitioning else { return }
        guard desiredMode != activeMode else { return }
        isTransitioning = true

        stopCurrent { [weak self] in
            guard let self else { return }
            self.activeMode = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + self.transitionDelay) {
                self.isTransitioning = false
                self.startDesiredIfReady()
            }
        }
    }

    private func stopCurrent(completion: @escaping () -> Void) {
        guard let activeMode,
              let handler = handlers[activeMode] else {
            completion()
            return
        }
        handler.stop(completion)
    }

    private func startDesiredIfReady() {
        guard !isTransitioning,
              let desiredMode,
              activeMode != desiredMode,
              let handler = handlers[desiredMode] else {
            return
        }
        activeMode = desiredMode
        handler.start()
    }
}
