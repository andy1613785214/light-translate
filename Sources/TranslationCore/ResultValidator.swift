import Foundation
import NaturalLanguage

public enum ResultValidator {
    /// Reject obvious non-translations. This is a coarse guard, not a semantic quality score.
    public static func validate(_ result: TranslationResult, for request: TranslationRequest) throws -> TranslationResult {
        let englishWords = request.text.split(whereSeparator: { !$0.isLetter && $0 != "'" }).count
        let translatedHan = result.translation.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        if request.sourceLanguage == "en", request.targetLanguage == "zh", englishWords >= 10, translatedHan < 6 {
            throw TranslationError.message("译文过短，可能没有完整翻译原句。请重试或更换模型。")
        }
        let letterCount = request.text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        if letterCount >= 12,
           result.translation.trimmingCharacters(in: .whitespacesAndNewlines) == request.text {
            throw TranslationError.message("模型原样返回了原文，没有完成翻译。请重试，或选择 Qwen3 1.7B / 云端 API。")
        }
        if result.translation.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 12,
           LanguageDetection.detect(result.translation) != request.targetLanguage {
            throw TranslationError.message("模型返回的语言与目标语言不一致。请重试或更换模型。")
        }
        let englishContext = request.targetLanguage == "en" ? result.translation : request.text
        let contextLemmas = lemmas(englishContext)
        let relevant = result.vocabulary.filter { word in
            let expression = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: word.word) + "(?![A-Za-z])"
            if englishContext.range(of: expression, options: [.regularExpression, .caseInsensitive]) != nil { return true }
            let wordLemmas = lemmas(word.word)
            return !wordLemmas.isEmpty && wordLemmas.isSubset(of: contextLemmas)
        }
        let selected = request.isSingleWord ? Array(relevant.prefix(1)) : relevant
        let vocabulary = selected.map { word -> VocabularyEntry in
            let dictionaryIPA = PronunciationLexicon.shared.lookup(word.word)
            return VocabularyEntry(word: word.word, ipa: dictionaryIPA ?? word.ipa, partOfSpeech: word.partOfSpeech,
                contextualMeaning: word.contextualMeaning, commonMeanings: word.commonMeanings,
                collocations: word.collocations, examples: word.examples,
                ipaSource: dictionaryIPA != nil ? "内置美式词表" : word.ipa != nil ? "模型生成（未校验）" : nil)
        }
        var warnings = result.warnings
        if request.isSingleWord && vocabulary.isEmpty {
            warnings.append("该单词的详细解释暂不可用，请重试。")
        }
        if relevant.count != result.vocabulary.count {
            warnings.append("已忽略与当前英文原文或译文无关的词卡。")
        }
        if vocabulary.allSatisfy({ $0.ipa != nil && $0.partOfSpeech != nil && $0.contextualMeaning != nil
            && !$0.commonMeanings.isEmpty && !$0.collocations.isEmpty && $0.examples.count == 2 }) {
            warnings.removeAll { $0 == "部分词解不完整；缺失内容显示为暂不可用。" }
        }
        return TranslationResult(detectedLanguage: request.sourceLanguage, translation: result.translation,
            vocabulary: vocabulary, provider: result.provider, model: result.model, warnings: warnings)
    }
    private static func lemmas(_ text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var words = Set<String>()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let word = tag?.rawValue ?? String(text[range])
            if word.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) }) {
                words.insert(word.lowercased())
            }
            return true
        }
        return words
    }
}
