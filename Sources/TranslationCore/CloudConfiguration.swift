import Foundation

public enum CloudService: String, Codable, CaseIterable, Identifiable {
    case compatible, gemini, deepSeek, qwenMT
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .compatible: return "自定义兼容服务"
        case .gemini: return "Gemini 3.5 Flash-Lite"
        case .deepSeek: return "DeepSeek V4.1 Flash"
        case .qwenMT: return "Qwen MT Lite + 词解模型"
        }
    }
    public var defaultEndpoint: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .deepSeek: return "https://api.deepseek.com"
        case .compatible, .qwenMT: return ""
        }
    }
    public var defaultModel: String {
        switch self {
        case .gemini: return "gemini-3.5-flash-lite"
        case .deepSeek: return "deepseek-flash"
        case .qwenMT: return "qwen-mt-lite"
        case .compatible: return ""
        }
    }
    public func provider(endpoint: String, apiKey: String, model: String, vocabularyModel: String = "",
                         transport: HTTPTransport = PrivateHTTPTransport()) throws -> any TranslationProvider {
        switch self {
        case .qwenMT:
            return try QwenMTProvider(endpoint: endpoint, apiKey: apiKey, model: model,
                                      vocabularyModel: vocabularyModel, transport: transport)
        default:
            return try CloudProvider(endpoint: endpoint, apiKey: apiKey, model: model,
                                     transport: transport, profile: self == .gemini ? .gemini : self == .deepSeek ? .deepSeek : .compatible)
        }
    }
}

public enum CloudJSONProfile { case compatible, gemini, deepSeek, qwen }

struct ChatCompletionClient {
    let url: URL
    let key: String
    let transport: HTTPTransport
    init(endpoint: String, apiKey: String, transport: HTTPTransport) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranslationError.missingConfiguration }
        url = try Endpoint.cloud(endpoint); key = apiKey; self.transport = transport
    }
    func complete(_ body: [String: Any]) async throws -> String {
        var http = URLRequest(url: url, timeoutInterval: 90)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.send(http)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw TranslationError.http(response.statusCode) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.invalidResponse
        }
        return content
    }
}

public struct QwenMTProvider: TranslationProvider {
    private let client: ChatCompletionClient
    private let model: String
    private let vocabularyModel: String
    private let explainer: CloudProvider
    public init(endpoint: String, apiKey: String, model: String = "qwen-mt-lite", vocabularyModel: String,
                transport: HTTPTransport = PrivateHTTPTransport()) throws {
        guard ["qwen-mt-lite", "qwen-mt-flash", "qwen-mt-plus", "qwen-mt-turbo"].contains(model),
              !vocabularyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.message("Qwen MT 只负责翻译，请填写同一百炼服务中的通用词解模型，例如 qwen-flash。")
        }
        client = try ChatCompletionClient(endpoint: endpoint, apiKey: apiKey, transport: transport)
        self.model = model; self.vocabularyModel = vocabularyModel
        explainer = try CloudProvider(endpoint: endpoint, apiKey: apiKey, model: vocabularyModel,
                                      transport: transport, profile: .qwen)
    }
    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let translated = try await client.complete([
            "model": model, "stream": false,
            "messages": [["role": "user", "content": request.text]],
            "translation_options": ["source_lang": request.sourceLanguage == "en" ? "English" : "Chinese",
                                    "target_lang": request.targetLanguage == "en" ? "English" : "Chinese"]
        ])
        let base = try ResultValidator.validate(TranslationResult(detectedLanguage: request.sourceLanguage,
            translation: translated, vocabulary: [], provider: "Qwen MT", model: model, warnings: []), for: request)
        try Task.checkCancellation()
        do {
            return try await explainer.explain(request, translation: base.translation, translationModel: model)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            return TranslationResult(detectedLanguage: base.detectedLanguage, translation: base.translation,
                vocabulary: [], provider: "Qwen MT", model: model,
                warnings: ["译文已保留，词解请求失败：\(error.localizedDescription)"])
        }
    }
}
