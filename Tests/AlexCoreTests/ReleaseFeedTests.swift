import Foundation
import Testing
@testable import AlexCore

@Test func releaseVersionsCompareNumerically() {
    #expect(ReleaseFeed.isNewer("v0.1.10", than: "0.1.9"))
    #expect(ReleaseFeed.isNewer("0.2", than: "0.1.9"))
    #expect(!ReleaseFeed.isNewer("v0.1.1", than: "0.1.1"))
    #expect(!ReleaseFeed.isNewer("1.0", than: "1.0.0"))
    #expect(!ReleaseFeed.isNewer("0.1.0", than: "0.1.1"))
    #expect(!ReleaseFeed.isNewer("0.1.2-beta", than: "0.1.1"))
}

@Test func latestReleasePicksTheUpdateArchiveForItsVersion() throws {
    func release(_ assets: [String]) -> Data {
        let list = assets.map { "{\"name\":\"\($0)\",\"browser_download_url\":\"https://example.com/\($0)\"}" }
        return Data("""
        {"tag_name":"v0.1.2","body":"取词修复","html_url":"https://example.com/v0.1.2",
         "assets":[\(list.joined(separator: ","))]}
        """.utf8)
    }
    let info = try ReleaseFeed.parse(release(["Alex-0.1.2.dmg", "Alex-0.1.1.zip", "Alex-0.1.2.zip"]))
    #expect(info.version == "0.1.2")
    #expect(info.notes == "取词修复")
    #expect(info.archive.lastPathComponent == "Alex-0.1.2.zip")
    #expect(throws: UpdateError.noArchive) { try ReleaseFeed.parse(release(["Alex-0.1.2.dmg", "Alex-0.1.1.zip"])) }
}
