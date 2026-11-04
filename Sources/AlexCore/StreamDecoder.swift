import Foundation

public enum TranslationError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint, missingKey, missingModel, emptyInput, invalidStream, incompleteStream, emptyResponse
    case http(Int), rejected, truncated
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "接口地址应为 HTTPS 地址（本机测试可用 HTTP），不能包含账号、密码或查询参数。"
        case .missingKey: "请先在设置 → 服务中保存 API Key。"
        case .missingModel: "请填写模型名称。"
        case .emptyInput: "请输入要翻译的文字。"
        case .invalidStream: "服务返回了无法解析的流式数据。"
        case .incompleteStream: "连接提前结束，译文可能不完整。请重试。"
        case .emptyResponse: "服务没有返回译文，请检查模型后重试。"
        case .rejected: "服务拒绝了请求，请检查模型与服务配置。"
        case .truncated: "服务提前停止生成，译文不完整。请缩短原文后重试。"
        case .http(401), .http(403): "API Key 无效或没有访问权限，请检查服务设置。"
        case .http(429): "服务请求过多或额度不足，请稍后重试。"
        case .http(let code): "翻译服务返回 HTTP \(code)，请检查接口后重试。"
        }
    }
}

public enum StreamEvent: Equatable, Sendable { case ignored, text(String), finished }
public struct StreamDecoder {
    public init() {}
    public mutating func consume(_ line: String) throws -> StreamEvent {
        guard line.hasPrefix("data:") else { return .ignored }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return .ignored }
        if payload == "[DONE]" { return .finished }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidStream
        }
        if object["error"] != nil { throw TranslationError.rejected }
        guard let choices = object["choices"] as? [[String: Any]] else { throw TranslationError.invalidStream }
        guard let choice = choices.first else { return .ignored }
        if let reason = choice["finish_reason"] as? String {
            guard reason == "stop" else { throw TranslationError.truncated }
            return .finished
        }
        guard let delta = choice["delta"] as? [String: Any] else { throw TranslationError.invalidStream }
        if let text = delta["content"] as? String, !text.isEmpty { return .text(text) }
        return .ignored
    }
}
