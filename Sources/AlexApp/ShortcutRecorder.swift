import AlexCore
import AppKit
import SwiftUI

/// Shows an action's combination; clicking it listens for the next key press and saves it through the model.
struct ShortcutRecorder: View {
    @Bindable var model: AppModel
    let action: ShortcutAction
    /// Receives why a recording was refused, or nil once a combination is saved or recording starts.
    var report: (String?) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button { monitor == nil ? start() : stop() } label: {
            Text(monitor == nil ? model.configuration.shortcut(for: action).display : "请按下快捷键…")
                .frame(minWidth: 96)
        }
        .accessibilityLabel("\(action.title)快捷键")
        .accessibilityValue(monitor == nil ? model.configuration.shortcut(for: action).display : "正在录制")
        .onDisappear(perform: stop)
        // Keys pressed in another app never reach this window; leaving must not keep global shortcuts paused.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
        .onChange(of: model.configuration.shortcut(for: action)) { stop() }
    }
    private func start() {
        report(nil)
        model.pauseShortcuts()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }
    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        model.resumeShortcuts()
    }
    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == Self.escape, modifiers.isEmpty { stop(); return }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else {
            report("组合里至少要有 ⌘、⌃ 或 ⌥。"); return
        }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers.carbon, key: Self.name(of: event))
        stop()
        report(model.setShortcut(shortcut, for: action))
    }

    private static let escape: UInt16 = 53
    private static let special: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
    ]
    /// The key's name on the current layout without modifiers, so ⇧ or ⌥ do not turn D into a symbol.
    private static func name(of event: NSEvent) -> String {
        special[event.keyCode] ?? (event.characters(byApplyingModifiers: []) ?? "?").uppercased()
    }
}
