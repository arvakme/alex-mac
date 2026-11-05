import Foundation

/// The newest published release and the archive the in-app updater installs.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let notes: String
    public let archive: URL
    public let page: URL
}

public enum UpdateError: Error, Equatable, LocalizedError {
    case unreadable, noArchive, http(Int), signatureMismatch, wrongVersion, unpackFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable: "发布信息无法读取。"
        case .noArchive: "这个版本没有可在应用内安装的更新包，请到发布页手动下载。"
        case .http(let status): "下载失败（HTTP \(status)）。"
        case .signatureMismatch: "更新包的签名和当前版本不一致，已放弃安装。"
        case .wrongVersion: "更新包里的版本和发布信息不一致，已放弃安装。"
        case .unpackFailed: "更新包无法解压。"
        }
    }
}

/// Reads the GitHub "latest release" of the public repository; pre-releases and drafts never appear there.
public enum ReleaseFeed {
    public static let latestURL = URL(string: "https://api.github.com/repos/arvakme/alex-mac/releases/latest")!

    /// Dotted numeric versions, an optional leading "v"; anything else is never treated as newer.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else { return false }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0, b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func components(_ version: String) -> [Int]? {
        let parts = version.drop(while: { $0 == "v" }).split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count && !numbers.isEmpty ? numbers : nil
    }

    public static func archiveName(for version: String) -> String { "Alex-\(version).zip" }

    public static func parse(_ data: Data) throws -> ReleaseInfo {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable { let tag_name: String; let body: String?; let html_url: URL; let assets: [Asset] }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { throw UpdateError.unreadable }
        let version = String(release.tag_name.drop(while: { $0 == "v" }))
        guard let archive = release.assets.first(where: { $0.name == archiveName(for: version) }) else {
            throw UpdateError.noArchive
        }
        return ReleaseInfo(version: version, notes: release.body ?? "", archive: archive.browser_download_url,
                           page: release.html_url)
    }

    public static func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try parse(data)
    }

    /// Downloads to a file the caller owns.
    public static func download(_ url: URL, into directory: URL) async throws -> URL {
        let (temporary, response) = try await session.download(from: url)
        try check(response)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private static let session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.httpShouldSetCookies = false
        options.urlCredentialStorage = nil
        return URLSession(configuration: options)
    }()

    private static func check(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw UpdateError.http(status) }
    }
}
