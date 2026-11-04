import AlexCore
import SwiftUI

struct PromptEditor: View {
    @Binding var prompt: String
    @State private var draft = ""
    @State private var insertion = PromptInsertion()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("提示词").font(.system(size: 14, weight: .semibold))
                Text(draft == PromptTemplate.defaultText ? "正在使用默认" : "已修改")
                    .font(.system(size: 10)).foregroundStyle(TranslationPanelStyle.secondaryText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                Spacer()
            }
            PromptTextEditor(text: $draft, insertion: insertion)
                .frame(height: 304)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 12))
                .clipShape(.rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.25), lineWidth: 3))
            HStack(spacing: 7) {
                Text("插入变量：").foregroundStyle(TranslationPanelStyle.secondaryText)
                ForEach(PromptVariable.allCases) { variable in
                    Button(variable.rawValue) { insertion.insert(variable) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                        .tint(.gray).foregroundStyle(.primary)
                        .help(variable == .originalText || variable == .contextSentence
                              ? "仅插入数据占位符，实际内容单独发送，不拼入系统指令。" : "在光标处插入变量")
                }
                Spacer(minLength: 0)
            }.font(.system(size: 11))
            HStack {
                Button("恢复默认", systemImage: "arrow.counterclockwise") { draft = PromptTemplate.defaultText }
                    .tint(.gray).foregroundStyle(.primary)
                    .disabled(draft == PromptTemplate.defaultText)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).tint(.gray).foregroundStyle(.primary)
                Button("完成") { prompt = draft; dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(draft.isEmpty)
            }.controlSize(.small).buttonBorderShape(.capsule)
        }
        .padding(18).frame(width: 528)
        .onAppear { draft = prompt }
    }
}
