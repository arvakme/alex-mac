import AppKit
import SwiftUI

/// Source and translation cards share this view, so both scroll, select, inset and measure the same way.
struct PanelTextView: NSViewRepresentable {
    @Binding var text: String
    /// Height the text needs including insets, reported by the text view's own layout.
    @Binding var contentHeight: CGFloat
    var label: String
    var editable = true
    /// Trailing characters still arriving from the stream; drawn faint until the next update.
    var freshCount = 0
    /// Renders Markdown; the bound text stays the raw source that copying uses.
    var markdown = false
    var onSubmit: () -> Void = {}

    @MainActor static let font = NSFont.systemFont(ofSize: 14)
    @MainActor static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }()
    static let inset = NSSize(width: 8, height: 8)

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PanelTextFrame {
        let view = PanelNSTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.isEditable = editable
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.insertionPointColor = .controlAccentColor
        view.font = Self.font
        view.typingAttributes = Self.attributes
        view.textContainerInset = Self.inset
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.setAccessibilityLabel(label)
        view.onHeight = { [weak coordinator = context.coordinator] in coordinator?.report($0) }
        let scroll = OverlayScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = view
        // Matches the text inset, so the first and last lines are never faded once scrolled to an end.
        return PanelTextFrame(scroll: scroll, fadeHeight: Self.inset.height)
    }
    // Fill exactly the space the card offers; the scroll view's own fitting size would overflow the card.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PanelTextFrame, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? contentHeight)
    }
    func updateNSView(_ frame: PanelTextFrame, context: Context) {
        context.coordinator.parent = self
        guard let view = frame.scroll.documentView as? PanelNSTextView else { return }
        view.submit = editable ? onSubmit : nil
        if view.source != text || view.freshCount != freshCount || view.markdown != markdown { view.show(text, fresh: freshCount, markdown: markdown) }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PanelTextView
        init(_ parent: PanelTextView) { self.parent = parent }
        func report(_ height: CGFloat) {
            // Layout runs inside SwiftUI's update pass; publish the height after it.
            Task { @MainActor [weak self] in self?.parent.contentHeight = height }
        }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
        // Tab moves focus like other controls in the panel instead of inserting a tab character.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)): textView.window?.selectNextKeyView(nil)
            case #selector(NSResponder.insertBacktab(_:)): textView.window?.selectPreviousKeyView(nil)
            default: return false
            }
            return true
        }
    }
}

/// Thin scrollers that appear only while scrolling, even when the system preference asks for legacy ones.
final class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}

/// Clips and edge-fades the scroll view from a layer that never scrolls. The clip view's own layer shifts its
/// bounds while scrolling, so a mask there moves with the text and its clip lets lines show past the card edge.
final class PanelTextFrame: NSView {
    let scroll: NSScrollView
    private let fadeHeight: CGFloat
    private let fade = CAGradientLayer()

    init(scroll: NSScrollView, fadeHeight: CGFloat) {
        self.scroll = scroll
        self.fadeHeight = fadeHeight
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.mask = fade
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError("PanelTextFrame is created in code") }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let edge = min(0.5, fadeHeight / max(bounds.height, 1))
        fade.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        fade.frame = bounds
    }
}

/// Line spacing makes TextKit's caret as tall as the whole line fragment; this keeps it to the font's height.
class CaretTextView: NSTextView {
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var caret = rect
        if let font = typingAttributes[.font] as? NSFont ?? font {
            caret.size.height = min(rect.height, ceil(font.ascender - font.descender))
        }
        super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
    }
}

final class PanelNSTextView: CaretTextView {
    var submit: (() -> Void)?
    var onHeight: ((CGFloat) -> Void)?
    private(set) var freshCount = 0
    private(set) var markdown = false
    /// The raw text last shown; differs from `string` when Markdown is rendered.
    private(set) var source = ""
    private var reported: CGFloat = -1

    func show(_ text: String, fresh: Int, markdown: Bool) {
        self.markdown = markdown
        freshCount = fresh
        source = text
        let value = markdown ? MarkdownStyle.render(text) : NSMutableAttributedString(string: text, attributes: PanelTextView.attributes)
        if fresh > 0, value.length > 0 {
            let count = min(fresh, value.length)
            value.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(0.35),
                               range: NSRange(location: value.length - count, length: count))
        }
        textStorage?.setAttributedString(value)
        reportHeight()
    }
    override func keyDown(with event: NSEvent) {
        if let submit, event.keyCode == 36, !event.modifierFlags.contains(.shift), !hasMarkedText() {
            submit()
        } else { super.keyDown(with: event) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportHeight()
    }
    override func didChangeText() {
        super.didChangeText()
        source = string
        reportHeight()
    }
    private func reportHeight() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2)
        guard abs(height - reported) > 0.5 else { return }
        reported = height
        onHeight?(height)
    }
}
