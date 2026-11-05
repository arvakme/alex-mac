import AppKit
import ApplicationServices
import AlexCore

struct CapturedSelection: Sendable {
    let text: String
    let context: String?
    let anchor: NSPoint
    /// Read from the clipboard because the selection itself could not be read; the panel says so.
    var fromClipboard = false
}

/// Raw values are the reason codes written to the diagnostic log.
enum SelectionFailure: Int, LocalizedError, Equatable {
    case permission = 1, empty, unavailable, clipboardEmpty, clipboardNotText
    var errorDescription: String? {
        switch self {
        case .permission: "请在系统设置 → 隐私与安全性 → 辅助功能中允许 alex。授权前可以继续输入翻译。"
        case .unavailable: "这个应用没有提供可读取的选中文字。请复制后在 alex 中粘贴翻译。"
        case .clipboardEmpty: "剪贴板里没有文字。请选中文字，或在原文框中输入。"
        case .clipboardNotText: "剪贴板的第一项不是文字（可能是图片或文件），无法翻译。"
        case .empty: "没有读到选中文字。请先选中文字，或直接在原文框中输入。"
        }
    }
    var title: String { self == .permission ? "需要辅助功能权限" : "没有读到选中文字" }
}

@MainActor enum SelectionReader {
    static var authorized: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        // The SDK exposes this immutable option key as a mutable C global.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    static func capture() async -> Result<CapturedSelection, SelectionFailure> {
        DiagnosticLog.shared.record(.selectionStart)
        let point = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        do { return .success(try await SelectionAX.shared.capture(pointer: point, screenTop: top)) }
        catch {
            DiagnosticLog.shared.record(.selectionUnavailable, ["reason": error.rawValue])
            return .failure(error)
        }
    }
}

private actor SelectionAX {
    static let shared = SelectionAX()
    func capture(pointer: NSPoint, screenTop: CGFloat) throws(SelectionFailure) -> CapturedSelection {
        guard !Task.isCancelled else { throw .unavailable }
        guard AXIsProcessTrusted() else { throw .permission }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        guard let raw = attribute(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw SelectionFailure.unavailable }
        let element = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.5)
        let range = selectedRange(element)
        let value = attribute(element, kAXValueAttribute) as? String
        var selected = attribute(element, kAXSelectedTextAttribute) as? String
        if selected == nil, let range, let value, valid(range, in: value) {
            selected = (value as NSString).substring(with: range)
        }
        guard let selected else { throw SelectionFailure.unavailable }
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SelectionFailure.empty }
        var context: String?
        if let range {
            if let value, value.utf16.count < 200_000 {
                context = SelectionContext.sentence(in: value, selected: selected, range: range)
            }
            if context == nil { context = nearbySentence(element, selected: selected, range: range) }
        }
        DiagnosticLog.shared.record(.selectionAX, ["characters": selected.utf16.count, "context": context?.utf16.count ?? 0])
        return CapturedSelection(text: selected, context: context, anchor: bounds(element, range: range, top: screenTop) ?? pointer)
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length > 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func valid(_ range: NSRange, in text: String) -> Bool {
        range.location >= 0 && range.location <= text.utf16.count && range.length <= text.utf16.count - range.location
    }
    private func parameter(_ element: AXUIElement, name: String, range: NSRange) -> CFTypeRef? {
        var range = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &result) == .success else { return nil }
        return result
    }
    private func nearbySentence(_ element: AXUIElement, selected: String, range: NSRange) -> String? {
        guard let count = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber,
              range.location <= count.intValue, range.length <= count.intValue - range.location else { return nil }
        let start = max(0, range.location - 1500)
        let end = min(count.intValue, range.location + range.length + 1500)
        guard let text = parameter(element, name: kAXStringForRangeParameterizedAttribute,
                                   range: NSRange(location: start, length: end - start)) as? String else { return nil }
        let local = NSRange(location: range.location - start, length: range.length)
        guard let sentence = SelectionContext.sentence(in: text, selected: selected, range: local) else { return nil }
        // A clipped sentence at a bounded read's edge is not trusted as full context.
        if start > 0 && text.hasPrefix(sentence) { return nil }
        if end < count.intValue && text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(sentence) { return nil }
        return sentence
    }
    private func bounds(_ element: AXUIElement, range: NSRange?, top: CGFloat) -> NSPoint? {
        guard let range, let raw = parameter(element, name: kAXBoundsForRangeParameterizedAttribute, range: range),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(raw as! AXValue, .cgRect, &rect), rect.width > 0 else { return nil }
        return NSPoint(x: rect.midX, y: top - rect.maxY - 8)
    }
}
