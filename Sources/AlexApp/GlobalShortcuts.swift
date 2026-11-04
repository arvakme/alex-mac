import AlexCore
import Carbon
import Foundation

/// Carbon global hot keys. The handler is installed once; key registrations change whenever settings do.
@MainActor final class GlobalShortcuts {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private static let signature: OSType = 0x414C4558
    var action: ((ShortcutAction) -> Void)?

    func install() -> OSStatus {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            MainActor.assumeIsolated {
                let target = id.id == 1 ? ShortcutAction.selection : .input
                Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue().action?(target)
            }
            return noErr
        }, 1, &type, context, &handler)
    }
    /// Replaces every registration; returns the actions whose combination the system refused.
    func register(_ shortcuts: [(ShortcutAction, Shortcut)]) -> [ShortcutAction: OSStatus] {
        unregisterKeys()
        var failures: [ShortcutAction: OSStatus] = [:]
        for (action, shortcut) in shortcuts {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action == .selection ? 1 : 2)
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references.append(reference) } else { failures[action] = status }
        }
        return failures
    }
    /// Releases the keys so a recorder can receive the combination currently in use.
    func unregisterKeys() {
        references.forEach { UnregisterEventHotKey($0) }; references.removeAll()
    }
    func remove() {
        unregisterKeys()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    /// True when an enabled system shortcut (Spotlight, input sources, screenshots…) already uses the combination.
    static func systemUses(_ shortcut: Shortcut) -> Bool {
        var raw: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&raw) == noErr, let list = raw?.takeRetainedValue() as? [[String: Any]] else { return false }
        return list.contains { entry in
            (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (entry[kHISymbolicHotKeyCode as String] as? Int).map(UInt32.init) == shortcut.keyCode
                && (entry[kHISymbolicHotKeyModifiers as String] as? Int).map(UInt32.init) == shortcut.modifiers
        }
    }
}
