/// A global key combination as Carbon registers it, plus the key's printed name captured when it was recorded.
public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
    public var modifiers: UInt32
    public var key: String

    public static let command: UInt32 = 1 << 8, shift: UInt32 = 1 << 9, option: UInt32 = 1 << 11, control: UInt32 = 1 << 12
    static let hyper = command | shift | option | control
    public static let defaultSelection = Shortcut(keyCode: 0x02, modifiers: hyper, key: "D")
    public static let defaultInput = Shortcut(keyCode: 0x11, modifiers: hyper, key: "T")

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }
    public var display: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + key
    }
}

public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case selection, input
    public var id: String { rawValue }
    public var title: String { self == .selection ? "划词翻译" : "输入翻译" }
    public var fallback: Shortcut { self == .selection ? .defaultSelection : .defaultInput }
}
