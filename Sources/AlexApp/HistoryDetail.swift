import AlexCore
import SwiftUI

/// The wide panel's right column: one entry's source and translation in full, side by side with the list.
struct HistoryDetail: View {
    var model: AppModel
    var entry: HistoryEntry
    var delete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            card("\(entry.sourceLanguage.title) · 原文", entry.source, font: .body).fixedSize(horizontal: false, vertical: true)
            card("\(entry.target.title) · 译文", entry.output, font: .system(size: 15))
                .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                Text("\(entry.when) · \(entry.service)").font(.caption).foregroundStyle(TranslationPanelStyle.secondaryText)
                Spacer()
                HistoryActions(model: model, entry: entry, delete: delete)
            }.padding(.horizontal, 2)
        }
    }
    private func card(_ title: String, _ text: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(TranslationPanelStyle.secondaryText)
            ScrollView {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines)).font(font).lineSpacing(3)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 220).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paper()
    }
}

/// The narrow panel's selected row, opened in place to show both texts in full.
struct HistoryExpandedRow: View {
    var model: AppModel
    var entry: HistoryEntry
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(entry.sourceLanguage.short) → \(entry.target.short)")
                Spacer()
                Text("\(entry.date.formatted(.dateTime.hour().minute())) · \(entry.service)")
            }.font(.caption).foregroundStyle(TranslationPanelStyle.secondaryText)
            Text(entry.output.trimmingCharacters(in: .whitespacesAndNewlines)).lineSpacing(3).textSelection(.enabled)
            Text(entry.source.trimmingCharacters(in: .whitespacesAndNewlines)).font(.callout).lineSpacing(2)
                .foregroundStyle(TranslationPanelStyle.secondaryText).textSelection(.enabled)
            HStack { Spacer(); HistoryActions(model: model, entry: entry, delete: delete) }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
        .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 12))
    }
}

/// Copy, delete (⌘⌫) and the one action that replaces the panel's translation: open it there (↩ from the search field).
struct HistoryActions: View {
    var model: AppModel
    var entry: HistoryEntry
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            action("复制译文", "doc.on.doc") { model.copy(entry.output) }
            action("删除这条（⌘⌫）", "trash", action: delete).keyboardShortcut(.delete, modifiers: .command)
            Button { model.open(entry) } label: {
                Text("在面板打开 ↩").font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.8), in: Capsule())
            }.buttonStyle(.plain).help("用这条替换面板里的翻译")
        }
    }
    private func action(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 26, height: 26).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

extension HistoryEntry {
    /// "今天 14:31"; the footer of a reopened translation.
    var when: String {
        "\(HistoryView.dayTitle(Calendar.current.startOfDay(for: date))) \(date.formatted(.dateTime.hour().minute()))"
    }
}

extension Language {
    /// One character for the history list's language tag.
    var short: String {
        switch self {
        case .auto: "自动"
        case .chinese: "中"
        case .english: "英"
        default: String(title.prefix(1))
        }
    }
}

extension String {
    /// Line breaks and space runs collapsed, so a one-line preview never starts with an empty line.
    var oneLine: String { split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
