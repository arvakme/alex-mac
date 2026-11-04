import Foundation

/// One rendered block of a Markdown translation; inline styles stay on `text` as Foundation intents.
public struct MarkdownBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph, heading(Int), listItem(marker: String, depth: Int), code, quote, rule
    }
    public var kind: Kind
    public var text: AttributedString
}

public enum Markdown {
    /// Splits text into blocks. Unfinished syntax from a stream still yields its text; single line breaks are kept
    /// because translations and dictionary entries use them as real lines.
    public static func blocks(_ source: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return [MarkdownBlock(kind: .paragraph, text: AttributedString(source))]
        }
        var blocks: [MarkdownBlock] = []
        var currentBlock: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            var piece = AttributedString(parsed[run.range])
            if let inline = run.inlinePresentationIntent, !inline.isDisjoint(with: [.softBreak, .lineBreak]) {
                piece = AttributedString("\n")
            }
            if let first = components.first, first.identity == currentBlock, !blocks.isEmpty {
                blocks[blocks.count - 1].text.append(piece)
            } else {
                currentBlock = components.first?.identity
                blocks.append(MarkdownBlock(kind: kind(of: components), text: piece))
            }
        }
        return blocks.map { block in
            var block = block
            // Code blocks end with the fence's newline; trailing breaks would draw an empty line.
            while block.text.characters.last == "\n" { block.text.characters.removeLast() }
            return block
        }
    }

    private static func kind(of components: [PresentationIntent.IntentType]) -> MarkdownBlock.Kind {
        let lists = components.filter {
            if case .orderedList = $0.kind { return true }
            if case .unorderedList = $0.kind { return true }
            return false
        }
        for component in components {
            switch component.kind {
            case .header(let level): return .heading(level)
            case .codeBlock: return .code
            case .thematicBreak: return .rule
            case .listItem(let ordinal):
                guard let list = lists.first else { return .paragraph }
                if case .orderedList = list.kind { return .listItem(marker: "\(ordinal).", depth: lists.count - 1) }
                return .listItem(marker: "•", depth: lists.count - 1)
            case .blockQuote: return .quote
            default: continue
            }
        }
        return .paragraph
    }
}
