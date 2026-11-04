import Foundation

public enum DiagnosticArchive {
    public static let stackLimit: UInt64 = 512 * 1024
    private static let week: TimeInterval = 7 * 24 * 60 * 60
    public static func pruneStacks(in directory: URL) throws {
        let files = try recentFiles(in: directory)
        for (index, file) in files.enumerated() where index >= 5 || modified(file).timeIntervalSinceNow < -week {
            try FileManager.default.removeItem(at: file)
        }
    }
    public static func export(version: String, revision: String, log: DiagnosticLog = .shared, downloads: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("alex-diagnostics-\(UUID().uuidString)")
        let root = temporary.appendingPathComponent("alex-diagnostics")
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temporary) }
        try log.snapshot(to: root.appendingPathComponent("logs"))
        var included: [String] = [], omitted: [String] = []
        let sources = [log.directory.appendingPathComponent("stacks"),
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"),
                       URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")]
        for (index, source) in sources.enumerated() {
            guard fm.fileExists(atPath: source.path) else { continue }
            let files = try recentFiles(in: source).filter { file in
                let name = file.lastPathComponent.lowercased()
                return modified(file).timeIntervalSinceNow >= -week &&
                    (index == 0 || ((name.hasPrefix("alex-") || name.hasPrefix("excuserfault_alex-")) &&
                        ["ips", "hang", "spin"].contains(file.pathExtension)))
            }.prefix(index == 0 ? 6 : 3)
            for file in files {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2 * 1024 * 1024 else { omitted.append(file.lastPathComponent); continue }
                let name = "\(index)-\(file.lastPathComponent)"
                try fm.copyItem(at: file, to: root.appendingPathComponent(name)); included.append(name)
            }
        }
        let metadata: [String: Any] = ["version": version, "revision": revision,
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "created": ISO8601DateFormatter().string(from: Date()), "included": included, "omittedOversized": omitted,
            "privacy": "Events contain only names and numeric metadata, no text, API keys or service URLs. System stacks may contain local paths.",
            "limits": "4 x 512KiB event logs; at most 6 bounded app stacks; latest 3 system reports per directory within 7 days.",
            "exit": "processExit records graceful exit only. SIGKILL/power loss cannot run application cleanup."]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("metadata.json"))
        let target = try downloads ?? fm.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let zip = target.appendingPathComponent("alex-diagnostics-\(stamp)-\(UUID().uuidString.prefix(6)).zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", root.path, zip.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? fm.removeItem(at: zip)
            throw CocoaError(.fileWriteUnknown)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: zip.path)
        log.record(.exportComplete)
        return zip
    }
    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    private static func recentFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { modified($0) > modified($1) }
    }
}
