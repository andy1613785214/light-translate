import Foundation
import Darwin
import TranslationCore

/// Owns a private server on an ephemeral loopback port. Never terminates a user's existing Ollama server.
@MainActor
final class OllamaRuntime {
    private var process: Process?
    private var endpoint: URL?
    private var generation = UUID()
    private let transport = PrivateHTTPTransport()

    func ensureRunning(executable: String) async throws -> URL {
        if process?.isRunning != true {
            stop()
            guard FileManager.default.isExecutableFile(atPath: executable) else { throw TranslationError.localUnavailable }
            let port = try Self.availablePort()
            let address = URL(string: "http://127.0.0.1:\(port)")!
            let child = Process()
            child.executableURL = URL(fileURLWithPath: executable)
            child.arguments = ["serve"]
            var environment = ProcessInfo.processInfo.environment
            environment["OLLAMA_HOST"] = "127.0.0.1:\(port)"
            environment["OLLAMA_MODELS"] = SettingsStore.modelsDirectory.path
            environment["OLLAMA_NO_CLOUD"] = "1"
            environment["OLLAMA_KEEP_ALIVE"] = "2m"
            environment["OLLAMA_NUM_PARALLEL"] = "1"
            environment["OLLAMA_MAX_LOADED_MODELS"] = "1"
            child.environment = environment
            child.standardInput = FileHandle.nullDevice
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            do { try child.run() } catch { throw TranslationError.localUnavailable }
            process = child; endpoint = address
        }
        let ticket = generation
        guard let address = endpoint else { throw TranslationError.localUnavailable }
        for _ in 0..<80 {
            try Task.checkCancellation()
            guard generation == ticket else { throw CancellationError() }
            guard process?.isRunning == true else { throw TranslationError.localUnavailable }
            let health = URLRequest(url: address.appendingPathComponent("api/version"), timeoutInterval: 0.5)
            if let (_, response) = try? await transport.send(health), response.statusCode == 200 {
                guard generation == ticket else { throw CancellationError() }
                return address
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        stop()
        throw TranslationError.localUnavailable
    }

    func verifyModel(_ model: String, at endpoint: URL) async throws {
        guard LocalModels.supported.contains(model) else { throw TranslationError.unsupportedModel }
        let (data, response) = try await transport.send(URLRequest(url: endpoint.appendingPathComponent("api/tags"), timeoutInterval: 5))
        guard response.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { throw TranslationError.localUnavailable }
        guard models.contains(where: { ($0["name"] as? String) == model }) else { throw TranslationError.localModelMissing }
    }

    func stop() {
        generation = UUID()
        if let child = process, child.isRunning {
            child.terminate()
            // Retain this exact child, never search/kill other Ollama processes by name.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil; endpoint = nil
    }

    private static func availablePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TranslationError.localUnavailable }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw TranslationError.localUnavailable }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0 else { throw TranslationError.localUnavailable }
        return UInt16(bigEndian: address.sin_port)
    }
}
