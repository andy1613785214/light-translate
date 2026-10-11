import AppKit
import ApplicationServices
import TranslationCore

enum SelectionRead: Sendable { case text(String), empty, unavailable, secure }

enum SelectionService {
    @MainActor private static var captureInProgress = false
    static var hasPermission: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    static func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @MainActor
    static func capture(pid: pid_t) async throws -> String {
        guard !captureInProgress else { throw TranslationError.message("正在完成上一次取词，请稍后再按快捷键。") }
        captureInProgress = true
        defer { captureInProgress = false }
        guard hasPermission else {
            throw TranslationError.message("当前运行的轻译尚未获得有效辅助功能权限。若系统开关已开启，请退出并重新打开；重新构建后需移除旧条目，再添加当前轻译.app。也可手动粘贴。")
        }
        let selection = await Task.detached(priority: .userInitiated) { readAccessibility(pid: pid) }.value
        try Task.checkCancellation()
        switch selection {
        case .text(let text): return text
        case .empty: throw TranslationError.message("当前没有选中文字。请先划选句子，或手动粘贴。")
        case .secure: throw TranslationError.message("无法读取受保护的输入框。请使用普通文本选区。")
        case .unavailable: return try await copySelection(pid: pid)
        }
    }

    private static func readAccessibility(pid: pid_t) -> SelectionRead {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.35)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unavailable }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if (subrole as? String) == "AXSecureTextField" { return .secure }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let editable = [kAXTextFieldRole, kAXTextAreaRole].contains(role as? String ?? "")
        switch SelectionPolicy.resolve(selectedText: status == .success ? value as? String : nil,
                                      isEditable: editable, isProtected: false) {
        case .text(let text): return .text(text)
        case .emptyEditableSelection: return .empty
        case .copyRequired: return .unavailable
        case .protectedInput: return .secure
        }
    }

    @MainActor
    private static func copySelection(pid: pid_t) async throws -> String {
        guard CGPreflightPostEventAccess() else {
            throw TranslationError.message("系统尚未允许轻译模拟复制。请退出后重新打开；若仍失败，请在辅助功能中重新添加当前轻译.app，或手动复制粘贴。")
        }
        // The hotkey callback can run while Option/Command is still physically held.
        let shortcutFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(shortcutFlags).isEmpty { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        guard CGEventSource.flagsState(.combinedSessionState).intersection(shortcutFlags).isEmpty else {
            throw TranslationError.message("请松开快捷键后重试取词，或手动复制粘贴。")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw TranslationError.message("前台应用已改变，请重新划选并按快捷键。")
        }
        let board = NSPasteboard.general
        let originalCount = board.changeCount
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        var byteCount = 0
        for item in board.pasteboardItems ?? [] {
            var stored: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    throw TranslationError.message("剪贴板含不可恢复的数据，请手动复制句子并点击“翻译剪贴板”。")
                }
                byteCount += data.count
                guard byteCount <= 16 * 1024 * 1024 else {
                    throw TranslationError.message("当前剪贴板内容较大，请手动复制句子并点击“翻译剪贴板”。")
                }
                stored[type] = data
            }
            snapshot.append(stored)
        }
        guard board.changeCount == originalCount else { throw TranslationError.message("剪贴板正在变化，请重试。") }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            throw TranslationError.message("无法模拟复制，请手动粘贴。")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(pid); up.postToPid(pid)
        var copiedCount: Int?
        defer {
            if let copiedCount, board.changeCount == copiedCount {
                board.clearContents()
                let items = snapshot.map { stored -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in stored { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { board.writeObjects(items) }
            }
        }
        // Once copy was posted, finish the short clipboard transaction even if translation was cancelled.
        for _ in 0..<40 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { continuation.resume() }
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                throw TranslationError.message("前台应用已改变，请重新划选。")
            }
            if board.changeCount != originalCount {
                copiedCount = board.changeCount
                let text = board.string(forType: .string) ?? ""
                guard board.changeCount == copiedCount else {
                    copiedCount = nil
                    throw TranslationError.message("复制期间剪贴板发生变化，请重试。")
                }
                try Task.checkCancellation()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TranslationError.message("选区不是可读取的文字，请手动粘贴。")
                }
                return text
            }
        }
        throw TranslationError.message("未获取到新的选中文字。请手动复制后点击“翻译剪贴板”。")
    }
}
