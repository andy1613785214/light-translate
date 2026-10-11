import Foundation
import TranslationCore

struct EvalCase: Codable {
    let id: Int
    let category: String
    let text: String
    let direction: TranslationDirection
    let reviewFocus: String
}
struct EvalOutput: Codable {
    let id: Int
    let category: String
    let text: String
    let reviewFocus: String
    let durationSeconds: Double
    let result: TranslationResult?
    let error: String?
}

@main
struct TranslationEval {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            if arguments.count == 5, arguments[1] == "--revalidate" {
                let saved = try JSONDecoder().decode([EvalOutput].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
                let cases = try JSONDecoder().decode([EvalCase].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
                var checked: [EvalOutput] = []
                for output in saved {
                    guard let item = cases.first(where: { $0.id == output.id && $0.text == output.text }) else {
                        throw TranslationError.message("评估案例与保存结果不匹配。")
                    }
                    var result = output.result, error = output.error
                    if let value = result {
                        do { result = try ResultValidator.validate(value, for: TranslationRequest(text: item.text, direction: item.direction)) }
                        catch let failure { result = nil; error = failure.localizedDescription }
                    }
                    checked.append(EvalOutput(id: output.id, category: output.category, text: output.text,
                        reviewFocus: output.reviewFocus, durationSeconds: output.durationSeconds, result: result, error: error))
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(checked).write(to: URL(fileURLWithPath: arguments[4]), options: .atomic)
                print("Revalidated \(checked.count) saved responses; \(checked.filter { $0.error != nil }.count) rejected. No model requests made.")
                return
            }
            guard arguments.count >= 5 else {
                print("Usage: TranslationEval <http://127.0.0.1:port> <qwen3:0.6b|qwen3:1.7b> <cases.json> <output.json> [limit]")
                Foundation.exit(2)
            }
            guard let url = URL(string: arguments[1]) else { throw TranslationError.invalidEndpoint }
            let provider = try OllamaProvider(baseURL: url, model: arguments[2])
            let cases = try JSONDecoder().decode([EvalCase].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
            let limit = arguments.count > 5 ? Int(arguments[5]) ?? cases.count : cases.count
            var outputs: [EvalOutput] = []
            for item in cases.prefix(limit) {
                let start = Date()
                do {
                    let result = try await provider.translate(TranslationRequest(text: item.text, direction: item.direction))
                    outputs.append(EvalOutput(id: item.id, category: item.category, text: item.text, reviewFocus: item.reviewFocus,
                        durationSeconds: Date().timeIntervalSince(start), result: result, error: nil))
                    print("Case \(item.id): OK, \(result.vocabulary.count) words, \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
                } catch {
                    outputs.append(EvalOutput(id: item.id, category: item.category, text: item.text, reviewFocus: item.reviewFocus,
                        durationSeconds: Date().timeIntervalSince(start), result: nil, error: error.localizedDescription))
                    print("Case \(item.id): FAILED — \(error.localizedDescription)")
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(outputs).write(to: URL(fileURLWithPath: arguments[4]), options: .atomic)
            }
            if outputs.contains(where: { $0.error != nil }) { Foundation.exit(1) }
        } catch { print(error.localizedDescription); Foundation.exit(1) }
    }
}
