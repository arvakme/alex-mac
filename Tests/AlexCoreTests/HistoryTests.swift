import Foundation
import Testing
@testable import AlexCore

private func entry(_ source: String, _ output: String, at date: Date, target: Language = .chinese) -> HistoryEntry {
    HistoryEntry(date: date, source: source, output: output, sourceLanguage: .english, target: target, service: "magpie")
}

@Test func historyKeepsSevenDaysAndDropsOlderEntries() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400
    var history = TranslationHistory(entries: [
        entry("fresh", "新", at: now - 6.9 * day),
        entry("stale", "旧", at: now - 7.1 * day),
    ], now: now)
    #expect(history.entries.map(\.source) == ["fresh"])
    // The window moves with the clock: an entry that was inside it expires a day later.
    history.prune(now: now + day)
    #expect(history.entries.isEmpty)
}

@Test func translatingTheSameTextAgainMovesItToTheTopInsteadOfDuplicating() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var history = TranslationHistory(entries: [], now: now)
    history.add(entry("hello", "你好", at: now - 60), now: now)
    history.add(entry("world", "世界", at: now - 30), now: now)
    history.add(entry("hello", "您好", at: now), now: now)
    #expect(history.entries.map(\.output) == ["您好", "世界"])
    // Into another language it is a different translation and both are kept.
    history.add(entry("hello", "Hallo", at: now, target: .german), now: now)
    #expect(history.entries.count == 3)
}

@Test func searchMatchesSourceOrTranslationIgnoringCase() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let history = TranslationHistory(entries: [
        entry("Idempotent", "幂等的", at: now),
        entry("ephemeral", "短暂的", at: now - 10),
    ], now: now)
    #expect(history.matching("idem").map(\.output) == ["幂等的"])
    #expect(history.matching("短暂").map(\.source) == ["ephemeral"])
    #expect(history.matching("  ").count == 2)
}

@Test func historyFileRoundTripsAndIsReadableOnlyByItsOwner() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = HistoryFile(url: dir.appendingPathComponent("history.json"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(file.load(now: now).entries.isEmpty)
    var history = TranslationHistory(entries: [], now: now)
    history.add(entry("hello", "你好", at: now), now: now)
    try file.save(history)
    #expect(file.load(now: now).entries == history.entries)
    let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
}
