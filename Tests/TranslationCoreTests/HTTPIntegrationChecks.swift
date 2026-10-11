import Foundation
import TranslationCore

extension TranslationCoreTests {
    private var liveBase: String { ProcessInfo.processInfo.environment["LIGHT_TRANSLATE_TEST_BASE_URL"]! }

    func testLiveCloudRoundtripInBothDirections() async throws {
        let provider = try CloudProvider(endpoint: liveBase + "/v1", apiKey: "fixture-only-key", model: "fixture-model")
        for (text, language, translation) in [
            ("This conclusion is tentative.", "en", "这个结论尚未确定。"),
            ("这个结论尚未确定。", "zh", "This conclusion is tentative.")
        ] {
            let result = try await provider.translate(TranslationRequest(text: text))
            expectEqual(result.detectedLanguage, language)
            expectEqual(result.translation, translation)
            expectEqual(result.vocabulary.first?.examples.count, 2)
            expectEqual(result.vocabulary.first?.ipaSource, "内置美式词表")
        }
    }
    func testLiveQwenMTTwoStageTranslation() async throws {
        let provider = try CloudService.qwenMT.provider(endpoint: liveBase + "/v1", apiKey: "fixture-only-key",
            model: "qwen-mt-lite", vocabularyModel: "qwen-flash")
        for text in ["This conclusion is tentative.", "这个结论尚未确定。"] {
            let request = try TranslationRequest(text: text)
            let result = try await provider.translate(request)
            expectEqual(result.translation, request.targetLanguage == "en" ? "This conclusion is tentative." : "这个结论尚未确定。")
            expectEqual(result.vocabulary.first?.examples.count, 2)
            expectEqual(result.model, "qwen-mt-lite + qwen-flash")
        }
    }

    func testLiveRedirectCannotForwardAPIKey() async throws {
        let provider = try CloudProvider(endpoint: liveBase + "/redirect", apiKey: "fixture-only-key", model: "fixture-model")
        do { _ = try await provider.translate(TranslationRequest(text: "hello")); fail("Redirect must fail") }
        catch TranslationError.http(let status) { expectEqual(status, 307) }
        let (data, _) = try await PrivateHTTPTransport().send(URLRequest(url: URL(string: liveBase + "/stats")!))
        let stats = try JSONSerialization.jsonObject(with: data) as! [String: Int]
        expectEqual(stats["redirectHits"], 0)
    }

    func testLiveAuthenticationAndMalformedResponseErrors() async throws {
        let unauthorized = try CloudProvider(endpoint: liveBase + "/unauthorized", apiKey: "fixture-only-key", model: "m")
        do { _ = try await unauthorized.translate(TranslationRequest(text: "hello")); fail("Authentication must fail") }
        catch TranslationError.http(let status) { expectEqual(status, 401) }
        let malformed = try CloudProvider(endpoint: liveBase + "/malformed", apiKey: "fixture-only-key", model: "m")
        do { _ = try await malformed.translate(TranslationRequest(text: "hello")); fail("Malformed response must fail") }
        catch TranslationError.invalidResponse {}
    }

    func testLiveTimeoutAndCancellation() async throws {
        let transport = PrivateHTTPTransport()
        let url = URL(string: liveBase + "/slow")!
        do { _ = try await transport.send(URLRequest(url: url, timeoutInterval: 0.2)); fail("Slow request must time out") }
        catch TranslationError.timedOut {}
        let task = Task { try await transport.send(URLRequest(url: url, timeoutInterval: 10)) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; fail("Cancelled HTTP request must fail") }
        catch is CancellationError {}
    }
}
