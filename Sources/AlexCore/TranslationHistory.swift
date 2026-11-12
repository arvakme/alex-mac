import Foundation

/// One finished translation. Holds the texts the person already saw; never the context read around a selection.
public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var source: String
    public var output: String
    public var sourceLanguage: Language
    public var target: Language
    public var service: String

    public init(date: Date, source: String, output: String, sourceLanguage: Language, target: Language, service: String) {
        self.date = date; self.source = source; self.output = output
        self.sourceLanguage = sourceLanguage; self.target = target; self.service = service
    }
}

/// Finished translations of the last seven days, newest first.
public struct TranslationHistory: Equatable, Sendable {
    public static let retention: TimeInterval = 7 * 86_400
    public private(set) var entries: [HistoryEntry]

    public init(entries: [HistoryEntry], now: Date) {
        self.entries = entries.sorted { $0.date > $1.date }
        prune(now: now)
    }
    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.date) > Self.retention }
    }
    /// The same text into the same language replaces its earlier translation, so retries do not pile up.
    public mutating func add(_ entry: HistoryEntry, now: Date) {
        entries.removeAll { $0.source == entry.source && $0.target == entry.target }
        entries.insert(entry, at: 0)
        prune(now: now)
    }
    public mutating func remove(_ id: HistoryEntry.ID) { entries.removeAll { $0.id == id } }
    public mutating func removeAll() { entries.removeAll() }
    public func matching(_ query: String) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.source.localizedCaseInsensitiveContains(query) || $0.output.localizedCaseInsensitiveContains(query) }
    }
}

/// The history on disk, readable only by the person who owns the file.
public struct HistoryFile: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    /// A missing or unreadable file is an empty history; old entries are dropped on the way in.
    public func load(now: Date) -> TranslationHistory {
        let entries = (try? JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: url))) ?? []
        return TranslationHistory(entries: entries, now: now)
    }
    public func save(_ history: TranslationHistory) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history.entries).write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
