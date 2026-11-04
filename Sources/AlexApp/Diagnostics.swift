import AlexCore
import AppKit

/// One outstanding main-queue heartbeat; the utility queue can sample even while the UI is blocked.
final class StallMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "alex.diagnostics.watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pendingSince: TimeInterval?
    private var reported = false
    private var sampler: Process?
    private static let threshold: TimeInterval = 2

    func start() {
        queue.async {
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500))
            timer.setEventHandler { self.tick() }
            self.timer = timer; timer.resume()
        }
    }
    func stop() {
        queue.sync {
            timer?.cancel(); timer = nil
            if let sampler, sampler.isRunning { sampler.terminate() }
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let since = pendingSince {
            if now - since >= Self.threshold, !reported {
                reported = true
                DiagnosticLog.shared.record(.mainThreadStall, ["milliseconds": Int((now - since) * 1000)])
                captureStack()
            }
            return
        }
        pendingSince = now
        DispatchQueue.main.async {
            let recovered = ProcessInfo.processInfo.systemUptime
            self.queue.async {
                if self.reported, let since = self.pendingSince {
                    DiagnosticLog.shared.record(.mainThreadRecovered, ["milliseconds": Int((recovered - since) * 1000)])
                }
                self.pendingSince = nil; self.reported = false
            }
        }
    }
    private func captureStack() {
        guard sampler == nil else { return }
        do {
            let dir = DiagnosticLog.shared.directory.appendingPathComponent("stacks")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try DiagnosticArchive.pruneStacks(in: dir)
            let file = dir.appendingPathComponent("stall-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).txt")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = [String(ProcessInfo.processInfo.processIdentifier), "1", "1", "-file", file.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                self.queue.async {
                    do {
                        if FileManager.default.fileExists(atPath: file.path) {
                            let handle = try FileHandle(forWritingTo: file)
                            defer { try? handle.close() }
                            if try handle.seekToEnd() > DiagnosticArchive.stackLimit {
                                try handle.truncate(atOffset: DiagnosticArchive.stackLimit)
                            }
                        }
                        DiagnosticLog.shared.record(process.terminationStatus == 0 ? .stackCaptured : .stackFailed,
                                                    ["code": Int(process.terminationStatus)])
                    } catch { DiagnosticLog.shared.record(.stackFailed, ["code": (error as NSError).code]) }
                    self.sampler = nil
                }
            }
            try process.run(); sampler = process
        } catch { DiagnosticLog.shared.record(.stackFailed, ["code": (error as NSError).code]) }
    }
}

@MainActor extension AppModel {
    func exportDiagnostics() {
        guard !exportingDiagnostics else { return }
        exportingDiagnostics = true; diagnosticStatus = "正在整理诊断报告…"
        Task {
            do {
                let info = Bundle.main.infoDictionary ?? [:]
                let version = info["CFBundleShortVersionString"] as? String ?? "development"
                let revision = info["AlexRevision"] as? String ?? "development"
                let url = try await Task.detached(priority: .utility) {
                    try DiagnosticArchive.export(version: version, revision: revision)
                }.value
                diagnosticStatus = "已导出到下载文件夹"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                DiagnosticLog.shared.record(.exportFailed, ["code": (error as NSError).code])
                diagnosticStatus = "导出失败：\(error.localizedDescription)"
            }
            exportingDiagnostics = false
        }
    }
}
