import Foundation

public enum DiagnosticEvent: String, Sendable {
    case processStart, processExit, selectionStart, selectionAX, selectionUnavailable, selectionCopy, selectionClipboard
    case clipboardEmpty, clipboardNotText, clipboardChanged, copyUnavailable
    case requestStart, requestFirstText, requestComplete, requestCancelled, requestTimeout, requestFailed, credentialFailed
    case mainThreadStall, mainThreadRecovered, stackCaptured, stackFailed, exportComplete, exportFailed
    case updateAvailable, updateCheckFailed, updateInstall, updateFailed
}

/// Numeric fields only: text, keys, request bodies and service addresses cannot enter the event log.
public final class DiagnosticLog: @unchecked Sendable {
    public static let shared = DiagnosticLog()
    public let directory: URL
    private let queue = DispatchQueue(label: "alex.diagnostics.log", qos: .utility)
    private let maximumBytes: Int
    private let generations = 3
    private let session = UUID().uuidString
    private var writeFailure: String?

    public init(directory: URL? = nil, maximumBytes: Int = 512 * 1024) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/alex", isDirectory: true)
        self.maximumBytes = maximumBytes
    }
    public func record(_ event: DiagnosticEvent, _ values: [String: Int] = [:]) {
        queue.async { self.write(event, values) }
    }
    public func flush() { queue.sync {} }
    public func snapshot(to destination: URL) throws {
        try queue.sync {
            if let writeFailure { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: writeFailure]) }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.pathExtension == "jsonl" {
                try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent(url.lastPathComponent))
            }
        }
    }
    private func write(_ event: DiagnosticEvent, _ values: [String: Int]) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let record: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "session": session,
                                         "pid": ProcessInfo.processInfo.processIdentifier, "event": event.rawValue, "values": values]
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]); data.append(10)
            let current = directory.appendingPathComponent("events.jsonl")
            if fm.fileExists(atPath: current.path) {
                let size = try fm.attributesOfItem(atPath: current.path)[.size] as? Int ?? 0
                if size + data.count > maximumBytes { try rotate() }
            }
            if !fm.fileExists(atPath: current.path) { try Data().write(to: current, options: .atomic) }
            let handle = try FileHandle(forWritingTo: current)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
            writeFailure = nil
        } catch {
            // Export surfaces storage failures instead of claiming that an empty report is a successful capture.
            writeFailure = "诊断日志无法写入（\((error as NSError).code)）。请检查磁盘空间和目录权限。"
        }
    }
    private func rotate() throws {
        let fm = FileManager.default
        for i in stride(from: generations, through: 1, by: -1) {
            let target = directory.appendingPathComponent("events-\(i).jsonl")
            if i == generations, fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            let source = directory.appendingPathComponent(i == 1 ? "events.jsonl" : "events-\(i - 1).jsonl")
            if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: target) }
        }
    }
}
