import AlexCore
import AppKit
import SwiftUI

/// The 更新 section of the general settings: automatic checks, the found version and its notes, and the install button.
struct UpdateSection: View {
    @Bindable var model: AppModel
    private var updater: Updater { model.updater }

    var body: some View {
        Section {
            if updater.isSupported {
                Toggle("自动检查更新", isOn: model.setting(\.checkForUpdates))
                LabeledContent("版本 \(updater.currentVersion)") { action }
                if let release = updater.available, !release.notes.isEmpty {
                    Text(release.notes).font(.callout).textSelection(.enabled)
                }
            } else {
                LabeledContent("版本 \(updater.currentVersion)") { Text("开发版不检查更新").foregroundStyle(TranslationPanelStyle.secondaryText) }
            }
        } header: { Text("更新") } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let status { Text(status) }
                Text("修订 " + (Bundle.main.object(forInfoDictionaryKey: "AlexRevision") as? String ?? "development"))
            }.foregroundStyle(TranslationPanelStyle.secondaryText)
        }
    }

    @ViewBuilder private var action: some View {
        switch updater.state {
        case .available(let release):
            Button("安装 \(release.version) 并重新打开") { Task { await updater.install(release) } }
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .idle, .upToDate, .failed:
            Button("检查更新") { Task { await updater.check() } }
        }
    }

    private var status: String? {
        switch updater.state {
        case .idle, .available: nil
        case .checking: "正在检查…"
        case .upToDate: "已是最新版本。"
        case .installing: "正在下载并安装，完成后 Alex 会自动重新打开。"
        case .failed(let message): message
        }
    }
}
