import AlexCore
import Foundation

@MainActor extension AppModel {
    func showHistory(_ show: Bool) {
        if show { history.prune(now: .now); persistHistory() }
        showingHistory = show
    }
    /// Replaces the panel's translation with a saved one, as it was, without asking the service again.
    /// The person chose this; back from here is the panel itself, and ⌘Y returns to the list.
    func open(_ entry: HistoryEntry) {
        stop()
        input = entry.source
        context = nil; fromClipboard = false
        source = .auto; target = entry.target; explicitTarget = true
        output = entry.output; phase = .complete
        restored = entry; showingHistory = false
    }
    func deleteHistory(_ id: HistoryEntry.ID) {
        history.remove(id)
        if restored?.id == id { restored = nil }
        persistHistory()
    }
    func clearHistory() {
        guard !history.entries.isEmpty else { return }
        history.removeAll(); restored = nil
        persistHistory()
    }
    func persistHistory() {
        do { try historyFile.save(history) }
        catch { settingsError = "翻译历史保存失败：\(error.localizedDescription)" }
    }
}
