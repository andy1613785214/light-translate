import Foundation
import TranslationCore

extension TranslationCoreTests {
    func testWordModeDetectsWordsAndPreservesSentenceMode() throws {
        for text in ["apple", "unanimous", "well-being", "can't", "C++", " AI "] {
            let request = try TranslationRequest(text: text)
            expectTrue(request.isSingleWord)
            let data = try unwrap(TranslationPrompt.user(request).data(using: .utf8))
            let body = try unwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            expectEqual(body["mode"], "dictionary")
        }
        for text in ["an apple", "Hello.", "123", "你好", "The proposal was approved."] {
            expectFalse(try TranslationRequest(text: text).isSingleWord)
        }
        expectEqual(try TranslationRequest(text: "apple", direction: .toEnglish).targetLanguage, "zh")
    }
    func testMissingWordCardIsExplicitlyReported() throws {
        let request = try TranslationRequest(text: "apple")
        let value = try ResultParser.parse(#"{"detectedLanguage":"en","translation":"苹果","vocabulary":[]}"#, provider: "fixture", model: "fixture")
        let result = try ResultValidator.validate(value, for: request)
        expectEqual(result.translation, "苹果")
        expectTrue(result.warnings.contains("该单词的详细解释暂不可用，请重试。"))
    }
}
