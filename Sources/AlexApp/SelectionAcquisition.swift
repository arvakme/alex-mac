import AlexCore
import AppKit

/// AX, then a temporary copy in the source app, then the existing first clipboard item.
@MainActor final class SelectionAcquisition {
    private var task: Task<Void, Never>?
    private let clipboard = ClipboardAccess()
    func cancel() { task?.cancel(); task = nil }
    func start(configuration: Configuration, deliver: @escaping (Result<CapturedSelection, SelectionFailure>) -> Void) {
        cancel()
        let source = NSWorkspace.shared.frontmostApplication?.processIdentifier
        task = Task {
            let result = await SelectionReader.capture()
            guard !Task.isCancelled else { return }
            // Without Accessibility alex cannot tell whether anything is selected, so the clipboard is no stand-in
            // for the selection; the permission notice is what the reader needs.
            if case .success = result { deliver(result); return }
            if case .failure(.permission) = result { deliver(result); return }
            if configuration.copySelectionFallback, let source, source != ProcessInfo.processInfo.processIdentifier,
               let text = await copySelection(from: source) {
                guard !Task.isCancelled else { return }
                deliver(.success(CapturedSelection(text: text, context: nil, anchor: NSEvent.mouseLocation))); return
            }
            guard !Task.isCancelled else { return }
            if configuration.clipboardFallback {
                let text = await clipboard.firstText()
                guard !Task.isCancelled else { return }
                switch text {
                case .success(let value):
                    DiagnosticLog.shared.record(.selectionClipboard, ["characters": value.utf16.count])
                    deliver(.success(CapturedSelection(text: value, context: nil, anchor: NSEvent.mouseLocation, fromClipboard: true)))
                case .failure(let failure): deliver(.failure(failure))
                }
            } else { deliver(result) }
        }
    }
    private func copySelection(from pid: pid_t) async -> String? {
        guard let saved = await clipboard.snapshot(), !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else {
            DiagnosticLog.shared.record(.copyUnavailable); return nil
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(pid); up.postToPid(pid)
        // NSPasteboard offers no change notification. Observe this one copy for at most 800ms, then release it.
        // Finish cleanup even if the acquisition is cancelled after the keystroke was posted.
        for _ in 0..<16 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { continuation.resume() }
            }
            if let copied = await clipboard.finishCopy(after: saved) {
                if case .success(let text) = copied {
                    DiagnosticLog.shared.record(.selectionCopy, ["characters": text.utf16.count]); return text
                }
                return nil
            }
        }
        DiagnosticLog.shared.record(.copyUnavailable); return nil
    }
}

/// Pasteboard data is materialized off the UI thread; only Sendable values cross the actor boundary.
actor ClipboardAccess {
    struct Snapshot: Sendable { let count: Int; let items: [[String: Data]] }
    func snapshot() -> Snapshot? {
        let board = NSPasteboard.general
        let count = board.changeCount
        var items: [[String: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var values: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                values[type.rawValue] = data
            }
            items.append(values)
        }
        guard count == board.changeCount else { return nil }
        return Snapshot(count: count, items: items)
    }
    func firstText() -> Result<String, SelectionFailure> {
        let board = NSPasteboard.general
        guard let item = board.pasteboardItems?.first else {
            DiagnosticLog.shared.record(.clipboardEmpty); return .failure(.clipboardEmpty)
        }
        guard let text = item.string(forType: .string) else {
            DiagnosticLog.shared.record(.clipboardNotText); return .failure(.clipboardNotText)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DiagnosticLog.shared.record(.clipboardEmpty); return .failure(.clipboardEmpty)
        }
        return .success(text)
    }
    func finishCopy(after saved: Snapshot) -> Result<String, SelectionFailure>? {
        let board = NSPasteboard.general
        let copiedCount = board.changeCount
        guard copiedCount != saved.count else { return nil }
        let result = firstText()
        guard board.changeCount == copiedCount else {
            DiagnosticLog.shared.record(.clipboardChanged); return .failure(.unavailable)
        }
        let items = saved.items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: .init(type)) }
            return item
        }
        board.clearContents()
        if !items.isEmpty, !board.writeObjects(items) {
            DiagnosticLog.shared.record(.clipboardChanged)
            return .failure(.unavailable)
        }
        return result
    }
}
