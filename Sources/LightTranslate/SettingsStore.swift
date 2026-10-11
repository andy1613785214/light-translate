import AppKit
import Carbon
import Security
import TranslationCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let standard = Shortcut(keyCode: 49, modifiers: UInt32(optionKey), label: "⌥ Space")
}

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    @Published var mode: ProviderMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    @Published var direction: TranslationDirection { didSet { defaults.set(direction.rawValue, forKey: "direction") } }
    @Published var endpoint: String { didSet { defaults.set(endpoint, forKey: "endpoint") } }
    @Published var cloudModel: String { didSet { defaults.set(cloudModel, forKey: "cloudModel") } }
    @Published var cloudService: CloudService { didSet { defaults.set(cloudService.rawValue, forKey: "cloudService") } }
    @Published var vocabularyModel: String { didSet { defaults.set(vocabularyModel, forKey: "vocabularyModel") } }
    @Published var localModel: String { didSet { defaults.set(localModel, forKey: "localModel") } }
    @Published var ollamaPath: String { didSet { defaults.set(ollamaPath, forKey: "ollamaPath") } }
    @Published var shortcut: Shortcut { didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Every launch starts online; offline inference always requires an explicit choice.
        mode = .cloud
        direction = TranslationDirection(rawValue: defaults.string(forKey: "direction") ?? "") ?? .automatic
        endpoint = defaults.string(forKey: "endpoint") ?? ""
        cloudModel = defaults.string(forKey: "cloudModel") ?? ""
        cloudService = CloudService(rawValue: defaults.string(forKey: "cloudService") ?? "") ?? .compatible
        vocabularyModel = defaults.string(forKey: "vocabularyModel") ?? ""
        let saved = defaults.string(forKey: "localModel")
        localModel = saved.flatMap { LocalModels.supported.contains($0) ? $0 : nil }
            ?? LocalModels.preferred(installed: Self.installedModels())
        // Persist initial choice, so later installations do not silently change it.
        ollamaPath = defaults.string(forKey: "ollamaPath") ?? Self.findOllama()
        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .standard
        if defaults.string(forKey: "legacyKeyEndpoint") == nil, !endpoint.isEmpty,
           let bound = try? Endpoint.cloud(endpoint).absoluteString {
            defaults.set(bound, forKey: "legacyKeyEndpoint")
        }
        defaults.set(localModel, forKey: "localModel")
    }
    static var modelsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["OLLAMA_MODELS"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models", isDirectory: true)
    }
    static func installedModels() -> [String] {
        LocalModels.supported.filter { model in
            FileManager.default.fileExists(atPath: modelsDirectory
                .appendingPathComponent("manifests/registry.ollama.ai/library/qwen3/" + String(model.split(separator: ":")[1])).path)
        }
    }
    static func findOllama() -> String {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/ollama"
    }
}

enum APIKeyStore {
    private static let service = "com.local.LightTranslate.cloud-api"
    private static func query(for endpoint: String) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: try Endpoint.cloud(endpoint).absoluteString]
    }
    static func read(for endpoint: String) throws -> String {
        var request = try query(for: endpoint)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound,
           UserDefaults.standard.string(forKey: "legacyKeyEndpoint") == (try Endpoint.cloud(endpoint).absoluteString) {
            request[kSecAttrAccount as String] = "api-key"
            status = SecItemCopyMatching(request as CFDictionary, &result)
        }
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw TranslationError.message("无法读取钥匙串中的 API 密钥，请在设置中重新保存。")
        }
        return key
    }
    static func save(_ value: String, for endpoint: String) throws {
        let query = try query(for: endpoint)
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw TranslationError.message("密钥保存失败，请检查钥匙串权限。")
            }
        } else if status != errSecSuccess { throw TranslationError.message("密钥更新失败，请检查钥匙串权限。") }
    }
    static func delete(for endpoint: String) throws {
        let query = try query(for: endpoint)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TranslationError.message("无法删除密钥。") }
        if UserDefaults.standard.string(forKey: "legacyKeyEndpoint") == (try Endpoint.cloud(endpoint).absoluteString) {
            var legacy = query; legacy[kSecAttrAccount as String] = "api-key"
            let legacyStatus = SecItemDelete(legacy as CFDictionary)
            guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else { throw TranslationError.message("无法删除旧版密钥。") }
            UserDefaults.standard.removeObject(forKey: "legacyKeyEndpoint")
        }
    }
}
