import Foundation

/// Completes AVKit restoration after the demo's player route is visible again.
@MainActor
final class DemoPlayerRouteRestorationCoordinator {
    var requestPlayerRoute: (@MainActor () -> Void)?

    private(set) var isPlayerInterfaceAvailable = false
    private var pendingCompletions: [@Sendable (Bool) -> Void] = []

    func restorePlayerInterface(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard !isPlayerInterfaceAvailable else {
            completion(true)
            return
        }

        let shouldRequestRoute = pendingCompletions.isEmpty
        pendingCompletions.append(completion)
        guard let requestPlayerRoute else {
            completePendingRestorations(restored: false)
            return
        }
        if shouldRequestRoute {
            requestPlayerRoute()
        }
    }

    func playerInterfaceDidAppear() {
        isPlayerInterfaceAvailable = true
        completePendingRestorations(restored: true)
    }

    func playerInterfaceDidDisappear() {
        isPlayerInterfaceAvailable = false
    }

    func playerInterfaceRestorationFailed() {
        completePendingRestorations(restored: false)
    }

    private func completePendingRestorations(restored: Bool) {
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        completions.forEach { $0(restored) }
    }
}
