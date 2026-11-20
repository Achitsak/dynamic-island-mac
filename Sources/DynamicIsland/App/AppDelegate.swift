import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let openIslandSettings = Notification.Name("OpenIslandSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: IslandModel!
    private var controller: IslandController!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .contains(where: { $0 != .current && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }

        model = IslandModel()
        controller = IslandController(model: model)
        model.start()
        refreshStatusItem()
        enableLaunchAtLoginOnFirstRun()
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.playDemo() }
            }
        }

        NotificationCenter.default.addObserver(forName: .openIslandSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openSettings() }
        }
        NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatusItem()
                self?.controller.relayout()
                self?.model.settingsChanged()
            }
        }
    }

    /// Start at login by default once the app is installed; it can be turned off in Settings.
    /// Copies run from elsewhere (e.g. a build folder) are left alone.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didSetUpLaunchAtLogin"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    // Double-clicking the app while it runs opens Settings (there is no Dock icon).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Settings window

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Dynamic Island"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar icon

    private func refreshStatusItem() {
        if AppSettings.shared.showMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "capsule.portrait.fill", accessibilityDescription: "Dynamic Island")
                ?? NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")
            item.menu = makeMenu()
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let timerItem = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for minutes in [1, 3, 5, 10, 15, 25, 30, 60] {
            let item = NSMenuItem(title: "\(minutes) min", action: #selector(startTimer(_:)), keyEquivalent: "")
            item.tag = minutes
            item.target = self
            timerMenu.addItem(item)
        }
        timerMenu.addItem(.separator())
        let cancel = NSMenuItem(title: "Cancel Timer", action: #selector(cancelTimer), keyEquivalent: "")
        cancel.target = self
        timerMenu.addItem(cancel)
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)

        let demo = NSMenuItem(title: "Play Demo", action: #selector(playDemo), keyEquivalent: "")
        demo.target = self
        menu.addItem(demo)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        model.timer.start(seconds: TimeInterval(sender.tag * 60))
    }

    @objc private func cancelTimer() {
        model.timer.cancel()
    }

    @objc private func playDemo() {
        model.runDemo()
    }
}
