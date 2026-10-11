import Foundation
import TranslationCore

// Fixed UI fixture: preview bundles never need an API request or a global shortcut.
enum UIPreviewFixture {
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
