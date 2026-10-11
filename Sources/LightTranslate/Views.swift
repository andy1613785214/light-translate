import AppKit
import SwiftUI
import TranslationCore

struct PanelLayout: Equatable {
    var contentHeight: CGFloat = 0
    var regions: [String: CGRect] = [:]
    var idealHeight: CGFloat {
        contentHeight + (regions["header"]?.height ?? 36) + (regions["footer"]?.height ?? 25)
    }
}

private struct PanelLayoutKey: PreferenceKey {
    static let defaultValue = PanelLayout()
    static func reduce(value: inout PanelLayout, nextValue: () -> PanelLayout) {
        let next = nextValue()
        value.contentHeight = max(value.contentHeight, next.contentHeight)
        value.regions.merge(next.regions) { _, new in new }
    }
}

private extension View {
    func panelRegion(_ name: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: PanelLayoutKey.self,
                    value: PanelLayout(regions: [name: geometry.frame(in: .named("translation-panel"))]))
            }
        }
    }
}

struct TranslationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @State private var expanded = Set<String>()
    @State private var sourceExpanded = false
    @State private var vocabularyExpanded = false
    @State private var copied = false

    var body: some View {
        Group {
            if model.isBusy {
                Text("正在翻译").font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                expandedBody
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: model.presentationID) { _, _ in
                expanded.removeAll(); copied = false; sourceExpanded = false; vocabularyExpanded = false
            }
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("轻译").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { model.isPinned.toggle(); model.onPinChange?(model.isPinned) } label: {
                    Image(systemName: model.isPinned ? "pin.fill" : "pin")
                }.help("固定浮窗").accessibilityLabel("固定浮窗")
                Menu {
                    Picker("翻译方向", selection: Binding(get: { settings.direction }, set: {
                        model.cancel(); settings.direction = $0
                    })) {
                        ForEach(TranslationDirection.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("翻译模式", selection: Binding(get: { settings.mode }, set: model.setMode)) {
                        ForEach(ProviderMode.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    if model.result != nil {
                        Button("编辑原文") { sourceExpanded = true }
                    }
                    Button("翻译剪贴板") { model.translateClipboard() }.disabled(model.isTesting)
                    Button("设置…") { model.showSettings?() }
                    Button("检查更新…") { model.checkForUpdates?() }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("方向、模式与设置")
                    .accessibilityLabel("更多选项")
                Button { model.dismissPanel?() } label: { Image(systemName: "xmark") }
                    .help("关闭（Esc）").accessibilityLabel("关闭浮窗")
            }.font(.system(size: 12)).buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .layoutPriority(1).panelRegion("header")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.result != nil && (!WordSelection.isSingleEnglishWord(model.resultSource) || sourceExpanded) {
                        Button {
                            sourceExpanded.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: sourceExpanded ? "chevron.down" : "chevron.right")
                                Text("原文")
                                if !sourceExpanded {
                                    Text(model.resultSource).lineLimit(1).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).help("展开或收起原文与编辑入口")
                    }
                    if model.result == nil || sourceExpanded {
                        if model.isBusy {
                            if !model.inputText.isEmpty {
                                Text(model.inputText).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topLeading) {
                                    if model.inputText.isEmpty {
                                        Text("输入或粘贴文字")
                                            .font(.system(size: 12)).foregroundStyle(.tertiary)
                                            .padding(.horizontal, 12).padding(.top, 10).allowsHitTesting(false)
                                    }
                                    TextEditor(text: $model.inputText).font(.system(size: 13))
                                        .scrollContentBackground(.hidden).frame(height: 68).padding(6)
                                        .accessibilityLabel("待翻译的原文")
                                }.background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.06)))
                                HStack {
                                    Button { model.translateClipboard() } label: {
                                        Image(systemName: "doc.on.clipboard")
                                    }.buttonStyle(.plain).help("翻译剪贴板").accessibilityLabel("翻译剪贴板")
                                        .disabled(model.isTesting)
                                    Spacer()
                                    Text("\(model.inputText.count)/3000").font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(model.inputText.count > 3000 ? .red : .secondary)
                                    Button("翻译") { model.translateText() }.buttonStyle(GlassActionStyle())
                                        .controlSize(.small)
                                        .disabled(model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isTesting)
                                }
                            }
                        }
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                            HStack {
                                Button("重试") { model.translateText(force: true) }
                                    .disabled(model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("设置…") { model.showSettings?() }
                                if settings.mode == .cloud && !model.inputText.isEmpty {
                                    Menu("其他方式") {
                                        Button("切换本地并重试") { model.setMode(.local); model.translateText(force: true) }
                                    }.fixedSize()
                                }
                            }.controlSize(.small)
                        }.font(.caption).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let result = model.result {
                        if WordSelection.isSingleEnglishWord(model.resultSource), let word = result.vocabulary.first {
                            VocabularyCard(entry: word, expanded: .constant(true), alwaysExpanded: true)
                        } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(result.detectedLanguage == "zh" ? "中 → 英" : result.detectedLanguage == "en" ? "英 → 中" : "译文")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    model.copyTranslation(); copied = true
                                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                                    .buttonStyle(.plain).help(copied ? "已复制" : "复制译文")
                                    .accessibilityLabel(copied ? "已复制" : "复制译文")
                            }
                            Text(result.translation).font(.system(size: 15)).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .panelRegion("translation")
                        }.padding(.vertical, 6)
                        if !result.vocabulary.isEmpty {
                            DisclosureGroup(isExpanded: $vocabularyExpanded) {
                                VStack(spacing: 8) {
                                    ForEach(result.vocabulary) { entry in
                                        VocabularyCard(entry: entry, expanded: Binding(
                                            get: { expanded.contains(entry.id) },
                                            set: { if $0 { expanded.insert(entry.id) } else { expanded.remove(entry.id) } }))
                                    }
                                }.padding(.top, 6)
                            } label: {
                                HStack {
                                    Text("词汇 · \(result.vocabulary.count)").font(.caption.weight(.semibold))
                                    Spacer()
                                }.panelRegion("vocabulary-toggle")
                            }.tint(.teal)
                        }
                        }
                        ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                        if model.resultSource != model.inputText {
                            Text("原文已修改，请重新翻译。").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    if settings.mode == .local && settings.localModel == "qwen3:0.6b" {
                        Text("0.6B 应急模式 · 词解质量有限").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: PanelLayoutKey.self, value: PanelLayout(contentHeight: geometry.size.height))
                    }
                }
            }
            .id(model.presentationID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped().panelRegion("scroll")
            HStack(spacing: 5) {
                Text(settings.mode == .cloud ? "云端 API" : "本机")
                    .help(settings.mode == .cloud ? "文字将发送到你配置的 API" : "文字仅发送到本机")
                if let result = model.result {
                    Text("· \(result.model)").lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if let seconds = model.elapsed { Text(String(format: "%.1fs", seconds)) }
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
                .padding(.horizontal, 16).padding(.bottom, 12)
                .layoutPriority(1).panelRegion("footer")
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(name: "translation-panel")
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .onPreferenceChange(PanelLayoutKey.self) { layout in
                if layout.contentHeight > 0 { model.onPanelLayoutChange?(layout) }
            }
    }
}

struct VocabularyCard: View {
    let entry: VocabularyEntry
    @Binding var expanded: Bool
    var alwaysExpanded = false

    var body: some View {
        Group {
            if alwaysExpanded {
                VStack(alignment: .leading, spacing: 12) { heading; details }
            } else {
                DisclosureGroup(isExpanded: $expanded) { details } label: { heading }
            }
        }.tint(.secondary).padding(9).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var details: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text("音标来源：\(entry.ipaSource ?? "模型生成 · 未校验")")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text("常见义项").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(entry.commonMeanings.isEmpty ? "暂不可用" : entry.commonMeanings.joined(separator: "；"))
                Text("常见搭配").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(entry.collocations.isEmpty ? "暂不可用" : entry.collocations.joined(separator: " · "))
                Text("使用例句").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if entry.examples.isEmpty { Text("暂不可用").foregroundStyle(.secondary) }
                ForEach(Array(entry.examples.enumerated()), id: \.offset) { index, example in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(index + 1). \(example.english)")
                        Text(example.chinese).foregroundStyle(.secondary)
                    }
                }
                if entry.examples.count == 1 { Text("第二个例句暂不可用").foregroundStyle(.secondary) }
            }.font(.system(size: 12)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }

    private var heading: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.word).font(.system(size: alwaysExpanded ? 20 : 13, weight: .semibold))
                    Text(entry.partOfSpeech ?? "词性暂不可用").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(entry.ipa ?? "音标暂不可用").font(.system(size: 11)).foregroundStyle(.secondary)
                    .help(entry.ipaSource ?? "模型生成 · 未校验")
                Text(entry.contextualMeaning ?? "语境释义暂不可用").font(.system(size: 12))
            }.textSelection(.enabled).padding(.vertical, 2)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    let changeShortcut: (Shortcut) -> String?
    @State private var endpoint = ""
    @State private var cloudModel = ""
    @State private var cloudService: CloudService = .compatible
    @State private var vocabularyModel = ""
    @State private var key = ""
    @State private var executable = ""
    @State private var message = ""
    @State private var hasPermission = SelectionService.hasPermission

    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(ReleaseManager.version).font(.caption).foregroundStyle(.tertiary)
            }
            Picker("设置分类", selection: $tab) {
                Text("翻译服务").tag(0)
                Text("偏好").tag(1)
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tab == 0 {
                        Picker("翻译模式", selection: Binding(get: { settings.mode }, set: model.setMode)) {
                            ForEach(ProviderMode.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                        if settings.mode == .cloud {
                            Picker("服务", selection: Binding(get: { cloudService }, set: { service in
                                cloudService = service; key = ""
                                if service != .compatible { endpoint = service.defaultEndpoint; cloudModel = service.defaultModel }
                            })) {
                                ForEach(CloudService.allCases) { Text($0.title).tag($0) }
                            }
                            TextField("API 地址", text: $endpoint)
                                .accessibilityLabel("API 地址")
                            TextField("模型名称", text: $cloudModel)
                                .accessibilityLabel("模型名称")
                            if cloudService == .qwenMT {
                                TextField("词解模型", text: $vocabularyModel)
                            }
                            SecureField("API 密钥 · 留空保留", text: $key)
                            HStack {
                                Button("保存") { saveCloud() }.buttonStyle(GlassActionStyle())
                                Spacer()
                                Button {
                                    do { try APIKeyStore.delete(for: settings.endpoint); model.configurationChanged(); message = "密钥已删除。" }
                                    catch { message = error.localizedDescription }
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).help("删除已存密钥").accessibilityLabel("删除已存密钥")
                            }
                        } else {
                            Picker("模型", selection: Binding(get: { settings.localModel }, set: model.setLocalModel)) {
                                Text("Qwen3 1.7B").tag("qwen3:1.7b")
                                Text("Qwen3 0.6B").tag("qwen3:0.6b")
                            }
                            TextField("Ollama 路径", text: $executable)
                            HStack {
                                Button("保存") {
                                    guard FileManager.default.isExecutableFile(atPath: executable) else { message = "该路径不是可执行文件。"; return }
                                    model.configurationChanged(); settings.ollamaPath = executable; message = "路径已保存。"
                                }.buttonStyle(GlassActionStyle())
                                Button("检查模型") {
                                    message = SettingsStore.installedModels().contains(settings.localModel) ? "已找到模型。" : "未找到模型，请先下载。"
                                }.buttonStyle(GlassActionStyle())
                            }
                        }
                    } else {
                        HStack {
                            Label(hasPermission ? "选区权限已开启" : "需要选区权限", systemImage: hasPermission ? "checkmark.circle" : "lock")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Button("授权") { SelectionService.requestPermission(); SelectionService.openPermissionSettings() }
                            Button { hasPermission = SelectionService.hasPermission } label: { Image(systemName: "arrow.clockwise") }
                                .help("刷新权限状态").accessibilityLabel("刷新权限状态")
                        }.controlSize(.small)
                        HStack {
                            Text("快捷键").font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            ShortcutRecorder(shortcut: settings.shortcut) { shortcut in
                                message = changeShortcut(shortcut) ?? "已保存。"
                            }.frame(width: 220, height: 30)
                            Button { message = changeShortcut(.standard) ?? "已恢复。" } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.plain).help("恢复默认快捷键").accessibilityLabel("恢复默认快捷键")
                        }
                        Picker("默认方向", selection: Binding(get: { settings.direction }, set: { model.cancel(); settings.direction = $0 })) {
                            ForEach(TranslationDirection.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }.textFieldStyle(.roundedBorder).padding(.vertical, 3)
            }
        }.padding(24).padding(.top, 20).frame(minWidth: 420, minHeight: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { cloudService = settings.cloudService; endpoint = settings.endpoint; cloudModel = settings.cloudModel; vocabularyModel = settings.vocabularyModel; executable = settings.ollamaPath }
            .onChange(of: tab) { _, _ in message = "" }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in hasPermission = SelectionService.hasPermission }
    }
    private func saveCloud() {
        do {
            _ = try Endpoint.cloud(endpoint)
            guard !cloudModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TranslationError.missingConfiguration }
            if cloudService == .qwenMT && vocabularyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw TranslationError.message("请填写同一百炼服务中的通用词解模型。")
            }
            if !key.isEmpty { try APIKeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: endpoint) }
            model.configurationChanged()
            settings.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.cloudModel = cloudModel.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.cloudService = cloudService
            settings.vocabularyModel = vocabularyModel.trimmingCharacters(in: .whitespacesAndNewlines)
            key = ""; message = "云端设置已保存。"
        } catch { message = error.localizedDescription }
    }
}
