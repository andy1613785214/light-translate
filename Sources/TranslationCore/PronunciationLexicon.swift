import Foundation

/// An immutable memory-mapped sorted wordlist, loaded only when a word card needs pronunciation.
/// Keeps a compact line-offset index rather than allocating a dictionary of 125,000 Swift strings.
public final class PronunciationLexicon {
    public static let shared = PronunciationLexicon()
    private let data: Data
    private let offsets: [Int]
    public var entryCount: Int { offsets.count }

    private init() {
        let name = "LightTranslate_TranslationCore.bundle"
        let packaged = Bundle.main.resourceURL?.appendingPathComponent(name)
        #if DISTRIBUTION
        let sibling = Bundle.main.bundleURL.appendingPathComponent(name)
        let bundle = packaged.flatMap { Bundle(url: $0) } ?? Bundle(url: sibling)
        let loadedData = (bundle?.url(forResource: "en_US", withExtension: "tsv")
            .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }) ?? Data()
        #else
        let bundle = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
        let loadedData = (bundle.url(forResource: "en_US", withExtension: "tsv")
            .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }) ?? Data()
        #endif
        data = loadedData
        offsets = loadedData.withUnsafeBytes { bytes -> [Int] in
            guard !bytes.isEmpty else { return [] }
            var lines = [0]
            for position in 0..<bytes.count where bytes[position] == 10 && position + 1 < bytes.count {
                lines.append(position + 1)
            }
            return lines
        }
    }

    public func lookup(_ word: String) -> String? {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "’", with: "'")
        guard !normalized.isEmpty, normalized.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        let key = Array(normalized.utf8)
        return data.withUnsafeBytes { bytes -> String? in
            var low = 0, high = offsets.count
            while low < high {
                let middle = (low + high) / 2
                let start = offsets[middle]
                var tab = start
                while tab < bytes.count && bytes[tab] != 9 && bytes[tab] != 10 { tab += 1 }
                let length = tab - start
                var comparison = 0
                for position in 0..<min(length, key.count) {
                    if bytes[start + position] != key[position] {
                        comparison = bytes[start + position] < key[position] ? -1 : 1
                        break
                    }
                }
                if comparison == 0 && length != key.count { comparison = length < key.count ? -1 : 1 }
                if comparison < 0 { low = middle + 1 }
                else if comparison > 0 { high = middle }
                else {
                    guard tab < bytes.count, bytes[tab] == 9 else { return nil }
                    let end = middle + 1 < offsets.count ? offsets[middle + 1] - 1 : bytes.count
                    let text = String(decoding: bytes[(tab + 1)..<end], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                }
            }
            return nil
        }
    }
}
