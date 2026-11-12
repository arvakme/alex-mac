import AlexCore
import SwiftUI

/// Cards that replace the translation when it cannot be shown.
extension TranslationView {
    func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("翻译失败", systemImage: "exclamationmark.triangle").fontWeight(.medium)
            Text(message).font(.callout).textSelection(.enabled)
            HStack {
                Button("重试", systemImage: "arrow.clockwise", action: model.translate).buttonStyle(.borderedProminent)
                Button("打开设置", systemImage: "gearshape", action: settings).buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }
    func selectionCard(_ failure: SelectionFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(failure.title, systemImage: failure == .permission ? "lock.shield" : "text.cursor").fontWeight(.medium)
            Text(failure.localizedDescription).font(.callout)
            if failure == .permission {
                Button("打开系统设置", systemImage: "gearshape", action: SelectionReader.requestPermission)
                    .buttonStyle(.borderedProminent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// The pieces every text card is made of.
extension TranslationView {
    func placeholder(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(TranslationPanelStyle.secondaryText)
            .padding(.horizontal, 13).padding(.top, 8).allowsHitTesting(false)
    }
    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
    }
    func cardBar<Actions: View>(_ title: String, _ count: Int, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 2) {
            Text("\(Text(title).fontWeight(.semibold)) · \(count) 字符").font(.caption).foregroundStyle(TranslationPanelStyle.secondaryText)
            Spacer()
            actions()
        }.frame(height: 24).padding(.horizontal, 10).padding(.bottom, 6)
    }
}

extension View {
    /// The opaque sheet every text sits on: the system text background with a hairline edge, never translucent.
    func paper(radius: CGFloat = TranslationPanelStyle.paperRadius) -> some View {
        background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.separator, lineWidth: 1) }
            .clipShape(.rect(cornerRadius: radius))
    }
}
