import CoreGraphics

/// Where the translation panel appears when it opens.
public enum PanelPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Below the selected text; below the pointer when no selection position is known.
    case selection
    /// Beside the pointer, switching sides near the screen edge.
    case mouse
    case center
    /// Where the panel was last moved to; centred until it has been moved once.
    case remembered
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .selection: "选中文字下方"
        case .mouse: "跟随鼠标"
        case .center: "屏幕中央"
        case .remembered: "上次的位置"
        }
    }
    public var explanation: String {
        switch self {
        case .selection: "划词时出现在选中文字正下方；输入翻译或读不到文字位置时，出现在鼠标指针下方。"
        case .mouse: "总在鼠标指针右下方出现；靠近屏幕边缘时换到指针的另一侧。"
        case .center: "总在鼠标所在屏幕的中央出现。"
        case .remembered: "在上次关闭时的位置出现；显示器拔掉或分辨率变化后，自动移回能看到的屏幕。"
        }
    }
}

public enum PanelPlacement {
    /// Distance kept from the screen's usable edges.
    public static let margin: CGFloat = 8
    /// Gap between the pointer and the panel, so the panel never sits under the cursor.
    static let pointerGap: CGFloat = 12

    /// Bottom-left origin in AppKit screen coordinates for a panel of `size` opened at `anchor`.
    public static func origin(size: CGSize, anchor: CGPoint, position: PanelPosition, in visible: CGRect) -> CGPoint {
        let proposed: CGPoint
        switch position {
        case .center, .remembered:
            proposed = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .selection:
            proposed = CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - margin)
        case .mouse:
            let right = anchor.x + pointerGap
            let below = anchor.y - pointerGap - size.height
            proposed = CGPoint(
                x: right + size.width <= visible.maxX - margin ? right : anchor.x - pointerGap - size.width,
                y: below >= visible.minY + margin ? below : anchor.y + pointerGap)
        }
        return CGPoint(x: clamp(proposed.x, visible.minX + margin, visible.maxX - size.width - margin),
                       y: clamp(proposed.y, visible.minY + margin, visible.maxY - size.height - margin))
    }
    /// Keeps a remembered top-left corner on a screen that still exists: the screen holding most of the old frame,
    /// else the first one, with the whole panel inside its usable area.
    public static func restore(topLeft: CGPoint, size: CGSize, screens: [CGRect]) -> CGPoint? {
        let old = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        let area = { (r: CGRect) -> CGFloat in let i = r.intersection(old); return i.isNull ? 0 : i.width * i.height }
        guard let visible = screens.max(by: { area($0) < area($1) }) else { return nil }
        return CGPoint(x: clamp(old.minX, visible.minX + margin, visible.maxX - size.width - margin),
                       y: clamp(old.minY, visible.minY + margin, visible.maxY - size.height - margin))
    }
    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), max(low, high))
    }
}
