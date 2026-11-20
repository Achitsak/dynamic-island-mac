import AppKit
import SwiftUI

/// A borderless, click-through panel pinned to the top of the screen, above the menu bar.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Must sit above the menu bar so it can cover the notch area. (Don't set
        // `isFloatingPanel` — it silently resets the level to `.floating`.)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // AppKit would otherwise push the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandController {
    private let model: IslandModel
    private let panel = IslandPanel()
    private var monitors: [Any] = []
    /// Cached: the global mouse monitor fires on every pointer move on screen.
    private var hitRect = CGRect.zero
    private var settleTask: Task<Void, Never>?

    init(model: IslandModel) {
        self.model = model

        let host = IslandHostingView(rootView: IslandRootView(model: model))
        host.sizingOptions = []
        host.safeAreaRegions = []  // The notch would otherwise inset everything by its height.
        panel.contentView = host

        relayout()
        panel.orderFrontRegardless()
        installMouseTracking()
        observeEnvironment()
    }

    func relayout() {
        guard let screen = targetScreen() else { return }
        let geometry = IslandGeometry(screen: screen, sizeScale: model.settings.sizeScale)
        if model.geometry != geometry {
            // Snap rather than spring: the window resizes at once and would clip the animation.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.geometry = geometry }
        }

        // Sized for the largest state; a smaller window is cheaper to composite.
        let u = geometry.unit
        let width = min(screen.frame.width, model.expandedWidth + 40 * u)
        let tallest = (Layout.timerRowHeight + Layout.playerHeight + Layout.bottomPadding + 12) * u
        let height = min(screen.frame.height * 0.6, geometry.notchHeight + tallest)
        let frame = NSRect(x: geometry.centerX - width / 2, y: geometry.screenTop - height, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func targetScreen() -> NSScreen? {
        if model.settings.preferMainDisplay, let main = NSScreen.screens.first {
            return main  // The screen that holds the menu bar.
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: Pointer

    private func installMouseTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) {
            monitors.append(local)
        }
        trackHitRect()
    }

    /// Re-checks the pointer when the island changes shape under a still cursor.
    private func trackHitRect() {
        hitRect = withObservationTracking {
            model.hitRect
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.trackHitRect()
                    self?.updatePointer()
                }
            }
        }
    }

    private func updatePointer() {
        let point = NSEvent.mouseLocation
        if !model.isHovering, panel.ignoresMouseEvents, !hitRect.contains(point) { return }
        var inside = hitRect.contains(point)
        // Keep the island open while dragging (e.g. scrubbing) even if the pointer slips out.
        if !inside, model.isHovering, NSEvent.pressedMouseButtons & 1 == 1 { inside = true }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.setHovering(inside)
    }

    // MARK: Screens & spaces

    /// Connecting a display or changing the resolution sends a burst of notifications,
    /// and NSScreen can report half-updated values in between (the system may also still
    /// move windows around). Following each step makes the island jump, so lay out once
    /// the burst is over, and again a little later to be sure.
    private func screensChanged() {
        model.ignoreSystemBrightnessChanges()
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            for delay in [0.3, 1.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.relayout()
                self.panel.orderFrontRegardless()
            }
        }
    }

    private func observeEnvironment() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.orderFrontRegardless() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.relayout()
                self?.panel.orderFrontRegardless()
            }
        }
    }
}
