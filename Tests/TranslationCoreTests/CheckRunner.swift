import Foundation

// A dependency-free executable test runner for machines with Command Line Tools only.
// Assertions collect failures and exit nonzero; every test below exercises production code.
private var failures: [String] = []
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures.append("\(URL(fileURLWithPath: String(describing: file)).lastPathComponent):\(line): \(message)")
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { fail("Expected \(expected), got \(actual)", file: file, line: line) }
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
func expectNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value != nil, file: file, line: line) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected an error. \(message)", file: file, line: line) } catch {}
}
func expectNoThrow<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() } catch { fail("Unexpected error: \(error)", file: file, line: line) }
}
struct CheckFailure: Error {}
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure() }; return value
}

@main
struct CheckRunner {
    static func main() async {
        let suite = TranslationCoreTests()
        var tests: [(String, () async throws -> Void)] = [
            ("single word dictionary and sentence mode", { try suite.testWordModeDetectsWordsAndPreservesSentenceMode() }),
            ("missing dictionary card remains explicit", { try suite.testMissingWordCardIsExplicitlyReported() }),
            ("blank input and whitespace", { try suite.testRejectsBlankInputAndTrimsWhitespace() }),
            ("3000-character boundary", { try suite.testInputLimitCountsCharactersWithoutTruncation() }),
            ("endpoint normalization", { try suite.testEndpointNormalization() }),
            ("cloud URL validation", { suite.testEndpointRejectsInsecureCloudAndEmbeddedCredentials() }),
            ("offline loopback restriction", { suite.testOfflineEndpointCannotBeRemote() }),
            ("complete vocabulary parsing", { try suite.testParserPreservesFullVocabulary() }),
            ("partial vocabulary recovery", { try suite.testMissingWordDetailsNeverDestroyTranslation() }),
            ("missing vocabulary warning", { try suite.testAbsentVocabularyIsReported() }),
            ("zero difficult words", { try suite.testEmptyVocabularyIsValid() }),
            ("invalid translation rejection", { suite.testInvalidTranslationFailsRatherThanDisplayingRawJSON() }),
            ("fenced and reasoning responses", { try suite.testFencedAndThinkingPrefixedResponses() }),
            ("vocabulary deduplication and cap", { try suite.testDuplicateVocabularyIsDeduplicatedAndCapped() }),
            ("cloud request contract", { try await suite.testCloudRequestUsesSelectedEndpointAndDoesNotLogKey() }),
            ("offline request and resources", { try await suite.testOllamaUsesLoopbackNoKeyNoThinkingAndBoundedResources() }),
            ("small Qwen whitelist", { suite.testOnlySupportedSmallQwenModelsAreAccepted() }),
            ("HTTP errors", { try await suite.testHTTPAuthenticationRateLimitAndServerErrors() }),
            ("missing model, no cloud fallback", { try await suite.testMissingLocalModelIsReportedWithoutCloudFallback() }),
            ("LRU isolation and eviction", { try suite.testLRUCachePartitionsProvidersModelsDirectionsAndEvicts() }),
            ("explicit and automatic language direction", { try suite.testExplicitAndAutomaticTranslationDirections() }),
            ("placeholder details rejected", { try suite.testPlaceholderDetailsAreNotDisplayedAsFacts() }),
            ("wrong-language and echoed output rejected", { try suite.testObviousWrongLanguageAndEchoAreRejected() }),
            ("cancelled late response cannot publish", { try await suite.testCancelledRequestCannotReturnLateResult() }),
            ("English word cards and distinct examples", { try suite.testChineseHeadwordsAndDuplicateExamplesAreFiltered() }),
            ("bundled American IPA and alternative readings", { suite.testBundledPronunciationLookupHandlesVariantsAndMissingWords() }),
            ("model IPA corrected and unrelated word filtered", { try suite.testPronunciationOverridesWrongModelIPAAndRejectsUnrelatedExampleWord() }),
            ("fragment examples rejected and model prompts adapted", { try suite.testExampleWordGlossesAndFragmentsAreNotPresentedAsSentences() }),
            ("instruction-like text and incomplete translation", { try suite.testInstructionLikeSourceCannotCollapseToSingleTranslatedWord() }),
            ("candidate model names and endpoint presets", { try suite.testCandidatePresetModelNamesAndEndpoints() }),
            ("vendor JSON and thinking request options", { try await suite.testVendorJSONAndThinkingOptions() }),
            ("Qwen MT translation and correct English context", { try await suite.testQwenMTPreservesTranslationAndUsesCorrectEnglishContext() }),
            ("Qwen MT retains translation when details fail", { try await suite.testQwenMTKeepsTranslationWhenDetailsFail() }),
            ("Qwen MT cancellation cannot publish partial success", { try await suite.testQwenMTDoesNotPublishTranslationAfterCancellation() }),
            ("empty browser selection fallback and empty editor refusal", { suite.testEmptyBrowserSelectionFallsBackButEmptyEditorDoesNot() }),
            ("protected selection never copies or exposes text", { suite.testProtectedFieldsNeverUseCopyOrText() })
        ]
        if ProcessInfo.processInfo.environment["LIGHT_TRANSLATE_TEST_BASE_URL"] != nil {
            tests = [
                ("real HTTP bilingual translation and complete word cards", { try await suite.testLiveCloudRoundtripInBothDirections() }),
                ("real HTTP Qwen MT two-stage translation and word cards", { try await suite.testLiveQwenMTTwoStageTranslation() }),
                ("real HTTP redirect never forwards API key", { try await suite.testLiveRedirectCannotForwardAPIKey() }),
                ("real HTTP authentication and malformed response errors", { try await suite.testLiveAuthenticationAndMalformedResponseErrors() }),
                ("real HTTP timeout and cancellation", { try await suite.testLiveTimeoutAndCancellation() })
            ]
        }
        for (name, test) in tests {
            let count = failures.count
            do { try await test() } catch { fail("\(name): \(error)") }
            print("\(failures.count == count ? "PASS" : "FAIL")  \(name)")
        }
        for failure in failures { print(failure) }
        print("\(tests.count) scenarios, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}
