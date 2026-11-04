import Foundation

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward a bearer credential to a redirected endpoint.
        completionHandler(nil)
    }
}

public struct TranslationClient: Sendable {
    public init() {}
    public func translate(text: String, context: String?, source: Language, target: Language,
                          configuration: Configuration, key: String,
                          onText: @Sendable (String) async -> Void) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranslationError.emptyInput }
        guard !key.isEmpty else { throw TranslationError.missingKey }
        guard !configuration.wireModel.isEmpty else { throw TranslationError.missingModel }
        var request = URLRequest(url: try configuration.completionsURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let system = PromptTemplate.system(configuration.prompt, source: source, target: target, hasContext: context != nil)
        let body: [String: Any] = ["model": configuration.wireModel, "stream": true,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": PromptTemplate.user(text: text, context: context)]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let options = URLSessionConfiguration.ephemeral
        options.httpShouldSetCookies = false
        options.urlCredentialStorage = nil
        let session = URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.invalidStream }
        guard (200..<300).contains(http.statusCode) else { throw TranslationError.http(http.statusCode) }
        var decoder = StreamDecoder()
        var received = false
        var finished = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            switch try decoder.consume(line) {
            case .text(let text): received = true; await onText(text)
            case .finished: finished = true
            case .ignored: break
            }
            if finished { break }
        }
        try Task.checkCancellation()
        guard finished else { throw TranslationError.incompleteStream }
        guard received else { throw TranslationError.emptyResponse }
    }
}
