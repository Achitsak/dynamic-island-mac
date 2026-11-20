import AppKit

@main
enum DynamicIslandApp {
    @MainActor
    static func main() {
        // Writing to the media helper after it exits must not kill the app.
        signal(SIGPIPE, SIG_IGN)

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
