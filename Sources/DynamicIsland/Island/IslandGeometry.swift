import AppKit
import SwiftUI

/// Where the island lives on screen and how big one "unit" is.
///
/// All layout constants are written for a 32pt-tall notch (a MacBook at default
/// scaling) and multiplied by `unit`, so the island keeps the same physical
/// proportions at any display scaling.
struct IslandGeometry: Equatable {
    var centerX: CGFloat
    var screenTop: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool
    var unit: CGFloat

    static let placeholder = IslandGeometry(
        centerX: 0, screenTop: 0, notchWidth: 185, notchHeight: 32, hasNotch: false, unit: 1
    )

    init(centerX: CGFloat, screenTop: CGFloat, notchWidth: CGFloat, notchHeight: CGFloat, hasNotch: Bool, unit: CGFloat) {
        self.centerX = centerX
        self.screenTop = screenTop
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.hasNotch = hasNotch
        self.unit = unit
    }

    init(screen: NSScreen, sizeScale: Double) {
        let frame = screen.frame
        centerX = frame.midX
        screenTop = frame.maxY
        let scale = CGFloat(min(max(sizeScale, 0.7), 1.5))

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchHeight = screen.safeAreaInsets.top
            notchWidth = max(right.minX - left.maxX, notchHeight * 4)
            // Follow the notch, but only partly: at "More Space" scalings the notch is
            // huge in points while the rest of the UI stays small.
            unit = min(max(notchHeight / 32, 0.9), 1.25) * scale
        } else {
            hasNotch = false
            let menuBar = frame.maxY - screen.visibleFrame.maxY
            notchHeight = menuBar > 4 ? menuBar : NSStatusBar.system.thickness
            unit = min(max(notchHeight / 28, 0.8), 3) * scale
            notchWidth = 170 * unit
        }
    }
}

/// `ui(14)` → 14 points scaled to the current display.
struct UIScale {
    var unit: CGFloat
    func callAsFunction(_ value: CGFloat) -> CGFloat { value * unit }
}

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue = UIScale(unit: 1)
}

extension EnvironmentValues {
    var ui: UIScale {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

/// Base layout metrics (multiplied by `IslandGeometry.unit`).
enum Layout {
    // Compact "ears" on each side of the notch.
    static let musicEar: CGFloat = 40
    static let timerEar: CGFloat = 54
    static let volumeEar: CGFloat = 86
    static let batteryEar: CGFloat = 76
    static let bannerEar: CGFloat = 66
    static let bannerExtra: CGFloat = 28

    // Expanded island.
    static let expandedWidth: CGFloat = 400
    static let expandedMinEar: CGFloat = 92
    static let sidePadding: CGFloat = 18
    static let playerHeight: CGFloat = 128
    static let placeholderHeight: CGFloat = 64
    static let timerRowHeight: CGFloat = 54
    static let presetsHeight: CGFloat = 40
    static let bottomPadding: CGFloat = 10

    // Timer finished alert.
    static let alertWidth: CGFloat = 340
    static let alertExtra: CGFloat = 56

    // Hover nudge (only used when hover doesn't expand).
    static let hoverGrowX: CGFloat = 8
    static let hoverGrowY: CGFloat = 2
}
