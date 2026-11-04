import AppKit
import SwiftUI

struct PanelDivider: NSViewRepresentable {
    @Binding var ratio: Double
    var area: CGFloat
    func makeNSView(context: Context) -> DividerHandle { DividerHandle() }
    func updateNSView(_ view: DividerHandle, context: Context) {
        view.ratio = ratio; view.area = area
        view.change = { ratio = $0 }
    }
}

final class DividerHandle: NSView {
    var ratio = 0.5
    var area: CGFloat = 1
    var change: ((Double) -> Void)?
    private var startY: CGFloat = 0
    private var startRatio = 0.5
    override var mouseDownCanMoveWindow: Bool { false }
    // The panel never activates alex, and cursor rects only apply in the active app, so track the pointer directly.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeUpDown.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.resizeUpDown.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.35).setFill()
        NSRect(x: 12, y: bounds.midY - 0.5, width: max(0, bounds.width - 24), height: 1).fill()
        NSColor.labelColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 19, y: bounds.midY - 2, width: 38, height: 4),
                     xRadius: 2, yRadius: 2).fill()
    }
    override func mouseDown(with event: NSEvent) { startY = event.locationInWindow.y; startRatio = ratio }
    override func mouseDragged(with event: NSEvent) { setRatio(startRatio + (startY - event.locationInWindow.y) / max(area, 1)) }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event) }
    private func setRatio(_ value: Double) { change?(min(max(value, 0.15), 0.85)) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
    override func accessibilityLabel() -> String? { "调整原文和译文高度" }
    override func accessibilityValue() -> Any? { NSNumber(value: ratio) }
    override func accessibilityPerformIncrement() -> Bool { setRatio(ratio + 0.05); return true }
    override func accessibilityPerformDecrement() -> Bool { setRatio(ratio - 0.05); return true }
}
