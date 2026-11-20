import AppKit
import ImageIO
import Observation
import SwiftUI

/// System-wide "Now Playing" (Music, Spotify, browsers, …).
///
/// macOS only lets Apple-signed processes read MediaRemote, so the actual work
/// happens in `libMediaBridge.dylib` loaded into `/usr/bin/perl`. It streams JSON
/// lines on stdout and accepts commands on stdin.
@Observable @MainActor
final class NowPlayingService {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
    }

    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    private(set) var accent: Color = .white
    private(set) var bundleID: String?
    private(set) var appName: String?
    private(set) var appIcon: NSImage?

    private var elapsedBase: Double = 0
    private var elapsedStamp = Date()
    private var rate: Double = 1

    var trackKey: String { "\(track?.title ?? "")|\(track?.artist ?? "")" }

    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var restartDelay: TimeInterval = 1
    @ObservationIgnored private var pendingPlaying: (value: Bool, until: Date)?

    private static let perlScript = """
    use DynaLoader;
    my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $s = DynaLoader::dl_find_symbol($h, "di_stream") or die "di_stream missing";
    DynaLoader::dl_install_xsub("main::di_stream", $s);
    di_stream();
    """

    // MARK: Playback position

    func elapsed(at date: Date) -> Double {
        var value = elapsedBase
        if isPlaying { value += date.timeIntervalSince(elapsedStamp) * rate }
        if let duration = track?.duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }

    // MARK: Commands

    func togglePlayPause() {
        setOptimisticPlaying(!isPlaying)
        send("toggle")
    }

    func play() {
        setOptimisticPlaying(true)
        send("play")
    }

    func next() { send("next") }
    func previous() { send("prev") }

    func seek(to seconds: Double) {
        elapsedBase = seconds
        elapsedStamp = Date()
        send(String(format: "seek %.3f", seconds))
    }

    func openSourceApp() {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func setOptimisticPlaying(_ playing: Bool) {
        // Freeze the clock at the current position before flipping state.
        elapsedBase = elapsed(at: Date())
        elapsedStamp = Date()
        isPlaying = playing
        pendingPlaying = (playing, Date().addingTimeInterval(1.2))
        onChange?()
    }

    private func send(_ command: String) {
        guard let input, let data = (command + "\n").data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }

    // MARK: Helper process

    func start() {
        guard process == nil else { return }
        stopping = false
        guard let library = Self.bridgeLibrary() else {
            NSLog("DynamicIsland: libMediaBridge.dylib not found in the app bundle")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.perlScript, library.path]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(data) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.processEnded() }
            }
        }

        do {
            try process.run()
            self.process = process
            self.input = input.fileHandleForWriting
        } catch {
            NSLog("DynamicIsland: failed to start media helper: \(error)")
            scheduleRestart()
        }
    }

    /// A downloaded app carries the quarantine flag on every file, and perl won't
    /// load a quarantined library. In that case run a clean copy instead.
    private static func bridgeLibrary() -> URL? {
        guard let bundled = Bundle.main.url(forResource: "libMediaBridge", withExtension: "dylib") else { return nil }
        guard getxattr(bundled.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 else { return bundled }

        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return bundled }
        let folder = support.appendingPathComponent("DynamicIsland", isDirectory: true)
        let copy = folder.appendingPathComponent("libMediaBridge.dylib")
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: copy.path) { try fileManager.removeItem(at: copy) }
            try fileManager.copyItem(at: bundled, to: copy)
            removexattr(copy.path, "com.apple.quarantine", 0)
            return copy
        } catch {
            return bundled
        }
    }

    func stop() {
        stopping = true
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
    }

    private func processEnded() {
        process = nil
        input = nil
        buffer.removeAll()
        guard !stopping else { return }
        scheduleRestart()
    }

    private func scheduleRestart() {
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.stopping else { return }
                self.start()
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(object)
        }
    }

    // MARK: Updates

    func handle(_ payload: [String: Any]) {
        guard payload["type"] as? String == "nowPlaying" else {
            if payload["type"] as? String == "ready" { restartDelay = 1 }
            return
        }

        if let encoded = payload["artwork"] as? String {
            updateArtwork(encoded.isEmpty ? nil : Data(base64Encoded: encoded))
        }

        guard let title = payload["title"] as? String, !title.isEmpty else {
            if track != nil { track = nil }
            isPlaying = false
            if artwork != nil { updateArtwork(nil) }
            onChange?()
            return
        }

        let newTrack = Track(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            duration: payload["duration"] as? Double ?? 0
        )
        if newTrack != track { track = newTrack }

        var playing = payload["playing"] as? Bool ?? false
        if let pending = pendingPlaying {
            if Date() < pending.until, pending.value != playing {
                playing = pending.value  // The player has not caught up with our command yet.
            } else {
                pendingPlaying = nil
            }
        }

        let reportedRate = payload["rate"] as? Double ?? (playing ? 1 : 0)
        rate = reportedRate > 0 ? reportedRate : 1
        if let elapsed = payload["elapsed"] as? Double {
            elapsedBase = elapsed
            if let stamp = payload["timestamp"] as? Double {
                elapsedStamp = Date(timeIntervalSince1970: stamp)
            } else {
                elapsedStamp = Date()
            }
        }
        if playing != isPlaying { isPlaying = playing }

        if let bundle = payload["bundle"] as? String, bundle != bundleID {
            updateApp(bundle)
        }
        onChange?()
    }

    private func updateArtwork(_ data: Data?) {
        guard let data, let image = Self.thumbnail(from: data, maxPixels: 256) else {
            artwork = nil
            accent = .white
            return
        }
        artwork = image
        accent = ArtworkPalette.accent(for: image)
    }

    /// Covers can be 3000 px (36 MB decoded); the island never needs more than 256.
    private static func thumbnail(from data: Data, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func updateApp(_ bundle: String) {
        bundleID = bundle
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            if let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                icon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
                NSGraphicsContext.restoreGraphicsState()
                let small = NSImage(size: NSSize(width: 32, height: 32))
                small.addRepresentation(rep)
                appIcon = small
            } else {
                appIcon = icon
            }
            appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            appIcon = nil
            appName = nil
        }
    }
}
