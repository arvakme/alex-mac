import AlexCore
import SwiftUI

enum TranslationPanelStyle {
    /// Height is the most the panel grows to for long text; resizing the panel changes it.
    static let defaultSize = CGSize(width: 432, height: 520)
    static let minSize = CGSize(width: 360, height: 280)
    static let maxSize = CGSize(width: 760, height: 1000)
    /// Content width from which source and translation sit side by side, and history gets a preview column.
    static let splitWidth: CGFloat = 560
    static let cornerRadius: CGFloat = 24
    /// Share of the window colour laid over the glass frame. Glass carries only the controls (HIG: no glass in the
    /// content layer); the texts sit on opaque paper, so the background never shows through them.
    static let surfaceOpacity = 0.86
    static let paperRadius: CGFloat = 16
    /// Captions and status. The system secondary colour turns vibrant on glass and drops near 3:1.
    static let secondaryText = Color.primary.opacity(0.72)
}

struct TranslationView: View {
    @Bindable var model: AppModel
    var close: () -> Void
    var settings: () -> Void
    /// Receives the panel height that shows both texts without scrolling.
    var fit: (CGFloat) -> Void
    @State private var copied = false
    @State private var sourceText: CGFloat = 0
    @State private var outputText: CGFloat = 0
    @State private var layout = CardsLayout()
    /// Wide enough for two columns: the panel keeps the size the reader gave it instead of fitting the text.
    @State private var wide = false
    /// Source card's share of the card area once the reader drags the divider; 0 keeps the automatic split.
    @AppStorage("translationSplitRatio") private var splitRatio = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    private static let cardSpacing: CGFloat = 10
    private static let cardBar: CGFloat = 30
    private static let minText: CGFloat = 38
    nonisolated private static let panelSpace = "alex.panel"

    /// The card area and everything around it, read in one layout pass. Measured separately, the two could come from
    /// different panel heights, and the height computed from them would chase itself.
    struct CardsLayout: Equatable {
        var area: CGFloat = 0
        var chrome: CGFloat?
    }

    var body: some View {
        Group {
            if model.showingHistory { HistoryView(model: model, close: close) } else { translation }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= TranslationPanelStyle.splitWidth } action: { wide = $0 }
        .padding(14)
        // Fixed limits instead of the content's own size, so the content takes the window's size and the
        // window reads its resize limits from here.
        .frame(minWidth: TranslationPanelStyle.minSize.width, maxWidth: TranslationPanelStyle.maxSize.width,
               minHeight: TranslationPanelStyle.minSize.height, maxHeight: TranslationPanelStyle.maxSize.height,
               alignment: .top)
        .coordinateSpace(.named(Self.panelSpace))
        .background {
            Color.clear.contentShape(Rectangle())
                .gesture(WindowDragGesture(), including: model.presentation == .floating ? .all : .none)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : TranslationPanelStyle.surfaceOpacity),
                    in: .rect(cornerRadius: TranslationPanelStyle.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: TranslationPanelStyle.cornerRadius))
        // Glass draws beyond its shape; clip that pass and let WindowServer provide the outer shadow.
        .clipShape(.rect(cornerRadius: TranslationPanelStyle.cornerRadius))
        .onExitCommand(perform: close)
        .onChange(of: model.output) { copied = false }
        .onChange(of: idealHeight, initial: true) { if let idealHeight { fit(idealHeight) } }
    }
    private var translation: some View {
        VStack(spacing: 12) {
            header
            cards
            if case .failed(let message) = model.phase { errorCard(message) }
            if case .noSelection(let failure) = model.phase { selectionCard(failure) }
            if model.input.isEmpty {
                HStack(spacing: 14) {
                    Text("↩ 翻译"); Text("⇧↩ 换行"); Text("esc 关闭")
                    Spacer()
                }.font(.caption).foregroundStyle(TranslationPanelStyle.secondaryText)
            }
            footer
        }
    }
    private var hasOutput: Bool { !model.output.isEmpty }
    private var sourceNeed: CGFloat { max(sourceText, Self.minText) + Self.cardBar }
    private var outputNeed: CGFloat { max(outputText, Self.minText) + Self.cardBar }
    private var idealHeight: CGFloat? {
        // History and the side-by-side layout take all the height the reader allows.
        if model.showingHistory || wide { return TranslationPanelStyle.maxSize.height }
        guard let chrome = layout.chrome else { return nil }
        let cards = sourceNeed + (hasOutput ? Self.cardSpacing + outputNeed : 0)
        return (chrome + cards).rounded(.up)
    }
    /// Shares the card area in proportion to what each text needs, so neither card is cut while the other has room.
    static func split(_ area: CGFloat, source: CGFloat, output: CGFloat?, ratio: Double = 0) -> (source: CGFloat, output: CGFloat) {
        let minCard = minText + cardBar
        guard let output else { return (max(area, minCard), 0) }
        if ratio > 0 {
            let top = min(max(area * ratio, minCard), max(minCard, area - minCard))
            return (top, max(area - top, minCard))
        }
        let share = area * source / (source + output)
        let top = min(max(share, minCard), max(minCard, area - min(output, area / 2)))
        return (top, max(area - top, minCard))
    }
    private var cards: some View {
        let area = layout.area - (hasOutput ? Self.cardSpacing : 0)
        let heights = Self.split(area, source: sourceNeed, output: hasOutput ? outputNeed : nil, ratio: splitRatio)
        return Group {
            if wide {
                HStack(spacing: 0) { sourceCard; Rectangle().fill(.separator).frame(width: 1).padding(.vertical, 12); outputCard }
            } else {
                VStack(spacing: 0) {
                    sourceCard.frame(height: heights.source)
                    if hasOutput {
                        PanelDivider(ratio: Binding(get: { heights.source / max(area, 1) }, set: { splitRatio = $0 }), area: area)
                            .frame(height: Self.cardSpacing)
                        outputCard.frame(height: heights.output)
                    }
                }
            }
        }
        .paper()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CardsLayout.self) { proxy in
            CardsLayout(area: proxy.size.height,
                        chrome: proxy.bounds(of: .named(Self.panelSpace)).map { $0.height - proxy.size.height })
        } action: { layout = $0 }
    }
    private var sourceCard: some View {
        card {
            ZStack(alignment: .topLeading) {
                if model.input.isEmpty { placeholder("输入或粘贴要翻译的文字") }
                PanelTextView(text: $model.input, contentHeight: $sourceText, label: "原文", onSubmit: model.translate)
            }
            cardBar("原文", model.input.count) {
                icon("朗读原文", "speaker.wave.2", disabled: model.input.isEmpty) { model.speak(model.input) }
                icon("复制原文", "doc.on.doc", disabled: model.input.isEmpty) { model.copy(model.input) }
            }
        }
    }
    /// In two columns the translation card is always there, so the layout does not jump when the first words arrive.
    private var outputCard: some View {
        card {
            ZStack(alignment: .topLeading) {
                if !hasOutput { placeholder("↩ 翻译后，译文显示在这里") }
                PanelTextView(text: .constant(model.output), contentHeight: $outputText, label: "译文", editable: false,
                              freshCount: model.isStreaming && !reduceMotion ? 4 : 0, markdown: model.configuration.renderMarkdown)
            }
            cardBar("译文", model.output.count) {
                icon("朗读译文", "speaker.wave.2", disabled: model.isStreaming || !hasOutput) { model.speak(model.output) }
                icon(copied ? "已复制" : "复制译文", copied ? "checkmark" : "doc.on.doc", disabled: model.isStreaming || !hasOutput) {
                    model.copy(model.output); copied = true
                }
            }
        }
    }
    private var header: some View {
        HStack {
            icon(model.pinned ? "取消置顶" : "置顶", model.pinned ? "pin.fill" : "pin") { model.pinned.toggle() }
                .foregroundStyle(model.pinned ? Color.accentColor : .secondary)
                .background(model.pinned ? Color.accentColor.opacity(0.15) : .clear, in: Circle())
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Menu {
                    Picker("源语言", selection: Binding(get: { model.source }, set: model.changeSource)) {
                        ForEach(Language.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.inline).labelsHidden()
                } label: {
                    if model.source == .auto, let detected = model.detectedSource {
                        Text("\(Text("自动").foregroundStyle(TranslationPanelStyle.secondaryText)) \(detected.title)")
                    } else {
                        Text(model.source.title)
                    }
                }.menuIndicator(.visible).accessibilityLabel("源语言")
                icon("交换语言", "arrow.left.arrow.right", disabled: model.detectedSource == nil) { model.swapLanguages() }
                Menu {
                    Picker("目标语言", selection: Binding(get: { model.target }, set: model.changeTarget)) {
                        ForEach(Language.targets) { Text($0.title).tag($0) }
                    }.pickerStyle(.inline).labelsHidden()
                } label: { Text(model.target.title) }.menuIndicator(.visible).accessibilityLabel("目标语言")
            }
            .font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: Capsule())
            Spacer(minLength: 4)
            icon("关闭", "xmark", action: close)
        }
    }
    private var footer: some View {
        HStack(spacing: 8) {
            if model.isStreaming {
                ProgressView().controlSize(.mini)
            } else if model.restored != nil {
                Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(TranslationPanelStyle.secondaryText)
            } else {
                Circle().fill(statusColor).frame(width: 6, height: 6).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(status).font(.caption).foregroundStyle(TranslationPanelStyle.secondaryText)
                if model.fromClipboard {
                    Text("没读到选中文字 · 原文来自剪贴板").font(.caption2).foregroundStyle(TranslationPanelStyle.secondaryText)
                } else if !model.output.isEmpty, model.isTerm, model.context == nil {
                    Text("未取得上下文 · 通用词义").font(.caption2).foregroundStyle(TranslationPanelStyle.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if let restored = model.restored {
                icon("从历史删除", "trash") { model.deleteHistory(restored.id) }
            }
            Button { model.showHistory(true) } label: {
                Label("历史", systemImage: "clock.arrow.circlepath").font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }.buttonStyle(.plain).keyboardShortcut("y", modifiers: .command).help("翻译历史（⌘Y）")
            icon("设置", "gearshape", action: settings)
            if !model.input.isEmpty {
                icon(model.isStreaming ? "停止翻译" : "翻译", model.isStreaming ? "stop.fill" : "arrow.clockwise") {
                    copied = false
                    if model.isStreaming { model.stop() } else { model.translate() }
                }
            }
        }
    }
    private var statusColor: Color {
        switch model.phase {
        case .failed: .red
        case .idle, .noSelection: TranslationPanelStyle.secondaryText
        case .stopped: .orange
        default: .green
        }
    }
    private var status: String {
        switch model.phase {
        case .idle: model.configuration.serviceName
        case .streaming: "正在翻译…"
        case .complete: model.restored.map { "\($0.when) · \($0.service)" } ?? "\(model.configuration.serviceName) · \(model.elapsed.formatted(.number.precision(.fractionLength(1)))) 秒"
        case .stopped: "已停止 · 译文可能不完整"
        case .failed: "翻译未完成"
        case .noSelection: model.configuration.serviceName
        }
    }
    private func icon(_ title: String, _ symbol: String, disabled: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 24) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title).disabled(disabled)
    }
}
