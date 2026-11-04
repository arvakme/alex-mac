import Foundation
import Testing
@testable import AlexCore

private final class Fixture {
    let process = Process()
    let base: String
    init() throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/translation_server.py")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.availableData
        base = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.hasPrefix("http://127.0.0.1:") else { throw TranslationError.invalidEndpoint }
    }
    func stop() { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    func config(_ route: String = "") -> Configuration {
        var config = Configuration()
        config.endpoint = base + route + "/v1"
        config.model = " test-model "
        return config
    }
}
private actor Output {
    var chunks: [String] = []
    func append(_ chunk: String) { chunks.append(chunk) }
    func text() -> String { chunks.joined() }
    func count() -> Int { chunks.count }
}

@Test func actualHTTPStreamingAndFailureResponses() async throws {
    let fixture = try Fixture()
    defer { fixture.stop() }
    let output = Output()
    try await TranslationClient().translate(text: "ephemeral", context: nil, source: .english,
        target: .chinese, configuration: fixture.config(), key: "alex-local-fixture") { await output.append($0) }
    #expect(await output.count() == 3)
    #expect(await output.text().contains("短暂的"))
    #expect(await !output.text().contains("在这句里"))
    for (route, expected) in [("/unauthorized", TranslationError.http(401)), ("/rate-limit", .http(429)),
                              ("/redirect", .http(307)), ("/malformed", .invalidStream),
                              ("/disconnect", .incompleteStream), ("/empty", .emptyResponse)] {
        do {
            try await TranslationClient().translate(text: "hello", context: nil, source: .english,
                target: .chinese, configuration: fixture.config(route), key: "alex-local-fixture", onText: { _ in })
            Issue.record("Expected failure for \(route)")
        } catch let error as TranslationError { #expect(error == expected) }
    }
}

@Test func cancellationStopsAnOpenHTTPStream() async throws {
    let fixture = try Fixture()
    defer { fixture.stop() }
    let output = Output()
    let config = fixture.config("/slow")
    let task = Task {
        try await TranslationClient().translate(text: "hello", context: nil, source: .english,
            target: .chinese, configuration: config, key: "alex-local-fixture") { text in
                await output.append(text)
                withUnsafeCurrentTask { $0?.cancel() }
            }
    }
    do { try await task.value; Issue.record("Cancelled stream reported completion") }
    catch { #expect(task.isCancelled) }
    #expect(await output.count() == 1)
}

@Test func keychainRoundTripAndDelete() throws {
    let store = CredentialStore(service: "com.kazelis.alex.test." + UUID().uuidString)
    defer { try? store.delete() }
    #expect(try store.read() == nil)
    try store.save("local-fixture-not-a-real-secret")
    #expect(try store.read() == "local-fixture-not-a-real-secret")
    try store.save("replacement-fixture")
    #expect(try store.read() == "replacement-fixture")
    try store.delete()
    #expect(try store.read() == nil)
}

@Test func unsafeURLsDoNotReceiveCredentials() throws {
    var config = Configuration()
    for endpoint in ["http://example.com/v1", "https://user:password@example.com/v1", "https://example.com/v1?key=secret"] {
        config.endpoint = endpoint
        #expect(throws: TranslationError.invalidEndpoint) { try config.completionsURL() }
    }
    config.endpoint = "https://example.com/v1/"
    #expect(try config.completionsURL().absoluteString == "https://example.com/v1/chat/completions")
    #expect(Configuration().wireModel.isEmpty)
}
