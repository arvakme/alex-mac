import AlexCore
import AppKit

/// Turns Markdown blocks into the panel's text style. Only the translation is rendered; copying still uses raw text.
@MainActor enum MarkdownStyle {
    private static let listIndent: CGFloat = 18
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    static func render(_ text: String) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for (index, block) in Markdown.blocks(text).enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n", attributes: PanelTextView.attributes)) }
            out.append(render(block))
        }
        return out
    }

    private static func render(_ block: MarkdownBlock) -> NSAttributedString {
        let paragraph = (PanelTextView.attributes[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
        paragraph.paragraphSpacing = 6
        var font = PanelTextView.font
        var color = NSColor.labelColor
        var prefix = ""
        switch block.kind {
        case .paragraph: break
        case .heading(let level):
            font = .systemFont(ofSize: level == 1 ? 17 : level == 2 ? 15.5 : 14, weight: .semibold)
        case .listItem(let marker, let depth):
            let indent = listIndent * CGFloat(depth + 1)
            prefix = marker + "\t"
            paragraph.firstLineHeadIndent = indent - listIndent
            paragraph.headIndent = indent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            paragraph.paragraphSpacing = 2
        case .code:
            font = codeFont
            paragraph.firstLineHeadIndent = 10
            paragraph.headIndent = 10
        case .quote:
            color = .labelColor
            paragraph.firstLineHeadIndent = 12
            paragraph.headIndent = 12
        case .rule:
            color = .tertiaryLabelColor
            paragraph.alignment = .center
        }
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let out = NSMutableAttributedString(string: prefix, attributes: base)
        for run in block.text.runs {
            var attributes = base
            let inline = run.inlinePresentationIntent ?? []
            if block.kind == .rule {
                out.append(NSAttributedString(string: "———", attributes: attributes)); continue
            }
            if inline.contains(.code) {
                attributes[.font] = codeFont
                attributes[.backgroundColor] = NSColor.quaternarySystemFill
            } else {
                attributes[.font] = styled(font, bold: inline.contains(.stronglyEmphasized), italic: inline.contains(.emphasized))
            }
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            out.append(NSAttributedString(string: String(block.text[run.range].characters), attributes: attributes))
        }
        return out
    }

    private static func styled(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    }
}
