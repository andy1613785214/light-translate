import Foundation
import NaturalLanguage

public enum TranslationDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, toChinese, toEnglish
    public var id: String { rawValue }
    public var title: String {
        switch self { case .automatic: return "自动识别"; case .toChinese: return "英 → 中"; case .toEnglish: return "中 → 英" }
    }
}

public enum ProviderMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case cloud, local
    public var id: String { rawValue }
    public var title: String { self == .cloud ? "云端 API" : "本地 Qwen3" }
}

public enum LocalModels {
    public static let supported = ["qwen3:1.7b", "qwen3:0.6b"]
    public static func preferred(installed: [String]) -> String {
        supported.first(where: installed.contains) ?? supported[0]
    }
}

public struct TranslationRequest: Sendable {
    public let text: String
    public let direction: TranslationDirection
    public let difficulty: String
    public var isSingleWord: Bool { WordSelection.isSingleEnglishWord(text) }
    public var sourceLanguage: String { isSingleWord ? "en" : LanguageDetection.detect(text) }
    public var targetLanguage: String {
        if isSingleWord { return "zh" }
        switch direction {
        case .toChinese: return "zh"
        case .toEnglish: return "en"
        case .automatic: return sourceLanguage == "zh" ? "en" : "zh"
        }
    }
    public init(text: String, direction: TranslationDirection = .automatic) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }
        guard trimmed.count <= 3_000 else { throw TranslationError.inputTooLong }
        self.text = trimmed
        self.direction = direction
        self.difficulty = "大学英语六级及以上，兼顾熟词生义、专业术语和固定短语"
    }
}

public enum WordSelection {
    public static func isSingleEnglishWord(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 80 else { return false }
        return value.range(of: #"^[A-Za-z]+(?:['’\-][A-Za-z]+)*(?:\+\+|#)?$"#, options: .regularExpression) != nil
    }
}

public enum LanguageDetection {
    public static func detect(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .simplifiedChinese, .traditionalChinese]
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage {
            return language == .english ? "en" : "zh"
        }
        return text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } ? "zh" : "en"
    }
}

public struct UsageExample: Codable, Identifiable, Sendable {
    public var id: String { english + chinese }
    public let english: String
    public let chinese: String
    public init(english: String, chinese: String) { self.english = english; self.chinese = chinese }
}

public struct VocabularyEntry: Codable, Identifiable, Sendable {
    public var id: String { word }
    public let word: String
    public let ipa: String?
    public let partOfSpeech: String?
    public let contextualMeaning: String?
    public let commonMeanings: [String]
    public let collocations: [String]
    public let examples: [UsageExample]
    public let ipaSource: String?
    public init(word: String, ipa: String?, partOfSpeech: String?, contextualMeaning: String?,
                commonMeanings: [String], collocations: [String], examples: [UsageExample], ipaSource: String? = nil) {
        self.word = word; self.ipa = ipa; self.partOfSpeech = partOfSpeech; self.contextualMeaning = contextualMeaning
        self.commonMeanings = commonMeanings; self.collocations = collocations; self.examples = examples; self.ipaSource = ipaSource
    }
}

public struct TranslationResult: Codable, Sendable {
    public let detectedLanguage: String
    public let translation: String
    public let vocabulary: [VocabularyEntry]
    public let provider: String
    public let model: String
    public let warnings: [String]
}

public enum TranslationError: LocalizedError {
    case emptyInput, inputTooLong, invalidEndpoint, missingConfiguration, invalidResponse, unsupportedModel
    case http(Int), network, timedOut, localUnavailable, localModelMissing, message(String)
    public var errorDescription: String? {
        switch self {
        case .emptyInput: return "请先划选或粘贴需要翻译的文字。"
        case .inputTooLong: return "单次最多翻译 3,000 字符，请缩短选区。"
        case .invalidEndpoint: return "API 地址无效。云端需要 HTTPS；本地服务仅允许环回地址。"
        case .missingConfiguration: return "请在设置中填写 API 地址、模型和密钥。"
        case .invalidResponse: return "模型没有返回可读取的译文。请重试或更换模型。"
        case .unsupportedModel: return "本地仅支持 qwen3:1.7b 和 qwen3:0.6b。"
        case .http(401), .http(403): return "API 认证失败，请检查密钥和访问权限。"
        case .http(429): return "服务限流或额度不足，请稍后重试并检查账户额度。"
        case .http(let status): return "翻译服务返回 HTTP \(status)，请检查设置或稍后重试。"
        case .network: return "无法连接翻译服务。请检查网络，或手动切换到本地模型。"
        case .timedOut: return "翻译超时，可以重试；本地首次加载通常较慢。"
        case .localUnavailable: return "本地服务未能启动。请确认已安装 Ollama，并在设置中检查可执行文件路径。"
        case .localModelMissing: return "所选 Qwen3 模型尚未下载。请联网时按设置页说明提前下载。"
        case .message(let text): return text
        }
    }
}

public struct CacheKey: Hashable {
    public let text: String
    public let direction: String
    public let provider: String
    public let endpoint: String
    public let model: String
    public init(request: TranslationRequest, provider: String, endpoint: String, model: String) {
        self.text = request.text; self.direction = request.direction.rawValue
        self.provider = provider; self.endpoint = endpoint; self.model = model
    }
}

public struct ResultCache {
    private var values: [CacheKey: TranslationResult] = [:]
    private var order: [CacheKey] = []
    private let capacity: Int
    public init(capacity: Int = 50) { self.capacity = max(1, capacity) }
    public mutating func value(for key: CacheKey) -> TranslationResult? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return value
    }
    public mutating func insert(_ value: TranslationResult, for key: CacheKey) {
        values[key] = value; order.removeAll { $0 == key }; order.append(key)
        while order.count > capacity { values.removeValue(forKey: order.removeFirst()) }
    }
    public mutating func removeAll() { values.removeAll(); order.removeAll() }
}
