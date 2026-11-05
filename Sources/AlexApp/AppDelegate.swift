import AppKit
import AlexCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var panels: PanelController!
    private var status: NSStatusItem!
    private var bubble: SelectionBubble!
    private let stallMonitor = StallMonitor()
    private let acquisition = SelectionAcquisition()

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.shared.record(.processStart, ["accessibility": SelectionReader.authorized ? 1 : 0])
        stallMonitor.start()
        NSApp.setActivationPolicy(.accessory)
        panels = PanelController(model: model)
        configureStatusItem()
        configureMainMenu()
        model.startShortcuts { [weak self] action in
            if action == .selection { self?.translateSelection() } else { self?.panels.showInput() }
        }
        bubble = SelectionBubble(model: model)
        bubble.onSelect = { [weak self] selection in self?.panels.showSelection(selection) }
        bubble.start()
        model.updater.startAutomaticChecks(enabled: model.configuration.checkForUpdates)
        panels.showInput()
    }
    private func configureStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = status.button else { return }
        if let url = Bundle.main.url(forResource: "MenuBar", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.isTemplate = true; image.size = NSSize(width: 18, height: 18); button.image = image
        } else { button.title = "a" }
        button.toolTip = "alex · 左键输入翻译，右键菜单"
        button.target = self; button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("alex 翻译菜单栏")
    }
    private func configureMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem(); app.submenu = menu()
        main.addItem(app)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"),
                                     ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            submenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = submenu; main.addItem(edit); NSApp.mainMenu = main
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = menu(); menu.delegate = self; status.menu = menu; status.button?.performClick(nil)
        } else { panels.showInput(anchor: status.button?.window?.frame.origin, presentation: .menuBar) }
    }
    func menuDidClose(_ menu: NSMenu) { status.menu = nil }
    private func menu() -> NSMenu {
        let menu = NSMenu(title: "alex")
        for (title, action, selector) in [("输入翻译", ShortcutAction.input, #selector(inputTranslation)),
                                          ("划词翻译", .selection, #selector(translateSelection))] {
            let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: "")
            let shortcut = model.configuration.shortcut(for: action)
            // Shown for reference only; the global hot key does the work, so single printable keys are enough here.
            if shortcut.key.count == 1 {
                item.keyEquivalent = shortcut.key.lowercased()
                item.keyEquivalentModifierMask = NSEvent.ModifierFlags(carbon: shortcut.modifiers)
            }
        }
        menu.addItem(.separator())
        let target = NSMenuItem(title: "翻译成", action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for language in Language.targets {
            let item = languages.addItem(withTitle: language.title, action: #selector(selectTarget(_:)), keyEquivalent: "")
            item.representedObject = language.rawValue
            item.state = model.configuration.target == language ? .on : .off
            item.target = self
        }
        target.submenu = languages; menu.addItem(target)
        let icon = menu.addItem(withTitle: "选中后显示小图标", action: #selector(toggleIcon), keyEquivalent: "")
        icon.state = model.configuration.showSelectionIcon ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(settings), keyEquivalent: ",")
        if let release = model.updater.available {
            menu.addItem(withTitle: "安装新版本 \(release.version)…", action: #selector(settings), keyEquivalent: "")
        } else if model.updater.isSupported {
            menu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        }
        menu.addItem(withTitle: "导出诊断报告…", action: #selector(exportDiagnostics), keyEquivalent: "")
        menu.addItem(withTitle: "退出 alex", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }
    @objc private func inputTranslation() { panels.showInput() }
    @objc private func translateSelection() {
        acquisition.start(configuration: model.configuration) { [weak self] result in
            switch result {
            case .success(let selection): self?.panels.showSelection(selection)
            case .failure(let failure): self?.panels.selectionFailed(failure)
            }
        }
    }
    @objc private func selectTarget(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let language = Language(rawValue: value) else { return }
        var config = model.configuration; config.target = language; model.saveConfiguration(config)
    }
    @objc private func toggleIcon() {
        var config = model.configuration; config.showSelectionIcon.toggle(); model.saveConfiguration(config)
    }
    @objc private func settings() { panels.showSettings() }
    @objc private func checkForUpdates() { panels.showSettings(); Task { await model.updater.check() } }
    @objc private func exportDiagnostics() { model.exportDiagnostics() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panels.showInput(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        acquisition.cancel(); bubble.stop(); panels.stop(); model.shutdown()
        stallMonitor.stop()
        DiagnosticLog.shared.record(.processExit); DiagnosticLog.shared.flush()
    }
}

extension NSEvent.ModifierFlags {
    init(carbon: UInt32) {
        self = []
        if carbon & Shortcut.control != 0 { insert(.control) }
        if carbon & Shortcut.option != 0 { insert(.option) }
        if carbon & Shortcut.shift != 0 { insert(.shift) }
        if carbon & Shortcut.command != 0 { insert(.command) }
    }
    var carbon: UInt32 {
        (contains(.control) ? Shortcut.control : 0) | (contains(.option) ? Shortcut.option : 0)
            | (contains(.shift) ? Shortcut.shift : 0) | (contains(.command) ? Shortcut.command : 0)
    }
}
