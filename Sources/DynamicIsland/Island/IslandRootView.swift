import SwiftUI

struct IslandRootView: View {
    let model: IslandModel
    @Namespace private var ns

    static let expandSpring = Animation.spring(duration: 0.4, bounce: 0.24)
    static let settleSpring = Animation.spring(duration: 0.34, bounce: 0.12)

    var body: some View {
        let p = model.presentation
        let size = model.size(for: p)
        let radii = model.cornerRadii(for: p)
        let shape = IslandShape(topRadius: radii.top, bottomRadius: radii.bottom)
        let ui = UIScale(unit: model.geometry.unit)

        ZStack(alignment: .top) {
            content(for: p)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { model.handleTap() }
        .contextMenu { contextMenu }
        .opacity(p == .idle && model.hidesWhenIdle ? 0 : 1)
        .animation(p == .expanded ? Self.expandSpring : Self.settleSpring, value: model.layoutKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.ui, ui)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(for p: Presentation) -> some View {
        let size = model.contentSize(for: p)
        switch p {
        case .idle:
            Color.clear
        case .compact(.music):
            CompactMusicView(nowPlaying: model.nowPlaying, ns: ns, notchGap: model.geometry.earGap)
                .frame(width: size.width, height: size.height)
                .transition(.islandContent)
        case .compact(.timer):
            CompactTimerView(timer: model.timer, nowPlaying: nil, ns: ns, notchGap: model.geometry.earGap)
                .frame(width: size.width, height: size.height)
                .transition(.islandContent)
        case .compact(.musicAndTimer):
            CompactTimerView(timer: model.timer, nowPlaying: model.nowPlaying, ns: ns, notchGap: model.geometry.earGap)
                .frame(width: size.width, height: size.height)
                .transition(.islandContent)
        case .compact(.charging):
            CompactChargingView(battery: model.battery, notchGap: model.geometry.earGap)
                .frame(width: size.width, height: size.height)
                .transition(.islandContent)
        case .hud(let hud):
            HUDView(hud: hud, model: model)
                .frame(width: size.width, height: size.height)
                .id(hud.kind)
                .transition(.islandContent)
        case .expanded:
            ExpandedView(model: model, ns: ns)
                .frame(width: size.width, height: size.height, alignment: .top)
                .transition(.islandExpandedContent)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Settings…") { NotificationCenter.default.post(name: .openIslandSettings, object: nil) }
        Divider()
        Button("Quit Dynamic Island") { NSApp.terminate(nil) }
    }
}

// MARK: - Content transition

/// No scaling here on purpose: the shape already moves, and scaling the content
/// as well fights the matched artwork and looks wobbly.
private struct SoftFocus: ViewModifier {
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SoftFocus(blur: 6, opacity: 0),
                identity: SoftFocus(blur: 0, opacity: 1)
            )
            .animation(.easeOut(duration: 0.26).delay(0.06)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }

    /// Blurring the whole expanded panel is expensive, so it only fades.
    static var islandExpandedContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.24).delay(0.06)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }
}
