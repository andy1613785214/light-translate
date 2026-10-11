import Foundation
import TranslationCore

final class SequenceTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let responses: [(Int, String)]
    var delayDetails = false
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = requests.count; requests.append(request)
        if index > 0 && delayDetails { try? await Task.sleep(for: .milliseconds(200)) }
        let (status, content) = responses[min(index, responses.count - 1)]
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

extension TranslationCoreTests {
    private var detailsFixture: String {
        #"{"detectedLanguage":"en","translation":"不能覆盖原译文","vocabulary":[{"word":"tentative","ipa":null,"partOfSpeech":"adj.","contextualMeaning":"暂定的","commonMeanings":["暂定的"],"collocations":["a tentative conclusion"],"examples":[{"english":"These dates are tentative.","chinese":"这些日期是暂定的。"},{"english":"We reached a tentative agreement.","chinese":"我们达成了初步协议。"}]}]}"#
    }
    func testCandidatePresetModelNamesAndEndpoints() throws {
        expectEqual(CloudService.gemini.defaultModel, "gemini-3.5-flash-lite")
        expectEqual(CloudService.deepSeek.defaultModel, "deepseek-flash")
        expectEqual(CloudService.qwenMT.defaultModel, "qwen-mt-lite")
        expectEqual(try Endpoint.cloud(CloudService.gemini.defaultEndpoint).path, "/v1beta/openai/chat/completions")
        expectEqual(try Endpoint.cloud(CloudService.deepSeek.defaultEndpoint).absoluteString, "https://api.deepseek.com/chat/completions")
        expectThrows(try QwenMTProvider(endpoint: "https://example.com/v1", apiKey: "key", vocabularyModel: ""))
        expectThrows(try CloudProvider(endpoint: "https://example.com/v1", apiKey: "key", model: "qwen-mt-lite"))
    }
    func testVendorJSONAndThinkingOptions() async throws {
        for (profile, outputType) in [(CloudJSONProfile.gemini, "json_schema"), (.deepSeek, "json_object"), (.qwen, "json_object")] {
            let transport = SequenceTransport([(200, #"{"translation":"你好。","vocabulary":[]}"#)])
            let provider = try CloudProvider(endpoint: "https://example.com/v1", apiKey: "fixture", model: "fixture", transport: transport, profile: profile)
            _ = try await provider.translate(TranslationRequest(text: "hello"))
            let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
            expectEqual((body["response_format"] as? [String: Any])?["type"] as? String, outputType)
            switch profile {
            case .gemini: expectEqual(body["reasoning_effort"] as? String, "low"); expectNil(body["thinking"])
            case .deepSeek: expectEqual((body["thinking"] as? [String: String])?["type"], "disabled"); expectNil(body["reasoning_effort"])
            case .qwen: expectEqual(body["enable_thinking"] as? Bool, false)
            default: break
            }
            expectNil(body["tools"])
        }
    }
    func testQwenMTPreservesTranslationAndUsesCorrectEnglishContext() async throws {
        for (text, translated, context) in [
            ("This conclusion is tentative.", "这个结论尚未确定。", "This conclusion is tentative."),
            ("这个结论尚未确定。", "This conclusion is tentative.", "This conclusion is tentative.")
        ] {
            let transport = SequenceTransport([(200, translated), (200, detailsFixture)])
            let provider = try QwenMTProvider(endpoint: "https://example.com/v1", apiKey: "fixture", vocabularyModel: "qwen-flash", transport: transport)
            let result = try await provider.translate(TranslationRequest(text: text))
            expectEqual(result.translation, translated)
            expectEqual(result.vocabulary.first?.word, "tentative")
            expectEqual(result.vocabulary.first?.examples.count, 2)
            expectEqual(transport.requests.count, 2)
            let mt = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
            let messages = mt["messages"] as! [[String: String]]
            expectEqual(messages.count, 1); expectEqual(messages[0]["role"], "user"); expectEqual(messages[0]["content"], text)
            expectNil(mt["response_format"])
            let options = mt["translation_options"] as! [String: String]
            expectEqual(options["target_lang"], translated == context ? "English" : "Chinese")
            let explanation = try JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as! [String: Any]
            let details = explanation["messages"] as! [[String: String]]
            let payload = try JSONSerialization.jsonObject(with: Data(details.last!["content"]!.utf8)) as! [String: String]
            expectEqual(payload["english_context"], context)
            expectEqual(payload["translation"], translated)
        }
    }
    func testQwenMTKeepsTranslationWhenDetailsFail() async throws {
        for (status, content) in [(429, ""), (200, "broken json")] {
            let transport = SequenceTransport([(200, "这个结论尚未确定。"), (status, content)])
            let provider = try QwenMTProvider(endpoint: "https://example.com/v1", apiKey: "fixture", vocabularyModel: "qwen-flash", transport: transport)
            let result = try await provider.translate(TranslationRequest(text: "This conclusion is tentative."))
            expectEqual(result.translation, "这个结论尚未确定。")
            expectTrue(result.vocabulary.isEmpty); expectFalse(result.warnings.isEmpty)
            expectEqual(transport.requests.count, 2)
        }
    }
    func testQwenMTDoesNotPublishTranslationAfterCancellation() async throws {
        let transport = SequenceTransport([(200, "这个结论尚未确定。"), (200, detailsFixture)])
        transport.delayDetails = true
        let provider = try QwenMTProvider(endpoint: "https://example.com/v1", apiKey: "fixture", vocabularyModel: "qwen-flash", transport: transport)
        let task = Task { try await provider.translate(TranslationRequest(text: "This conclusion is tentative.")) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; fail("Cancellation must not become a partial success") }
        catch is CancellationError {}
    }
}
