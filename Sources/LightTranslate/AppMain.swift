import AppKit
import Carbon
import SwiftUI
import TranslationCore

@MainActor
final class TranslationPanel: NSPanel {
    var onEscape: (() -> Void)?
    var acceptsInput = true
    override var canBecomeKey: Bool { acceptsInput }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var isUIPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-ui") ||
            Bundle.main.object(forInfoDictionaryKey: "LightTranslateUIPreview") as? Bool == true
    }
    private var isSmoke: Bool { ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--smoke-") || $0.hasPrefix("--render-") }) }
    private let settings: SettingsStore
    private lazy var model = AppModel(settings: settings)
    private lazy var hotKey = HotKeyManager()
    private var statusItem: NSStatusItem!
    private var panel: TranslationPanel!
    private var settingsWindow: NSWindow?
    private var localMonitor: Any?
    private var userResizedPanel = false
    private let releaseManager = ReleaseManager()
    private var compactState = false
    private var expandedSize = NSSize(width: 360, height: 240)

    override init() {
        let fixture = ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--render-") || $0.hasPrefix("--smoke-") }) ||
            Bundle.main.object(forInfoDictionaryKey: "LightTranslateUIPreview") as? Bool == true
        settings = SettingsStore(defaults: fixture ? UserDefaults(suiteName: "com.local.LightTranslate.UIFixture")! : .standard)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--render-") }) {
            NSApp.appearance = NSAppearance(named: ProcessInfo.processInfo.arguments.contains("--render-dark") ? .darkAqua : .aqua)
        }
        setupMainMenu()
        setupPanel()
        setupMenu()
        model.showSettings = { [weak self] in self?.openSettings() }
        model.dismissPanel = { [weak self] in self?.hidePanel() }
        model.onInputCaptured = { [weak self] in
            guard let self, !self.model.isBusy else { return }
            self.panel.acceptsInput = true
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }
        model.onPinChange = { [weak self] pinned in self?.panel.hidesOnDeactivate = !pinned }
        model.onContentHeightChange = { [weak self] height in self?.fitPanelHeight(height) }
        model.checkForUpdates = { [weak self] in self?.releaseManager.checkForUpdates(nil) }
        model.onCompactStateChange = { [weak self] busy in self?.setCompactState(busy) }
        hotKey.onPress = { [weak self] in
            guard let self else { return }
            self.model.shortcutStatus = "已收到 \(self.settings.shortcut.label) · " + Date().formatted(date: .omitted, time: .standard)
            self.translateSelection()
        }
        if !isUIPreview && !isSmoke {
            do { try hotKey.register(settings.shortcut); model.shortcutStatus = "已注册：\(settings.shortcut.label)" }
            catch { model.shortcutStatus = error.localizedDescription; model.error = error.localizedDescription; openSettings() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, event.window === self?.panel {
                self?.hidePanel(); return nil
            }
            return event
        }
        if isUIPreview {
            model.inputText = "The committee reached a unanimous decision."
            model.resultSource = model.inputText
            model.result = UIPreviewFixture.result
            model.elapsed = 0.8
            openPanel()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--render-loading") {
            model.isBusy = true
            openPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                let dark = ProcessInfo.processInfo.arguments.contains("--render-dark")
                let renderer = ImageRenderer(content: TranslationView(model: model, settings: settings)
                    .frame(width: panel.frame.width, height: panel.frame.height)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .background(dark ? Color(red: 0.13, green: 0.16, blue: 0.17) : Color(red: 0.95, green: 0.97, blue: 0.97), in: RoundedRectangle(cornerRadius: 22)))
                renderer.scale = 2
                guard let cgImage = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]),
                      let path = ProcessInfo.processInfo.environment["LT_RENDER_PATH"] else { Foundation.exit(1) }
                do { try png.write(to: URL(fileURLWithPath: path)) }
                catch { Foundation.exit(1) }
                print("RENDER: \(panel.frame)")
                NSApp.terminate(nil)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-loading") {
            model.isBusy = true
            openPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                guard panel.frame.width == 148, panel.frame.height == 44 else { Foundation.exit(1) }
                print("PASS: loading is a 148 × 44 toast")
                model.inputText = "The committee reached a unanimous decision."
                model.resultSource = model.inputText
                model.result = UIPreviewFixture.result
                model.isBusy = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                    let visible = panel.screen?.visibleFrame ?? .zero
                    guard panel.frame.width >= 320, panel.frame.height >= 180,
                          abs(visible.maxX - panel.frame.maxX - 12) < 1,
                          abs(visible.maxY - panel.frame.maxY - 12) < 1 else { Foundation.exit(1) }
                    print("PASS: result expands at the same upper-right anchor; frame=\(panel.frame)")
                    NSApp.terminate(nil)
                }
            }
            return
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            openSettings()
        } else if !ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            openPanel()
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            presentPanel(activate: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                let visible = panel.screen?.visibleFrame ?? .zero
                print("SMOKE: delegate launched; panel=\(panel != nil); hostingView=\(panel.contentView != nil); statusItem=\(statusItem != nil); windows=\(NSApp.windows.count); bundledIPA=\(PronunciationLexicon.shared.entryCount); compactFrame=\(panel.frame); rightInset=\(visible.maxX - panel.frame.maxX); topInset=\(visible.maxY - panel.frame.maxY)")
                NSApp.terminate(nil)
            }
        }
    }
    private func setupMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "关于轻译", action: #selector(ReleaseManager.showAbout(_:)), keyEquivalent: "")
        about.target = releaseManager
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出轻译", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
    private func setupPanel() {
        panel = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "轻译"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 320, height: 180)
        panel.maxSize = NSSize(width: 640, height: 900)
        panel.contentView = GlassHosting.make(TranslationView(model: model, settings: settings))
        panel.onEscape = { [weak self] in self?.hidePanel() }
        panel.delegate = self
    }
    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "轻译")
        statusItem.button?.toolTip = "轻译 · 划选后按 \(settings.shortcut.label)"
        let menu = NSMenu()
        let entries: [(String, Selector, String)] = [
            ("翻译选中文字（\(settings.shortcut.label)）", #selector(translateSelection), ""),
            ("打开翻译浮窗", #selector(openPanel), ""),
            ("翻译剪贴板", #selector(translateClipboard), "")
        ]
        for (title, action, key) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self; menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "退出轻译", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        menu.insertItem(.separator(), at: menu.items.count - 1)
        let updates = NSMenuItem(title: "检查更新…", action: #selector(ReleaseManager.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = releaseManager
        menu.insertItem(updates, at: menu.items.count - 2)
        releaseManager.configure(menuItem: updates, enabled: !isUIPreview && !isSmoke)
    }
    @objc private func translateSelection() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier else {
            presentPanel(activate: true)
            model.selectionUnavailable("请先切回需要翻译的应用，划选文字后按快捷键。")
            return
        }
        model.translateSelection(pid: pid)
        presentPanel(activate: false)
    }
    @objc private func openPanel() { presentPanel(activate: true) }
    @objc private func translateClipboard() { model.translateClipboard(); presentPanel(activate: false) }
    private func presentPanel(activate: Bool) {
        setCompactState(model.isBusy)
        panel.acceptsInput = activate && !model.isBusy
        if !activate && panel.isKeyWindow { panel.resignKey() }
        if !model.isPinned || !panel.isVisible {
            let mouse = NSEvent.mouseLocation
            let visible = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let width = min(panel.frame.width, visible.width - 24)
            let height = min(panel.frame.height, visible.height - 24)
            let x = visible.maxX - width - 12
            let y = visible.maxY - height - 12
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
        if activate && !model.isBusy { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
    }
    private func hidePanel() { model.cancel(); panel.orderOut(nil) }
    private func setCompactState(_ busy: Bool) {
        guard busy != compactState else { return }
        compactState = busy
        var frame = panel.frame
        if busy {
            expandedSize = frame.size
            panel.minSize = NSSize(width: 132, height: 44)
            panel.acceptsInput = false
            if panel.isKeyWindow { panel.resignKey() }
        } else {
            panel.minSize = NSSize(width: 320, height: 180)
            panel.acceptsInput = true
        }
        let size = busy ? NSSize(width: 148, height: 44) : expandedSize
        frame.origin = NSPoint(x: frame.maxX - size.width, y: frame.maxY - size.height)
        frame.size = size
        panel.setFrame(frame, display: true)
        if !busy, panel.isVisible, model.result != nil || model.error != nil {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
    private func fitPanelHeight(_ contentHeight: CGFloat) {
        guard !model.isBusy, !userResizedPanel, !panel.inLiveResize else { return }
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let height = min(max(180, ceil(contentHeight)), min(520, visible.height - 24))
        guard abs(panel.frame.height - height) > 1 else { return }
        var frame = panel.frame
        frame.origin.y = max(visible.minY + 12, min(frame.maxY, visible.maxY - 12) - height)
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        if notification.object as? NSWindow === panel { userResizedPanel = true }
    }
    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, model: model, changeShortcut: { [weak self] shortcut in
                guard let self else { return "应用尚未就绪。" }
                if shortcut == self.settings.shortcut { return nil }
                do {
                    try self.hotKey.register(shortcut)
                    self.settings.shortcut = shortcut
                    self.model.shortcutStatus = "已注册：\(shortcut.label)"
                    self.statusItem.button?.toolTip = "轻译 · 划选后按 \(shortcut.label)"
                    self.statusItem.menu?.items.first?.title = "翻译选中文字（\(shortcut.label)）"
                    return nil
                } catch { return error.localizedDescription }
            })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "轻译设置"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = GlassHosting.make(view)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPanel()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown(); hotKey.unregister()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

@main
struct LightTranslateMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if ProcessInfo.processInfo.arguments.contains("--check-hotkey") {
            let manager = HotKeyManager()
            do {
                try manager.register(Shortcut(keyCode: 2, modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), label: "test"))
                manager.onPress = { manager.unregister(); print("PASS: exclusive hotkey registration and dispatcher callback"); Foundation.exit(0) }
                DispatchQueue.main.async {
                    do { try manager.checkDispatch() }
                    catch { print(error.localizedDescription); Foundation.exit(1) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { print("FAIL: hotkey callback was not delivered"); Foundation.exit(1) }
                withExtendedLifetime(manager) { application.run() }
            } catch { print(error.localizedDescription); Foundation.exit(1) }
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
