import AlexCore
import SwiftUI

/// Service fields save as they are typed once valid; the API key saves on return or when the field loses focus.
struct ServiceSettings: View {
    @Bindable var model: AppModel
    @State private var draft = Configuration()
    @State private var key = ""
    @State private var editingPrompt = false
    @State private var confirmingDelete = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        Form {
            Section {
                // Grouped forms show the label beside the field but name the field by its value for VoiceOver.
                TextField("名称", text: $draft.serviceName).accessibilityLabel("名称")
                TextField("接口地址", text: $draft.endpoint).autocorrectionDisabled().accessibilityLabel("接口地址")
                TextField("模型", text: $draft.model).autocorrectionDisabled().accessibilityLabel("模型")
            } header: { Text("服务") } footer: {
                // A problem replaces the note instead of adding a row, so the window keeps its height.
                if let problem = endpointIssue ?? modelIssue ?? model.settingsError {
                    Text(problem).foregroundStyle(.red)
                } else {
                    Text("修改后立即生效，无需保存。").foregroundStyle(TranslationPanelStyle.secondaryText)
                }
            }
            Section("API Key") {
                HStack {
                    SecureField("API Key", text: $key,
                                prompt: Text(model.keySaved ? "已保存在钥匙串，输入新值可替换" : "粘贴后按回车保存"))
                        .focused($keyFocused).onSubmit(saveKey).accessibilityLabel("API Key")
                    if model.keySaved {
                        Button("删除…", role: .destructive) { confirmingDelete = true }.tint(.red)
                            .confirmationDialog("删除钥匙串里的 API Key？", isPresented: $confirmingDelete) {
                                Button("删除", role: .destructive) { _ = model.saveKey("") }
                                Button("取消", role: .cancel) {}
                            } message: { Text("删除后翻译会失败，直到重新填写。") }
                    }
                }
            }
            Section("提示词") {
                LabeledContent("提示词") {
                    HStack {
                        Text(draft.prompt == PromptTemplate.defaultText ? "默认" : "已修改").foregroundStyle(TranslationPanelStyle.secondaryText)
                        Button("编辑…") { editingPrompt = true }
                    }
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button("测试连接") { saveKey(); model.testConnection() }.disabled(model.testingConnection)
                    Text(model.connectionStatus).foregroundStyle(TranslationPanelStyle.secondaryText)
                        .lineLimit(2, reservesSpace: true).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
        .onAppear { draft = model.configuration; model.refreshKeyStatus() }
        .onChange(of: draft) { _, value in autosave(value) }
        .onChange(of: keyFocused) { _, focused in if !focused { saveKey() } }
        .sheet(isPresented: $editingPrompt) { PromptEditor(prompt: $draft.prompt) }
    }
    private var endpointIssue: String? {
        (try? draft.completionsURL()) == nil ? "地址需以 https:// 开头（本机地址可用 http），修正前仍使用上一个有效地址。" : nil
    }
    private var modelIssue: String? {
        guard draft.wireModel.isEmpty else { return nil }
        return model.configuration.wireModel.isEmpty ? "请填写服务商提供的模型名称。" : "模型不能为空，修正前仍使用上一个模型。"
    }
    /// Copies only this page's fields onto the latest configuration, so other pages' changes are never overwritten.
    private func autosave(_ value: Configuration) {
        var config = model.configuration
        config.serviceName = value.serviceName
        config.prompt = value.prompt
        if endpointIssue == nil { config.endpoint = value.endpoint }
        if modelIssue == nil { config.model = value.model }
        if config != model.configuration { model.saveConfiguration(config) }
    }
    private func saveKey() {
        guard !key.isEmpty, model.saveKey(key) else { return }
        key = ""
    }
}
