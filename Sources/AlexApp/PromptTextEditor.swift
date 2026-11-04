import AlexCore
import AppKit
import SwiftUI

@MainActor final class PromptInsertion {
    weak var editor: NSTextView?
    func insert(_ variable: PromptVariable) {
        guard let editor else { return }
        let selection = editor.selectedRange()
        editor.window?.makeFirstResponder(editor)
        editor.insertText(variable.placeholder, replacementRange: selection)
    }
}

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let insertion: PromptInsertion

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = PromptTokenLayout()
        layout.delegate = layout
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let editor = CaretTextView(frame: .zero, textContainer: container)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.insertionPointColor = .controlAccentColor
        editor.textContainerInset = NSSize(width: 10, height: 12)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.font = PromptTokenLayout.font
        editor.textColor = .labelColor
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("提示词内容")
        let scroll = OverlayScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = editor
        insertion.editor = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, editor.string != text else { return }
        editor.string = text
        PromptTokenLayout.format(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextEditor
        init(_ parent: PromptTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            PromptTokenLayout.format(editor)
        }
    }
}

private final class PromptTokenLayout: NSLayoutManager, NSLayoutManagerDelegate {
    @MainActor static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private static let token = NSAttributedString.Key("alex.promptVariable")
    private static let pattern = try! NSRegularExpression(pattern:
        PromptVariable.allCases.map { NSRegularExpression.escapedPattern(for: $0.placeholder) }.joined(separator: "|"))

    @MainActor static func format(_ editor: NSTextView) {
        guard let storage = editor.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PromptTokenLayout.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ]
        storage.beginEditing()
        storage.setAttributes(attributes, range: all)
        for match in pattern.matches(in: storage.string, range: all) {
            storage.addAttribute(token, value: true, range: match.range)
        }
        storage.endEditing()
        editor.typingAttributes = attributes
    }
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage {
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            storage.enumerateAttribute(Self.token, in: characters) { value, range, _ in
                guard value != nil else { return }
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
                // Accent only behind the token; the text stays label colour so it reads at full contrast.
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                // Line fragments include the line spacing below the text; size the pill from the font instead,
                // so it sits on the glyphs like the caret does.
                guard let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
                enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                    let glyph = self.glyphIndex(for: NSPoint(x: rect.midX, y: rect.midY), in: container)
                    let baseline = self.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + self.location(forGlyphAt: glyph).y
                    let pill = NSRect(x: rect.minX - 2 + origin.x, y: baseline - font.ascender - 1 + origin.y,
                                      width: rect.width + 4, height: font.ascender - font.descender + 2)
                    NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        guard let storage = textStorage, charIndex > 0, charIndex < storage.length else { return true }
        var range = NSRange()
        guard storage.attribute(Self.token, at: charIndex, effectiveRange: &range) != nil else { return true }
        return charIndex == range.location
    }
}
