import AppKit
import SwiftUI

@MainActor @Observable final class GuideState { var granted = false }

/// The small panel that sits beside System Settings while the user grants Accessibility.
/// It follows the Settings window, polls the grant every 0.5 s, and leaves when Settings closes or the grant arrives.
@MainActor final class PermissionGuide {
    static let shared = PermissionGuide()
    private var panel: TranslationPanel?
    private var state = GuideState()
    private var timers: [Timer] = []
    private var completion: ((Bool) -> Void)?
    private var origin: NSRect?
    private var started = Date.now
    private var attached = false, flying = false, placed = false
    private var lostSince: Date?

    /// Opens the Accessibility page and shows the guide, flying out of `origin` (a screen rect) when given.
    func start(from origin: NSRect? = nil, completion: ((Bool) -> Void)? = nil) {
        SelectionReader.openAccessibilitySettings()
        self.completion = completion
        guard panel == nil else { return }
        self.origin = origin
        state = GuideState()
        started = .now; attached = false; flying = false; placed = false; lostSince = nil
        let host = NSHostingView(rootView: GuideView(state: state, close: { [weak self] in self?.finish(granted: false) }))
        let size = host.fittingSize
        let panel = TranslationPanel(contentRect: NSRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("alex.permission-guide")
        panel.title = "alex 授权引导"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = host
        panel.alphaValue = 0
        panel.onClose = { [weak self] in self?.finish(granted: false) }
        self.panel = panel
        timers = [
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow() }
            },
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if SelectionReader.authorized { self?.granted() } }
            },
        ]
    }

    private func follow() {
        guard let panel, !flying else { return }
        if let settings = Self.settingsFrame() {
            lostSince = nil; attached = true
            let target = Self.place(panel.frame.size, beside: settings)
            if placed { panel.setFrameOrigin(target.origin) } else { reveal(at: target) }
        } else if attached, !state.granted {
            // Settings closed (or left the screen) for a moment longer than a window switch takes.
            if let lostSince, Date.now.timeIntervalSince(lostSince) > 0.4 { finish(granted: false) }
            else if lostSince == nil { lostSince = .now }
        } else if !placed, Date.now.timeIntervalSince(started) > 2.5, let screen = NSScreen.main?.visibleFrame {
            // Settings never showed up where we can see it; stay useful in the middle of the screen.
            let size = panel.frame.size
            reveal(at: NSRect(x: screen.midX + 120, y: screen.midY - size.height / 2, width: size.width, height: size.height))
        }
    }

    private func reveal(at target: NSRect) {
        guard let panel else { return }
        placed = true
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let origin, !reduce {
            panel.setFrame(NSRect(x: origin.midX - target.width / 2, y: origin.midY - target.height / 2,
                                  width: target.width, height: target.height), display: false)
        } else {
            panel.setFrame(target, display: false)
        }
        panel.orderFrontRegardless()
        flying = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.55
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { MainActor.assumeIsolated { [weak self] in self?.flying = false } })
    }

    private func granted() {
        guard !state.granted else { return }
        state.granted = true
        timers.forEach { $0.invalidate() }; timers = []
        if panel?.isVisible != true { finish(granted: true); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 + 1.2) { [weak self] in
            guard let self, let panel = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { [weak self] in self?.finish(granted: true) } })
        }
    }

    private func finish(granted: Bool) {
        timers.forEach { $0.invalidate() }; timers = []
        panel?.orderOut(nil); panel = nil
        let completion = completion
        self.completion = nil
        completion?(granted)
    }

    /// Right of Settings near its top; left of it when the right side is off screen.
    static func place(_ size: NSSize, beside settings: NSRect) -> NSRect {
        let screen = (NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main)?.visibleFrame ?? settings
        var x = settings.maxX + 14
        if x + size.width > screen.maxX { x = settings.minX - 14 - size.width }
        if x < screen.minX { x = settings.maxX - size.width - 14 }
        let y = min(max(settings.maxY - 72 - size.height, screen.minY), screen.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The frontmost on-screen System Settings window in Cocoa coordinates. Bounds need no screen-recording grant.
    static func settingsFrame() -> NSRect? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .map(\.processIdentifier))
        guard !pids.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                                     kCGNullWindowID) as? [[String: Any]] else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for info in windows {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 300 else { continue }
            return NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }
}

private struct GuideView: View {
    let state: GuideState
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            if state.granted { granted.transition(.scale(scale: 0.6).combined(with: .opacity)) } else { waiting }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: state.granted)
        .padding(16).frame(width: 270)
        .modifier(Surface(radius: 22))
        .scaleEffect(shown || reduceMotion ? 1 : 0.4)
        .onAppear { withAnimation(.spring(duration: 0.55, bounce: 0)) { shown = true } }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("把 Alex 拖进左边的列表").font(.system(size: 13, weight: .bold))
                Spacer()
                Button("关闭引导", systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.plain)
                    .foregroundStyle(TranslationPanelStyle.secondaryText)
            }
            VStack(spacing: 0) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    GuideDemo(t: reduceMotion ? 0.95 : context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 4.2) / 4.2)
                }
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 14))
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    Text("等待授权")
                    ForEach(0..<3, id: \.self) { index in
                        Text("·").opacity(reduceMotion ? 1 : 0.35 + 0.65 * (0.5 + 0.5 * sin((time - Double(index) * 0.2) * .pi / 0.6)))
                    }
                }
            }
            .font(.system(size: 12)).foregroundStyle(TranslationPanelStyle.secondaryText)
            .accessibilityElement(children: .ignore).accessibilityLabel("等待授权")
        }
    }

    private var granted: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.white, .green)
            Text("已授权").font(.system(size: 14, weight: .bold))
            Text("可以关掉系统设置了").font(.system(size: 12)).foregroundStyle(TranslationPanelStyle.secondaryText)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One frame of the 4.2 s loop: the icon slides into a list row, the row fills in and its switch turns on.
/// The real icon stays in its well so it can be dragged; the moving one is a drag-image look-alike.
private struct GuideDemo: View {
    let t: Double
    private static let width: CGFloat = 214, well: CGFloat = 56, rowY: CGFloat = 112, icon: CGFloat = 22

    var body: some View {
        let move = Self.ease(Self.segment(t, 0.12, 0.55))
        let from = CGPoint(x: Self.width / 2, y: Self.well / 2), to = CGPoint(x: 23, y: Self.rowY)
        let on = Self.ease(Self.segment(t, 0.82, 0.90))
        let ring = Self.segment(t, 0.82, 1)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: Self.well, height: Self.well).position(from)
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: Self.well, height: Self.well).position(from)
                .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                .help("拖到系统设置的辅助功能列表里")
                .accessibilityLabel("Alex 应用图标，可拖动")
            Text("按住图标拖过去，再打开开关").font(.system(size: 12)).foregroundStyle(TranslationPanelStyle.secondaryText)
                .position(x: Self.width / 2, y: Self.well + 18)
            RoundedRectangle(cornerRadius: 8).strokeBorder(OnboardingStyle.blue, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .background(OnboardingStyle.blue.opacity(0.06), in: .rect(cornerRadius: 8))
                .frame(width: Self.width, height: 36).position(x: Self.width / 2, y: Self.rowY)
                .opacity(t < 0.70 ? Self.segment(t, 0.12, 0.2) : 0)
            row(on: on, ring: ring).opacity(Self.segment(t, 0.70, 0.80))
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: Self.well, height: Self.well)
                .scaleEffect(1 + (Self.icon / Self.well - 1) * move)
                .position(x: from.x + (to.x - from.x) * move, y: from.y + (to.y - from.y) * move)
                .opacity(t >= 0.12 && t < 0.70 ? 0.9 : 0).allowsHitTesting(false)
        }
        .frame(width: Self.width, height: Self.rowY + 18)
        .accessibilityElement(children: .contain)
    }

    private func row(on: Double, ring: Double) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: Self.icon, height: Self.icon)
            Text("Alex").font(.system(size: 12, weight: .semibold))
            Spacer()
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.82).mix(with: OnboardingStyle.blue, by: on)).frame(width: 30, height: 17)
                Circle().fill(.white).shadow(radius: 0.5, y: 0.5).frame(width: 13, height: 13).offset(x: 2 + 13 * on)
            }
            .background(Capsule().stroke(OnboardingStyle.blue.opacity(ring == 0 ? 0 : 0.35 * (1 - ring)), lineWidth: 6 * ring)
                .scaleEffect(1 + 0.3 * ring))
        }
        .padding(.horizontal, 12).frame(width: Self.width, height: 36)
        .background(OnboardingStyle.blue.opacity(0.06), in: .rect(cornerRadius: 8))
        .position(x: Self.width / 2, y: Self.rowY)
        .accessibilityHidden(true)
    }

    static func segment(_ t: Double, _ start: Double, _ end: Double) -> Double { min(max((t - start) / (end - start), 0), 1) }
    static func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}
