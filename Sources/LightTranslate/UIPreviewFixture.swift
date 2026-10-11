import Foundation
import TranslationCore

// Fixed UI fixture: preview bundles never need an API request or a global shortcut.
enum UIPreviewFixture {
    static let longSource = "A unanimous decision can support long-term prosperity when committee members carefully review the evidence and discuss the proposal."
    static var longResult: TranslationResult? { fixture(translation: "经过充分讨论，委员会达成了一致决定。成员们仔细核查了证据，并评估了提案的长期影响，认为它有助于当地的发展与繁荣。", wordCount: 2) }
    static var overflowResult: TranslationResult? { fixture(translation: String(repeating: "委员会成员仔细核查证据，并讨论了提案对长期发展的影响。", count: 45), wordCount: 2) }
    private static func fixture(translation: String, wordCount: Int) -> TranslationResult? {
        guard let sample = result,
              let data = try? JSONEncoder().encode(sample),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var words = json["vocabulary"] as? [[String: Any]], let first = words.first else { return nil }
        if wordCount == 2 {
            var second = first
            second["word"] = "prosperity"; second["contextualMeaning"] = "繁荣"
            second["ipa"] = PronunciationLexicon.shared.lookup("prosperity")
            second["partOfSpeech"] = "noun"
            second["commonMeanings"] = ["繁荣", "兴旺"]
            second["collocations"] = ["economic prosperity", "shared prosperity"]
            second["examples"] = [
                ["english": "The city enjoyed a period of prosperity.", "chinese": "这座城市经历了一段繁荣时期。"],
                ["english": "Education contributes to long-term prosperity.", "chinese": "教育有助于长期繁荣。"]
            ]
            words.append(second)
        }
        json["translation"] = translation; json["vocabulary"] = words
        guard let changed = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(TranslationResult.self, from: changed)
    }
    static var result: TranslationResult? {
        try? JSONDecoder().decode(TranslationResult.self, from: Data("""
        {
          "detectedLanguage": "en",
          "translation": "委员会达成了一致决定。",
          "provider": "UI fixture",
          "model": "布局预览",
          "warnings": [],
          "vocabulary": [{
            "word": "unanimous",
            "ipa": "/juˈnænəməs/",
            "partOfSpeech": "adj.",
            "contextualMeaning": "一致同意的；全体赞成的",
            "commonMeanings": ["全体一致的", "无异议的"],
            "collocations": ["unanimous decision", "unanimous approval"],
            "ipaSource": "界面测试样例",
            "examples": [
              {"english": "The proposal received unanimous approval.", "chinese": "这项提议获得了一致通过。"},
              {"english": "The judges were unanimous in their decision.", "chinese": "评委们对这一决定意见一致。"}
            ]
          }]
        }
        """.utf8))
    }
}
