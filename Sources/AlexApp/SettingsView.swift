import AlexCore
import AppKit
import ServiceManagement
import SwiftUI

/// Native preference window: toolbar tabs, grouped forms, every change saved the moment it is made.
@MainActor enum SettingsWindow {
    static let width: CGFloat = 520
    static let serviceTab = 2

    static func make(model: AppModel) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let pages: [(String, String, AnyView)] = [
            ("通用", "gearshape", AnyView(GeneralSettings(model: model))),
            ("快捷键", "keyboard", AnyView(ShortcutSettings(model: model))),
            ("服务", "network", AnyView(ServiceSettings(model: model))),
        ]
        for (title, symbol, page) in pages {
            let controller = NSHostingController(rootView: page.frame(width: width))
            controller.sizingOptions = .preferredContentSize
            // The toolbar tab view shows the selected tab's title as the window title.
            controller.title = title
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.identifier = NSUserInterfaceItemIdentifier("alex.settings")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

extension AppModel {
    /// A binding that saves the configuration on every change.
    func setting<Value>(_ key: WritableKeyPath<Configuration, Value>) -> Binding<Value> {
        Binding(get: { self.configuration[keyPath: key] }, set: { value in
            var config = self.configuration; config[keyPath: key] = value; self.saveConfiguration(config)
        })
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var authorized = SelectionReader.authorized
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("翻译") {
                Toggle("没有选中文字时翻译剪贴板", isOn: model.setting(\.clipboardFallback))
                    .accessibilityLabel("没有选中文字时翻译剪贴板")
                Toggle("取词失败时自动复制选中文字", isOn: model.setting(\.copySelectionFallback))
                    .accessibilityLabel("取词失败时自动复制选中文字")
                    .help("先尝试辅助功能，再临时发送 ⌘C；读取后恢复剪贴板。关闭后不模拟复制。")
                Toggle("渲染 Markdown", isOn: model.setting(\.renderMarkdown))
                    .accessibilityLabel("渲染 Markdown")
                Toggle("保存翻译历史（最近 7 天）", isOn: model.setting(\.saveHistory))
                    .help("只存在本机。关闭后不再保存，并删除已有记录。")
                Picker("默认翻译成", selection: model.setting(\.target)) {
                    ForEach(Language.targets) { Text($0.title).tag($0) }
                }
                Picker("原文是中文时翻译成", selection: model.setting(\.chineseTarget)) {
                    ForEach(Language.targets) { Text($0.title).tag($0) }
                }
            }
            Section {
                Picker("面板出现在", selection: model.setting(\.position)) {
                    ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                }
                Toggle("选中文字后显示翻译小图标", isOn: model.setting(\.showSelectionIcon))
            } header: { Text("面板") } footer: {
                Text(model.configuration.position.explanation).foregroundStyle(TranslationPanelStyle.secondaryText)
            }
            Section {
                LabeledContent("辅助功能权限") {
                    if authorized { Text("已授权").foregroundStyle(TranslationPanelStyle.secondaryText) }
                    else { Button("打开系统设置…", action: SelectionReader.requestPermission) }
                }
                Toggle("登录时打开 alex", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch { loginError = error.localizedDescription }
                }
            } header: { Text("系统") } footer: {
                Text("辅助功能只用于划词时读取选中文字和它所在的句子。").foregroundStyle(TranslationPanelStyle.secondaryText)
            }
            UpdateSection(model: model)
            Section {
                Button("导出诊断报告…", action: model.exportDiagnostics).disabled(model.exportingDiagnostics)
            } header: { Text("诊断") } footer: {
                Text(model.diagnosticStatus).foregroundStyle(TranslationPanelStyle.secondaryText)
            }
            if let error = loginError ?? model.settingsError { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            authorized = SelectionReader.authorized
        }
    }
}

struct ShortcutSettings: View {
    @Bindable var model: AppModel
    @State private var messages: [ShortcutAction: String] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(model: model, action: action) { messages[action] = $0 }
                    }
                }
            } footer: {
                // A problem replaces the hint instead of adding a row, so the window keeps its height.
                if let problem = ShortcutAction.allCases.lazy.compactMap({ messages[$0] ?? model.shortcutIssues[$0] }).first {
                    Text(problem).foregroundStyle(.red)
                } else {
                    Text("点按右侧的组合后按下新的快捷键，按 esc 取消。组合里至少要有 ⌘、⌃ 或 ⌥。").foregroundStyle(TranslationPanelStyle.secondaryText)
                }
            }
            Section {
                Button("恢复默认快捷键") { messages = [:]; model.restoreDefaultShortcuts() }
                    .disabled(ShortcutAction.allCases.allSatisfy { model.configuration.shortcut(for: $0) == $0.fallback })
            }
        }
        .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
    }
}
