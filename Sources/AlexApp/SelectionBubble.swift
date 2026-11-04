import AppKit
import SwiftUI

@MainActor final class SelectionBubble {
    private let model: AppModel
    private var monitor: Any?
    private var hideTask: DispatchWorkItem?
    private var captureTask: DispatchWorkItem?
    private var dragged = false
    private var readTask: Task<Void, Never>?
    private var bubble: NSPanel?
    var onSelect: ((CapturedSelection) -> Void)?
    init(model: AppModel) { self.model = model }
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged, .scrollWheel, .keyDown, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }
    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged: dragged = true; hide()
        case .leftMouseDown: dragged = false; hide(); captureTask?.cancel()
        case .leftMouseUp:
            guard dragged || event.clickCount >= 2, model.configuration.showSelectionIcon, SelectionReader.authorized else { return }
            dragged = false
            captureTask?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.capture() }
            captureTask = work
            // Mouse-up precedes selection publication in several text controls; coalesce that gesture once.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        default: hide(); captureTask?.cancel()
        }
    }
    private func capture() {
        readTask?.cancel()
        readTask = Task { [weak self] in
            let result = await SelectionReader.capture()
            guard !Task.isCancelled, let self, self.model.configuration.showSelectionIcon,
                  case .success(let selection) = result else { return }
            self.show(selection)
        }
    }
    private func show(_ selection: CapturedSelection) {
        hide()
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = .floating; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = Button { [weak self] in
            self?.hide(); self?.onSelect?(selection)
        } label: {
            Image(systemName: "character.bubble").font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 34).glassEffect(.regular.interactive(), in: .circle)
        }.buttonStyle(.plain).help("翻译选中文字 · Hyper+D").accessibilityLabel("翻译选中文字").padding(4)
        panel.contentView = NSHostingView(rootView: root)
        let mouse = NSEvent.mouseLocation
        let bounds = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: min(mouse.x + 12, bounds.maxX - 46), y: max(mouse.y - 48, bounds.minY + 4), width: 42, height: 42), display: false)
        bubble = panel; panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    private func hide() { readTask?.cancel(); hideTask?.cancel(); bubble?.orderOut(nil); bubble = nil }
    func stop() { captureTask?.cancel(); hide(); if let monitor { NSEvent.removeMonitor(monitor) } }
}
