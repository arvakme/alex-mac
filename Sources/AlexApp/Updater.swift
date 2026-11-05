import AlexCore
import AppKit
import Observation
import Security

/// Finds a newer GitHub release and installs it in place of the running bundle.
///
/// Only the release variant updates itself. Its fixed self-signed certificate is the code identity macOS keeps the
/// Accessibility grant for, so an update is installed only when it satisfies the running copy's designated requirement.
@MainActor @Observable final class Updater {
    enum State: Equatable { case idle, checking, upToDate, available(ReleaseInfo), installing, failed(String) }
    static let releaseIdentifier = "com.kazelis.alex.release"
    private static let interval: Duration = .seconds(24 * 60 * 60)
    private static let firstCheckDelay: Duration = .seconds(10)

    var state: State = .idle
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    var isSupported: Bool { Bundle.main.bundleIdentifier == Self.releaseIdentifier }
    var available: ReleaseInfo? { if case .available(let release) = state { release } else { nil } }
    private var schedule: Task<Void, Never>?

    func startAutomaticChecks(enabled: Bool) {
        schedule?.cancel(); schedule = nil
        guard enabled, isSupported else { return }
        schedule = Task { [weak self] in
            try? await Task.sleep(for: Self.firstCheckDelay)
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func check() async {
        guard isSupported, state != .checking, state != .installing else { return }
        state = .checking
        do {
            let release = try await ReleaseFeed.fetchLatest()
            if ReleaseFeed.isNewer(release.version, than: currentVersion) {
                state = .available(release); DiagnosticLog.shared.record(.updateAvailable)
            } else { state = .upToDate }
        } catch {
            state = .failed("检查更新失败：" + error.localizedDescription); DiagnosticLog.shared.record(.updateCheckFailed)
        }
    }

    func install(_ release: ReleaseInfo) async {
        guard state != .installing else { return }
        state = .installing; DiagnosticLog.shared.record(.updateInstall)
        let current = Bundle.main.bundleURL
        do {
            // Same volume as the installed app, so the final swap is a rename.
            let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                   appropriateFor: current, create: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let archive = try await ReleaseFeed.download(release.archive, into: work)
            let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
            try await Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
            let app = unpacked.appendingPathComponent("Alex.app", isDirectory: true)
            try Self.verify(app, version: release.version)
            _ = try FileManager.default.replaceItemAt(current, withItemAt: app)
        } catch {
            state = .failed("更新没有安装：" + error.localizedDescription); DiagnosticLog.shared.record(.updateFailed)
            return
        }
        do { try relaunch(current) } catch {
            state = .failed("新版本已经装好，请退出 Alex 后重新打开。"); DiagnosticLog.shared.record(.updateFailed)
        }
    }

    private static func verify(_ app: URL, version: String) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleShortVersionString"] as? String == version,
              info?["CFBundleIdentifier"] as? String == releaseIdentifier else { throw UpdateError.wrongVersion }
        var running: SecCode?, runningStatic: SecStaticCode?, requirement: SecRequirement?, candidate: SecStaticCode?
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode))
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate,
              SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess
        else { throw UpdateError.signatureMismatch }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { $0.terminationStatus == 0 ? done.resume() : done.resume(throwing: UpdateError.unpackFailed) }
            do { try process.run() } catch { done.resume(throwing: error) }
        }
    }

    /// The new copy opens only after this process has exited, so two copies never hold the global shortcuts at once.
    private func relaunch(_ app: URL) throws {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                            "alex-relaunch", String(getpid()), app.path]
        try waiter.run()
        NSApp.terminate(nil)
    }
}
