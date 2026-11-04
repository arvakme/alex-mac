import Foundation
import NaturalLanguage

public enum SelectionContext {
    public static func sentence(in text: String, selected: String, range: NSRange) -> String? {
        let ns = text as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location <= ns.length, range.length <= ns.length - range.location,
              ns.substring(with: range) == selected,
              let selection = Range(range, in: text) else { return nil }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: String?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { sentence, _ in
            if sentence.lowerBound <= selection.lowerBound && sentence.upperBound >= selection.upperBound {
                let candidate = String(text[sentence]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate != selected.trimmingCharacters(in: .whitespacesAndNewlines) { result = candidate }
                return false
            }
            return true
        }
        return result
    }
}
