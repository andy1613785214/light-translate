import AppKit
import TranslationCore

@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let runtime = OllamaRuntime()
    @Published var inputText = ""
    @Published var result: TranslationResult?
    @Published var resultSource = ""
    @Published var error: String?
    @Published var status = "划选句子并按快捷键，或直接粘贴文字。"
    @Published var isBusy = false
    @Published var isPinned = false
    @Published var elapsed: Double?
    @Published var connectionStatus = ""
    @Published var isTesting = false
    @Published var shortcutStatus = "快捷键尚未注册"
    var showSettings: (() -> Void)?
    var dismissPanel: (() -> Void)?
    var onPinChange: ((Bool) -> Void)?
    var onInputCaptured: (() -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var checkForUpdates: (() -> Void)?
    var onCompactStateChange: ((Bool) -> Void)?
    private var task: Task<Void, Never>?
    private var testTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var requestID = UUID()
    private var testID = UUID()
    private var cache = ResultCache()

    init(settings: SettingsStore) { self.settings = settings }

    func translateSelection(pid: pid_t) {
        inputText = ""; resultSource = ""
        start(isSelection: true, initialStatus: "正在读取选中文字…") { try await SelectionService.capture(pid: pid) }
    }
    func selectionUnavailable(_ message: String) {
        cancel(); inputText = ""; result = nil; resultSource = ""; elapsed = nil
        status = "未获取选区"; error = "取词失败：" + message
    }
    func translateText(force: Bool = false) {
        let input = inputText
        start(force: force) { input }
    }
    func translateClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        start { text }
    }
    private func start(force: Bool = false, isSelection: Bool = false, initialStatus: String = "正在准备翻译…", input: @escaping () async throws -> String) {
        cancel()
        if isTesting && settings.mode == .local { runtime.stop() }
        testTask?.cancel(); testID = UUID(); isTesting = false
        idleTask?.cancel()
        let ticket = requestID
        let mode = settings.mode
        let endpoint = settings.endpoint
        let cloudModel = settings.cloudModel
        let cloudService = settings.cloudService, vocabularyModel = settings.vocabularyModel
        let localModel = settings.localModel
        let executable = settings.ollamaPath
        let direction = settings.direction
        isBusy = true; status = initialStatus; error = nil; result = nil; elapsed = nil
        task = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            var captured = !isSelection
            do {
                let text = try await input()
                try Task.checkCancellation()
                guard self.requestID == ticket else { return }
                self.inputText = text
                captured = true
                self.onInputCaptured?()
                let request = try TranslationRequest(text: text, direction: direction)
                let key = CacheKey(request: request, provider: mode.rawValue, endpoint: mode == .cloud ? endpoint : "local",
                                   model: mode == .cloud ? "\(cloudService.rawValue):\(cloudModel):\(vocabularyModel)" : localModel)
                let value: TranslationResult
                if !force, let cached = self.cache.value(for: key) {
                    value = cached
                    self.status = "已读取本次会话缓存"
                } else {
                    if mode == .cloud {
                        self.status = "正在通过云端 API 翻译并解释词汇…"
                        let provider = try cloudService.provider(endpoint: endpoint, apiKey: APIKeyStore.read(for: endpoint),
                            model: cloudModel, vocabularyModel: vocabularyModel)
                        value = try await provider.translate(request)
                    } else {
                        self.status = "正在启动本地服务；首次加载模型可能较慢…"
                        let url = try await self.runtime.ensureRunning(executable: executable)
                        try await self.runtime.verifyModel(localModel, at: url)
                        try Task.checkCancellation()
                        self.status = "\(localModel) 正在加载或生成译文与词解…"
                        value = try await OllamaProvider(baseURL: url, model: localModel).translate(request)
                    }
                    try Task.checkCancellation()
                    guard self.requestID == ticket else { return }
                    self.cache.insert(value, for: key)
                    self.status = "翻译完成"
                }
                guard self.requestID == ticket else { return }
                self.resultSource = request.text; self.result = value; self.elapsed = Date().timeIntervalSince(started)
            } catch is CancellationError {
                return
            } catch {
                guard self.requestID == ticket else { return }
                self.error = (captured ? "翻译失败：" : "取词失败：") + error.localizedDescription
                self.status = captured ? "未完成翻译" : "未获取选区"
                self.onInputCaptured?()
            }
            guard self.requestID == ticket else { return }
            self.isBusy = false; self.task = nil
            if mode == .local { self.scheduleIdleStop() }
        }
    }

    func cancel() {
        requestID = UUID(); task?.cancel(); task = nil
        if isBusy && settings.mode == .local { runtime.stop() }
        isBusy = false
    }
    func setMode(_ mode: ProviderMode) {
        guard settings.mode != mode else { return }
        configurationChanged()
        settings.mode = mode
        status = mode == .cloud ? "已切换到云端，下次翻译使用 API。" : "已切换到本地，下次翻译时按需加载模型。"
    }
    func configurationChanged() {
        cancel(); testID = UUID(); testTask?.cancel(); testTask = nil; isTesting = false
        idleTask?.cancel(); runtime.stop(); cache.removeAll()
        result = nil; error = nil; connectionStatus = ""
    }
    func setLocalModel(_ model: String) {
        guard LocalModels.supported.contains(model) else { return }
        configurationChanged(); settings.localModel = model
    }
    func testConnection() {
        cancel(); testTask?.cancel(); idleTask?.cancel()
        let ticket = UUID(); testID = ticket
        let mode = settings.mode
        let endpoint = settings.endpoint, model = settings.cloudModel
        let cloudService = settings.cloudService, vocabularyModel = settings.vocabularyModel
        let localModel = settings.localModel, executable = settings.ollamaPath
        isTesting = true; connectionStatus = "正在验证连接和模型输出…"
        testTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sample = try TranslationRequest(text: "This is a test.", direction: .toChinese)
                if mode == .cloud {
                    let provider = try cloudService.provider(endpoint: endpoint, apiKey: APIKeyStore.read(for: endpoint),
                        model: model, vocabularyModel: vocabularyModel)
                    let result = try await provider.translate(sample)
                    try Task.checkCancellation()
                    guard self.testID == ticket else { return }
                    self.connectionStatus = result.warnings.isEmpty ? "连接成功，已获得有效译文。" : "译文可用：" + result.warnings.joined(separator: " ")
                } else {
                    let url = try await self.runtime.ensureRunning(executable: executable)
                    try await self.runtime.verifyModel(localModel, at: url)
                    _ = try await OllamaProvider(baseURL: url, model: localModel).translate(sample)
                }
                try Task.checkCancellation()
                guard self.testID == ticket else { return }
                if mode == .local { self.connectionStatus = "连接成功，已获得有效译文。" }
            } catch is CancellationError { return }
            catch {
                guard self.testID == ticket else { return }
                self.connectionStatus = error.localizedDescription
            }
            guard self.testID == ticket else { return }
            self.isTesting = false
            if mode == .local { self.scheduleIdleStop() }
        }
    }
    private func scheduleIdleStop() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard let self, !self.isBusy, !self.isTesting else { return }
            self.runtime.stop()
        }
    }
    func shutdown() { configurationChanged() }
    func copyTranslation() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.translation, forType: .string)
    }
}
