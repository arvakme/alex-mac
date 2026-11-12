import AppKit
import AVFoundation
import AlexCore
import Observation

@MainActor @Observable final class AppModel {
    enum Phase: Equatable { case idle, streaming, complete, stopped, failed(String), noSelection(SelectionFailure) }
    var input = "" {
        didSet {
            guard input != oldValue else { return }
            invalidate(); context = nil; fromClipboard = false
            // Recognition loads a language model; the header reads the result on every redraw.
            recognized = Language.detected(in: input)
        }
    }
    private var recognized: Language?
    /// The source text came from the clipboard fallback, not from the selection.
    var fromClipboard = false
    var output = ""
    var context: String?
    var source: Language = .auto
    var target: Language = .chinese
    var pinned = false
    var presentation: PanelPresentation = .floating
    var phase: Phase = .idle
    var configuration = Configuration()
    var settingsError: String?
    var diagnosticStatus = "日志只记录事件和长度，不记录原文、译文或密钥。"
    var exportingDiagnostics = false
    var connectionStatus = "尚未测试"
    var testingConnection = false
    /// Why a shortcut is not working, by action; empty when both are registered.
    var shortcutIssues: [ShortcutAction: String] = [:]
    var keySaved = false
    var explicitTarget = false
    var elapsed: TimeInterval = 0
    var history = TranslationHistory(entries: [], now: .now)
    var showingHistory = false
    /// The translation on screen was reopened from history, not requested now.
    var restored: HistoryEntry?
    let historyFile = HistoryFile(url: URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "com.kazelis.alex").appending(path: "history.json"))
    private var requestID = UUID()
    private var task: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    /// Keyed by bundle id, so a release copy on a development Mac never reads, or prompts for, the development key.
    private let credentials = CredentialStore(service: (Bundle.main.bundleIdentifier ?? "com.kazelis.alex") + ".translation")
    private let defaults = UserDefaults.standard
    private let speech = AVSpeechSynthesizer()
    private let shortcuts = GlobalShortcuts()
    let updater = Updater()

    init() {
        if let data = defaults.data(forKey: "configuration") {
            do { configuration = try JSONDecoder().decode(Configuration.self, from: data) }
            catch { settingsError = "保存的设置无法读取，请检查并重新保存。" }
        }
        target = configuration.target
        history = historyFile.load(now: .now)
        refreshKeyStatus()
    }
    var isStreaming: Bool { phase == .streaming }
    var isTerm: Bool { input.split(whereSeparator: { $0.isWhitespace }).count <= 4 && input.count < 60 }
    var detectedSource: Language? { source == .auto ? recognized : source }

    func saveConfiguration(_ value: Configuration) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: "configuration")
            let updatesChanged = value.checkForUpdates != configuration.checkForUpdates
            configuration = value
            if updatesChanged { updater.startAutomaticChecks(enabled: value.checkForUpdates) }
            if !value.saveHistory { clearHistory() }
            settingsError = nil
        } catch { settingsError = "设置保存失败，请重试。" }
    }
    func saveKey(_ key: String) -> Bool {
        do { try credentials.save(key); refreshKeyStatus(); settingsError = nil; return true }
        catch { settingsError = error.localizedDescription; return false }
    }
    func refreshKeyStatus() {
        do { keySaved = try credentials.read() != nil }
        catch { keySaved = false; settingsError = error.localizedDescription }
    }
    func prepare(text: String = "", context: String? = nil, fromClipboard: Bool = false) {
        stop()
        input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.context = context
        self.fromClipboard = fromClipboard
        output = ""
        source = .auto
        target = configuration.target
        explicitTarget = false
        phase = .idle
        restored = nil; showingHistory = false
    }
    func invalidate() {
        if isStreaming { DiagnosticLog.shared.record(.requestCancelled, ["received": output.utf16.count]) }
        task?.cancel(); task = nil; requestID = UUID()
        output = ""; phase = .idle; restored = nil
    }
    func stop() {
        task?.cancel(); task = nil; requestID = UUID()
        if isStreaming {
            DiagnosticLog.shared.record(.requestCancelled, ["received": output.utf16.count])
            phase = .stopped
        }
        speech.stopSpeaking(at: .immediate)
    }
    func translate() {
        invalidate()
        // Translating into the language the text is already in is never wanted unless the person picked it.
        if !explicitTarget, let detected = detectedSource, detected == target {
            target = detected == .chinese ? configuration.chineseTarget : .chinese
        }
        let key: String
        do { key = try credentials.read() ?? "" }
        catch {
            DiagnosticLog.shared.record(.credentialFailed, ["code": (error as NSError).code])
            phase = .failed(error.localizedDescription); return
        }
        let id = requestID
        let text = input, context = context, source = source, target = target, config = configuration
        let sourceLanguage = detectedSource ?? source
        phase = .streaming
        DiagnosticLog.shared.record(.requestStart, ["characters": text.utf16.count, "context": context?.utf16.count ?? 0])
        let start = Date()
        task = Task { [weak self] in
            do {
                try await TranslationClient().translate(text: text, context: context, source: source,
                    target: target, configuration: config, key: key) { [weak self] chunk in
                        await self?.append(chunk, id: id)
                    }
                guard let self, id == self.requestID else { return }
                self.elapsed = Date().timeIntervalSince(start)
                self.output = self.output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.phase = .complete
                if config.saveHistory {
                    self.history.add(HistoryEntry(date: .now, source: text, output: self.output, sourceLanguage: sourceLanguage,
                                                  target: target, service: config.serviceName), now: .now)
                    self.persistHistory()
                }
                DiagnosticLog.shared.record(.requestComplete, ["characters": self.output.utf16.count, "milliseconds": Int(self.elapsed * 1000)])
            } catch {
                guard let self, id == self.requestID else { return }
                let code = (error as NSError).code
                DiagnosticLog.shared.record(Task.isCancelled ? .requestCancelled : (code == NSURLErrorTimedOut ? .requestTimeout : .requestFailed), ["code": code])
                self.phase = Task.isCancelled ? .stopped : .failed(error.localizedDescription)
            }
        }
    }
    private func append(_ chunk: String, id: UUID) {
        guard id == requestID else { return }
        // Leading blank lines would push the translation down; they are dropped until the first visible character.
        let chunk = output.isEmpty ? String(chunk.drop { $0.isWhitespace }) : chunk
        guard !chunk.isEmpty else { return }
        if output.isEmpty { DiagnosticLog.shared.record(.requestFirstText) }
        output += chunk
    }
    func changeSource(_ value: Language) { source = value; if !input.isEmpty { translate() } }
    func changeTarget(_ value: Language) { target = value; explicitTarget = true; if !input.isEmpty { translate() } }
    func swapLanguages() {
        guard let from = detectedSource else { return }
        source = target; target = from; explicitTarget = true
        if !input.isEmpty { translate() }
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    func speak(_ text: String) { speech.stopSpeaking(at: .immediate); speech.speak(AVSpeechUtterance(string: text)) }
    func testConnection() {
        guard !testingConnection else { return }
        testingConnection = true; connectionStatus = "正在测试…"
        let config = configuration
        connectionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.testingConnection = false }
            do {
                let key = try self.credentials.read() ?? ""
                try await TranslationClient().translate(text: "Hello", context: nil, source: .english,
                    target: .chinese, configuration: config, key: key, onText: { _ in })
                self.connectionStatus = "连接成功，模型已返回译文"
            } catch { self.connectionStatus = error.localizedDescription }
        }
    }
    func shutdown() { stop(); connectionTask?.cancel(); shortcuts.remove() }

    func startShortcuts(_ action: @escaping (ShortcutAction) -> Void) {
        shortcuts.action = action
        let status = shortcuts.install()
        guard status == noErr else {
            shortcutIssues = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, "快捷键处理器安装失败（\(status)）") })
            return
        }
        applyShortcuts()
    }
    private func applyShortcuts() {
        let failures = shortcuts.register(ShortcutAction.allCases.map { ($0, configuration.shortcut(for: $0)) })
        // Carbon reports only refusals inside this process or by the system; another app holding the same
        // combination is not reported, so no message claims to know who holds it.
        shortcutIssues = Dictionary(uniqueKeysWithValues: failures.map { action, status in
            (action, "\(configuration.shortcut(for: action).display) 注册失败（\(status)），请换一个组合。")
        })
    }
    /// Releases the global keys while a recorder listens, so pressing the current combination reaches it.
    func pauseShortcuts() { shortcuts.unregisterKeys() }
    func resumeShortcuts() { applyShortcuts() }
    /// Saves a recorded combination and registers it; returns the reason when it clashes and was not kept.
    func setShortcut(_ value: Shortcut, for action: ShortcutAction) -> String? {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && configuration.shortcut(for: $0) == value }) {
            return "\(value.display) 已用于「\(other.title)」，请换一个组合。"
        }
        if GlobalShortcuts.systemUses(value) { return "\(value.display) 是系统快捷键，请换一个组合。" }
        let previous = configuration
        var config = configuration; config.setShortcut(value, for: action); saveConfiguration(config)
        applyShortcuts()
        guard shortcutIssues[action] != nil else { return nil }
        saveConfiguration(previous); applyShortcuts()
        return "\(value.display) 无法注册，仍使用 \(previous.shortcut(for: action).display)。"
    }
    func restoreDefaultShortcuts() {
        var config = configuration
        ShortcutAction.allCases.forEach { config.setShortcut($0.fallback, for: $0) }
        saveConfiguration(config); applyShortcuts()
    }
}
