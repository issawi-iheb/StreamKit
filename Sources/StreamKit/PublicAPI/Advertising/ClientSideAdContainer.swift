//
//  ClientSideAdContainer.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//

import SwiftUI
#if os(iOS)
import UIKit
/// A player-owned UIKit container used to display client-side advertisements.
///
/// Each player should own its own container. The container becomes usable
/// when its hosting view controller is visible in a window.
@MainActor
public final class ClientSideAdContainer {
    private weak var hostViewController: UIViewController?

    public private(set) var isBreakActive = false

    /// The view used by the advertising SDK to render ads.
    public var adContainerView: UIView? {
        hostViewController?.viewIfLoaded
    }

    /// The visible view controller associated with the ad container.
    public var viewController: UIViewController? {
        guard isDisplayable else { return nil }
        return hostViewController
    }

    /// Whether the container is attached to a window.
    public var isDisplayable: Bool {
        hostViewController?.viewIfLoaded?.window != nil
    }

    public init() {}

    /// Waits until the host view is attached to a window.
    ///
    /// Returns `false` if the waiting task is cancelled.
    public func waitUntilDisplayable() async -> Bool {
        while !Task.isCancelled && !isDisplayable {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }

        return !Task.isCancelled && isDisplayable
    }

    func register(_ viewController: UIViewController) {
        hostViewController = viewController
    }

    func unregister(_ viewController: UIViewController) {
        guard hostViewController === viewController else { return }
        hostViewController = nil
    }

    func updateBreakState(isActive: Bool) {
        isBreakActive = isActive
    }
}

/// SwiftUI host that attaches a player's ad container to its view hierarchy.
///
/// Place this alongside the corresponding player surface, typically as
/// an overlay, so the advertising SDK can render over the video.
@MainActor
public struct ClientSideAdContainerHost: UIViewControllerRepresentable {
    private let container: ClientSideAdContainer

    public init(container: ClientSideAdContainer) {
        self.container = container
    }

    public func makeUIViewController(
        context: Context
    ) -> ClientSideAdContainerHostController {
        ClientSideAdContainerHostController(container: container)
    }

    public func updateUIViewController(
        _ uiViewController: ClientSideAdContainerHostController,
        context: Context
    ) {
        uiViewController.registerIfVisible()
    }

    public static func dismantleUIViewController(
        _ uiViewController: ClientSideAdContainerHostController,
        coordinator: ()
    ) {
        uiViewController.unregister()
    }
}

/// UIKit host backing `ClientSideAdContainerHost`.
@MainActor
public final class ClientSideAdContainerHostController: UIViewController {
    private let container: ClientSideAdContainer

    fileprivate init(container: ClientSideAdContainer) {
        self.container = container
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let hostView = AdContainerHostView()
        hostView.backgroundColor = .clear
        hostView.isOpaque = false
        hostView.container = container
        view = hostView
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        registerIfVisible()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        unregister()
    }

    fileprivate func registerIfVisible() {
        guard viewIfLoaded?.window != nil else { return }
        container.register(self)
    }

    fileprivate func unregister() {
        container.unregister(self)
    }
}

@MainActor
private final class AdContainerHostView: UIView {
    weak var container: ClientSideAdContainer?

    override func hitTest(
        _ point: CGPoint,
        with event: UIEvent?
    ) -> UIView? {
        guard container?.isBreakActive == true else {
            return nil
        }

        return super.hitTest(point, with: event)
    }
}
#endif
