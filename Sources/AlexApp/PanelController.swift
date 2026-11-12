import AlexCore
import AppKit
import SwiftUI

enum PanelPresentation { case floating, menuBar }

final class TranslationPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}

@MainActor final class PanelController: NSObject, NSWindowDelegate {
    let model: AppModel
    private(set) var panel: TranslationPanel!
    private var settingsWindow: NSWindow?
    private var mouseMonitor: Any?
    /// Width, and the height the panel grows to before its texts scroll; set by resizing.
    private var size = PanelSizeMemory.load()
    private var idealHeight: CGFloat = 0
    private var fitPending = false
    init(model: AppModel) {
        self.model = model
        super.init()
        let root = TranslationView(model: model, close: { [weak self] in self?.hide() }, settings: { [weak self] in self?.showSettings() },
                                   fit: { [weak self] in self?.fit($0) })
        let host = NSHostingView(rootView: root)
        // The controller owns the panel size; SwiftUI supplies only the resize limits.
        host.sizingOptions = [.minSize, .maxSize]
        panel = TranslationPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.title = "alex 翻译"
        panel.identifier = NSUserInterfaceItemIdentifier("alex.translation")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.onClose = { [weak self] in self?.hide() }
        panel.delegate = self
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfUnpinned() }
        }

    }
    func showInput(anchor: NSPoint? = nil, presentation: PanelPresentation = .floating) {
        model.prepare()
        show(anchor: anchor, presentation: presentation)
    }
    func showSelection(_ selection: CapturedSelection) {
        model.prepare(text: selection.text, context: selection.context, fromClipboard: selection.fromClipboard)
        show(anchor: selection.anchor)
        model.translate()
    }
    func selectionFailed(_ failure: SelectionFailure) {
        model.prepare()
        model.phase = .noSelection(failure)
        show(anchor: NSEvent.mouseLocation)
    }
    private func show(anchor: NSPoint?, presentation: PanelPresentation = .floating) {
        model.presentation = presentation
        panel.isMovable = presentation == .floating
        panel.contentView?.layoutSubtreeIfNeeded()
        // The menu-bar panel always hangs below its icon, whatever the opening position setting says.
        let position = presentation == .menuBar ? PanelPosition.selection : model.configuration.position
        let point = position == .mouse ? NSEvent.mouseLocation : anchor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        panel.setContentSize(NSSize(width: size.width, height: targetHeight(in: bounds)))
        let screens = NSScreen.screens.map(\.visibleFrame)
        if position == .remembered, let topLeft = PanelSizeMemory.topLeft(),
           let origin = PanelPlacement.restore(topLeft: topLeft, size: panel.frame.size, screens: screens) {
            panel.setFrameOrigin(origin)
        } else {
            panel.setFrameOrigin(PanelPlacement.origin(size: panel.frame.size, anchor: point, position: position, in: bounds))
        }
        panel.makeKeyAndOrderFront(nil)
        focusText(in: panel.contentView)
    }
    /// Called from SwiftUI's update pass. Resizing there lays the view out again inside the same pass, so any disagreement
    /// between measurements would loop without ever returning to the event loop; the resize waits for the next turn.
    private func fit(_ ideal: CGFloat) {
        idealHeight = ideal
        guard !fitPending else { return }
        fitPending = true
        Task { @MainActor [weak self] in self?.applyFit() }
    }
    private func applyFit() {
        fitPending = false
        guard panel.isVisible, !panel.inLiveResize, let bounds = panel.screen?.visibleFrame else { return }
        var frame = panel.frame
        let height = targetHeight(in: bounds)
        guard abs(frame.height - height) >= 1 else { return }
        // Grow and shrink downward so the header stays where the reader is looking.
        frame.origin.y = max(frame.maxY - height, bounds.minY + 8)
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }
    private func targetHeight(in bounds: NSRect) -> CGFloat {
        min(max(idealHeight, TranslationPanelStyle.minSize.height), size.height, bounds.height - 16)
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        size = panel.frame.size
        PanelSizeMemory.save(size)
        PanelSizeMemory.saveTopLeft(NSPoint(x: panel.frame.minX, y: panel.frame.maxY))
    }
    func windowDidMove(_ notification: Notification) {
        // Only a move the reader made counts; opening the panel also moves it.
        guard panel.isVisible, NSEvent.pressedMouseButtons != 0 else { return }
        PanelSizeMemory.saveTopLeft(NSPoint(x: panel.frame.minX, y: panel.frame.maxY))
    }
    func windowDidResize(_ notification: Notification) {
        (notification.object as? NSWindow)?.invalidateShadow()
    }
    private func focusText(in view: NSView?) {
        guard let view else { return }
        if let editor = view as? NSTextView { panel.makeFirstResponder(editor); return }
        for child in view.subviews { focusText(in: child) }
    }
    func showSettings(tab: Int? = nil) {
        // A floating panel would cover the settings it opened.
        dismissIfUnpinned()
        let window = settingsWindow ?? SettingsWindow.make(model: model)
        settingsWindow = window
        if let tab { (window.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = tab }
        // alex is an accessory app whose panel never activates it; without activating, the window opens behind
        // whichever app is in front.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    func hide() { model.stop(); panel.orderOut(nil) }
    func dismissIfUnpinned() { if !model.pinned { hide() } }
    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        panel.orderOut(nil); settingsWindow?.orderOut(nil)
    }
}

private enum PanelSizeMemory {
    static let key = "translationPanelSize"
    static func load() -> CGSize {
        guard let saved = UserDefaults.standard.dictionary(forKey: key),
              let width = saved["width"] as? Double, let height = saved["height"] as? Double
        else { return TranslationPanelStyle.defaultSize }
        let min = TranslationPanelStyle.minSize, max = TranslationPanelStyle.maxSize
        return CGSize(width: Swift.min(Swift.max(width, min.width), max.width),
                      height: Swift.min(Swift.max(height, min.height), max.height))
    }
    static func save(_ size: CGSize) {
        UserDefaults.standard.set(["width": size.width, "height": size.height], forKey: key)
    }
    static let originKey = "translationPanelTopLeft"
    static func topLeft() -> NSPoint? {
        guard let saved = UserDefaults.standard.dictionary(forKey: originKey),
              let x = saved["x"] as? Double, let y = saved["y"] as? Double else { return nil }
        return NSPoint(x: x, y: y)
    }
    static func saveTopLeft(_ point: NSPoint) {
        UserDefaults.standard.set(["x": point.x, "y": point.y], forKey: originKey)
    }
}
