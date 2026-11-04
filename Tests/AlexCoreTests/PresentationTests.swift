import AlexCore
import Foundation
import Testing

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let size = CGSize(width: 432, height: 400)

@Test func followMouseFlipsAwayFromScreenEdgesAndStaysInside() {
    let open = PanelPlacement.origin(size: size, anchor: CGPoint(x: 300, y: 700), position: .mouse, in: screen)
    #expect(open == CGPoint(x: 312, y: 288))
    // Near the bottom-right corner the panel moves to the cursor's upper-left instead of covering it.
    let corner = PanelPlacement.origin(size: size, anchor: CGPoint(x: 1400, y: 60), position: .mouse, in: screen)
    #expect(corner == CGPoint(x: 956, y: 72))
    let frame = CGRect(origin: corner, size: size)
    #expect(screen.insetBy(dx: PanelPlacement.margin, dy: PanelPlacement.margin).contains(frame))
}

@Test func selectionAndCenterPlacementsStayOnScreen() {
    let below = PanelPlacement.origin(size: size, anchor: CGPoint(x: 700, y: 600), position: .selection, in: screen)
    #expect(below == CGPoint(x: 484, y: 192))
    let edge = PanelPlacement.origin(size: size, anchor: CGPoint(x: 1430, y: 100), position: .selection, in: screen)
    #expect(edge == CGPoint(x: 1000, y: 8))
    let center = PanelPlacement.origin(size: size, anchor: CGPoint(x: 10, y: 10), position: .center, in: screen)
    #expect(center == CGPoint(x: 504, y: 250))
}

@Test func rememberedPositionReturnsToAScreenThatStillExists() {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
    // Last closed on an external display to the right that has since been unplugged.
    let lost = PanelPlacement.restore(topLeft: CGPoint(x: 2200, y: 800), size: size, screens: [laptop])
    #expect(lost == CGPoint(x: 1000, y: 400))
    let kept = PanelPlacement.restore(topLeft: CGPoint(x: 300, y: 700), size: size, screens: [laptop])
    #expect(kept == CGPoint(x: 300, y: 300))
    #expect(PanelPlacement.restore(topLeft: .zero, size: size, screens: []) == nil)
}

@Test func markdownBlocksKeepLineBreaksAndSurviveUnfinishedStreams() {
    let blocks = Markdown.blocks("## 标题\n- **一**\n- 二\n\nhello\n/həˈloʊ/\n\n```\nlet a = 1\n```")
    #expect(blocks.map(\.kind) == [.heading(2), .listItem(marker: "•", depth: 0), .listItem(marker: "•", depth: 0),
                                   .paragraph, .code])
    #expect(blocks[1].text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    // Dictionary output relies on single line breaks; Markdown would otherwise join them into one line.
    #expect(String(blocks[3].text.characters) == "hello\n/həˈloʊ/")
    #expect(String(blocks[4].text.characters) == "let a = 1")
    let partial = Markdown.blocks("1. 第一\n2. **未闭合")
    #expect(partial.map(\.kind) == [.listItem(marker: "1.", depth: 0), .listItem(marker: "2.", depth: 0)])
    #expect(String(partial[1].text.characters).contains("未闭合"))
}

@Test func savedSettingsFromEarlierVersionsStillLoad() throws {
    let stored = #"{"serviceName":"My Service","positionAtPointer":true,"chineseTarget":"english","prompt":"p","#
        + #""endpoint":"https://example.com/v1","model":"lite","target":"chinese","showSelectionIcon":true}"#
    let config = try JSONDecoder().decode(Configuration.self, from: Data(stored.utf8))
    #expect(config.endpoint == "https://example.com/v1" && config.prompt == "p" && config.chineseTarget == .english)
    #expect(config.position == .selection)
    #expect(!config.renderMarkdown && config.clipboardFallback && config.copySelectionFallback)
    #expect(config.inputShortcut == .defaultInput && config.selectionShortcut.display == "⌃⌥⇧⌘D")
}

@Test func diagnosticLogStaysBoundedAndKeepsOnlyNumbers() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("alex-log-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = DiagnosticLog(directory: dir, maximumBytes: 1_000)
    for i in 0..<200 { log.record(.requestStart, ["characters": i]) }
    log.flush()
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
    #expect(files.count == 4)
    for file in files { #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize! <= 1_000) }
}
