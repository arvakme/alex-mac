import AppKit
import SwiftUI

enum OnboardingStyle {
    /// The cobalt of the app icon; the onboarding keeps it whatever the system accent is.
    static let blue = Color(red: 10 / 255, green: 100 / 255, blue: 216 / 255)
}

@MainActor @Observable final class WelcomeState { var authorized = SelectionReader.authorized }

/// First-run welcome: allow Accessibility, then set up the translation service.
/// Shown at launch while a step is missing, until the user chooses "稍后".
@MainActor final class Onboarding {
    private static let deferredKey = "onboardingDeferred"
    private let model: AppModel
    private let openService: () -> Void
    private let finished: () -> Void
    private let state = WelcomeState()
    private var window: TranslationPanel?
    private var poll: Timer?

    init(model: AppModel, openService: @escaping () -> Void, finished: @escaping () -> Void) {
        self.model = model; self.openService = openService; self.finished = finished
    }

    /// Returns whether the welcome window took the launch.
    func showIfNeeded() -> Bool {
        guard !(SelectionReader.authorized && model.keySaved), !UserDefaults.standard.bool(forKey: Self.deferredKey) else { return false }
        show(); return true
    }

    func show() {
        state.authorized = SelectionReader.authorized
        let window = self.window ?? makeWindow()
        self.window = window
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, SelectionReader.authorized != self.state.authorized else { return }
                self.state.authorized = SelectionReader.authorized
            }
        }
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> TranslationPanel {
        let view = WelcomeView(model: model, state: state, primary: { [weak self] in self?.primary() },
                               later: { [weak self] in self?.later() }, done: { [weak self] in self?.complete() })
        let host = NSHostingView(rootView: view)
        let window = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("alex.welcome")
        window.title = "欢迎使用 Alex"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = host
        window.onClose = { [weak self] in self?.later() }
        return window
    }

    private func primary() {
        if !state.authorized {
            let frame = window?.frame ?? .zero
            // The primary button: full width, 44 pt tall, above the 32 pt "稍后" and the bottom padding.
            let button = NSRect(x: frame.minX + 32, y: frame.minY + 66, width: frame.width - 64, height: 44)
            PermissionGuide.shared.start(from: button) { [weak self] granted in
                guard granted, let self else { return }
                self.state.authorized = true
                NSApp.activate()
                self.window?.makeKeyAndOrderFront(nil)
            }
        } else {
            openService()
        }
    }

    private func later() {
        UserDefaults.standard.set(true, forKey: Self.deferredKey)
        close()
    }

    private func complete() {
        guard let window else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduce ? 0.15 : 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { [weak self] in
            self?.close()
            self?.finished()
        } })
    }

    private func close() {
        poll?.invalidate(); poll = nil
        window?.orderOut(nil); window = nil
    }

    /// From a disk image or a translocated copy the grant would belong to a copy that soon disappears.
    static func offerMoveToApplications() {
        let source = Bundle.main.bundleURL
        guard source.path.hasPrefix("/Volumes/") || source.path.contains("/AppTranslocation/") else { return }
        let alert = NSAlert()
        alert.messageText = "移到“应用程序”文件夹？"
        alert.informativeText = "直接从安装盘打开的 Alex 会在推出后消失，授权也要重新给。移过去后会自动重新打开。"
        alert.addButton(withTitle: "移到应用程序")
        alert.addButton(withTitle: "暂不")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.trashItem(at: target, resultingItemURL: nil) }
            try FileManager.default.copyItem(at: source, to: target)
            // A quarantined copy would be translocated again on its next launch.
            removexattr(target.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

private struct WelcomeView: View {
    let model: AppModel
    let state: WelcomeState
    let primary: () -> Void
    let later: () -> Void
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var stepTwoIn = true

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                .offset(y: shown || reduceMotion ? 0 : 14).scaleEffect(shown || reduceMotion ? 1 : 0.92).opacity(shown ? 1 : 0)
                .accessibilityHidden(true)
            Text("欢迎使用 Alex").font(.system(size: 24, weight: .bold)).padding(.top, 6).modifier(Rise(shown, 0))
            Text(state.authorized ? "还差一步。" : "选中任何文字，按一下快捷键就能翻译。\n还差两步就能用。")
                .font(.system(size: 14)).lineSpacing(4).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(TranslationPanelStyle.secondaryText).modifier(Rise(shown, 1))
            VStack(spacing: 0) {
                step(1, "允许辅助功能", detail: state.authorized ? "已授权" : "读取你选中的文字，不读其他内容", done: state.authorized)
                Divider().padding(.horizontal, 16)
                step(2, "填写翻译服务", detail: "API Key 只存在钥匙串", done: false)
                    .background(state.authorized ? OnboardingStyle.blue.opacity(0.06) : .clear)
                    .offset(x: stepTwoIn ? 0 : 18).opacity(stepTwoIn ? 1 : 0)
            }
            .clipShape(.rect(cornerRadius: 16))
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black.opacity(0.08)))
            .padding(.top, 6).modifier(Rise(shown, 2))
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button(action: primary) {
                    Text(state.authorized ? "设置翻译服务" : "打开系统设置授权").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                        .background(OnboardingStyle.blue, in: .capsule).contentShape(.capsule)
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                Button("稍后", action: later).buttonStyle(.plain).font(.system(size: 13))
                    .foregroundStyle(TranslationPanelStyle.secondaryText).frame(height: 32)
                    .keyboardShortcut(.cancelAction)
            }.modifier(Rise(shown, 3))
        }
        .padding(EdgeInsets(top: 36, leading: 32, bottom: 26, trailing: 32))
        .frame(width: 440, height: 480)
        .modifier(Surface(radius: TranslationPanelStyle.cornerRadius))
        .environment(\.riseMotion, !reduceMotion)
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.7, bounce: 0.2)) { shown = true } }
        .onChange(of: state.authorized) { _, authorized in
            guard authorized else { return }
            stepTwoIn = false
            withAnimation(reduceMotion ? .easeOut(duration: 0.2).delay(0.3) : .easeOut(duration: 0.4).delay(0.5)) { stepTwoIn = true }
            if model.keySaved { done() }
        }
        .onChange(of: model.keySaved) { _, saved in if saved && state.authorized { done() } }
    }

    private func step(_ number: Int, _ title: String, detail: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(.white, .green)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .bold)).frame(width: 26, height: 26)
                        .foregroundStyle(isCurrent(number) ? .white : .secondary)
                        .background(isCurrent(number) ? OnboardingStyle.blue : Color.secondary.opacity(0.15), in: .circle)
                }
            }
            .frame(width: 26, height: 26)
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.3), value: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).strikethrough(done)
                    .foregroundStyle(done ? TranslationPanelStyle.secondaryText : .primary)
                Text(detail).font(.system(size: 12)).foregroundStyle(done ? .green : TranslationPanelStyle.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(number) 步：\(title)，\(done ? "已完成" : detail)")
    }

    private func isCurrent(_ number: Int) -> Bool { number == (state.authorized ? 2 : 1) }
}

/// The translation panel's surface: window colour over glass, clipped to the shape.
struct Surface: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : TranslationPanelStyle.surfaceOpacity),
                        in: .rect(cornerRadius: radius))
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
            .clipShape(.rect(cornerRadius: radius))
    }
}

private extension EnvironmentValues { @Entry var riseMotion = true }

/// The staggered fade-in of the welcome rows, 0.1 s apart after the icon.
private struct Rise: ViewModifier {
    let shown: Bool, index: Int
    @Environment(\.riseMotion) private var motion
    init(_ shown: Bool, _ index: Int) { self.shown = shown; self.index = index }
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown || !motion ? 0 : 8)
            .animation(.easeOut(duration: 0.5).delay(0.25 + 0.1 * Double(index)), value: shown)
    }
}
