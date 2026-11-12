import AlexCore
import SwiftUI

/// The panel's history page: the last seven days of finished translations, grouped by day, newest first.
/// Selecting an entry only previews it; the translation the panel came in with stays untouched until "在面板打开".
struct HistoryView: View {
    @Bindable var model: AppModel
    var close: () -> Void
    @State private var query = ""
    @State private var selection: HistoryEntry.ID?
    @State private var confirmingClear = false
    @FocusState private var searching: Bool

    var body: some View {
        let matches = model.history.matching(query)
        let current = matches.first { $0.id == selection } ?? matches.first
        VStack(spacing: 12) {
            HStack {
                Button { model.showHistory(false) } label: {
                    Label("返回", systemImage: "chevron.left").padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }.buttonStyle(.plain).keyboardShortcut("y", modifiers: .command).help("返回翻译（⌘Y）")
                Spacer()
                Text("翻译历史").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).help("关闭").accessibilityLabel("关闭")
            }
            GeometryReader { space in
                if space.size.width >= TranslationPanelStyle.splitWidth {
                    HStack(spacing: 12) {
                        VStack(spacing: 10) { search(matches, current); list(matches, current, expanding: false) }
                            .frame(width: 268)
                        if let current { HistoryDetail(model: model, entry: current, delete: { delete(current, in: matches) }) }
                        else { Color.clear }
                    }
                } else {
                    VStack(spacing: 10) { search(matches, current); list(matches, current, expanding: true) }
                }
            }
            HStack {
                Text("只存在本机，保留 7 天 · ↑↓ 选择，↩ 打开").font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(TranslationPanelStyle.secondaryText)
                Spacer()
                Button("清空历史…", role: .destructive) { confirmingClear = true }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.red).disabled(model.history.entries.isEmpty)
            }
        }
        .onAppear { searching = true }
        .confirmationDialog("清空最近 7 天的翻译历史？", isPresented: $confirmingClear) {
            Button("清空", role: .destructive, action: model.clearHistory)
        } message: { Text("删除后无法恢复。") }
    }

    private func search(_ matches: [HistoryEntry], _ current: HistoryEntry?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(TranslationPanelStyle.secondaryText)
            TextField("搜索原文或译文", text: $query).textFieldStyle(.plain).focused($searching)
                .onSubmit { if let current { model.open(current) } }
                .onKeyPress(.upArrow) { move(-1, in: matches, from: current); return .handled }
                .onKeyPress(.downArrow) { move(1, in: matches, from: current); return .handled }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .paper(radius: 10)
    }

    private func list(_ matches: [HistoryEntry], _ current: HistoryEntry?, expanding: Bool) -> some View {
        let grouped = Dictionary(grouping: matches) { Calendar.current.startOfDay(for: $0.date) }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                        Text(Self.dayTitle(day)).font(.caption.weight(.semibold))
                            .foregroundStyle(TranslationPanelStyle.secondaryText).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
                        ForEach(grouped[day] ?? []) { entry in
                            let selected = entry.id == current?.id
                            Group {
                                if expanding && selected {
                                    HistoryExpandedRow(model: model, entry: entry, delete: { delete(entry, in: matches) })
                                } else {
                                    row(entry, selected: selected)
                                }
                            }.id(entry.id)
                        }
                    }
                }.padding(6)
            }
            .onChange(of: current?.id) { _, id in withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) } }
        }
        .overlay {
            if matches.isEmpty {
                Text(query.isEmpty ? "最近 7 天还没有翻译" : "没有匹配的记录")
                    .font(.callout).foregroundStyle(TranslationPanelStyle.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paper()
    }

    private func row(_ entry: HistoryEntry, selected: Bool) -> some View {
        Button { selection = entry.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.output.oneLine).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(entry.date, format: .dateTime.hour().minute()).font(.caption)
                        .foregroundStyle(TranslationPanelStyle.secondaryText)
                }
                Text(entry.source.oneLine).font(.callout).foregroundStyle(TranslationPanelStyle.secondaryText).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.open(entry) })
        .contextMenu {
            Button("在面板打开") { model.open(entry) }
            Button("复制译文") { model.copy(entry.output) }
            Button("复制原文") { model.copy(entry.source) }
            Divider()
            Button("删除这条", role: .destructive) { delete(entry, in: model.history.matching(query)) }
        }
    }

    private func move(_ step: Int, in matches: [HistoryEntry], from current: HistoryEntry?) {
        guard !matches.isEmpty else { return }
        let index = current.flatMap { entry in matches.firstIndex { $0.id == entry.id } } ?? 0
        selection = matches[min(max(index + step, 0), matches.count - 1)].id
    }
    /// Deleting keeps the selection in place: the next entry, or the previous one at the end of the list.
    private func delete(_ entry: HistoryEntry, in matches: [HistoryEntry]) {
        let rest = matches.filter { $0.id != entry.id }
        let index = matches.firstIndex { $0.id == entry.id } ?? 0
        selection = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
        model.deleteHistory(entry.id)
    }

    nonisolated static func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "今天" }
        if Calendar.current.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN")))
    }
}
