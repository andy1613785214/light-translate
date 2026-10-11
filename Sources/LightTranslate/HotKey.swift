import AppKit
import Carbon
import SwiftUI

@MainActor
final class HotKeyManager {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private var activeID: UInt32?
    private var installationStatus: OSStatus = noErr
    var onPress: (() -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        installationStatus = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                identifier.signature == 0x4C54524E else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                guard manager.activeID == identifier.id else { return }
                manager.onPress?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: Shortcut) throws {
        guard installationStatus == noErr, handler != nil else { throw HotKeyError.handler(installationStatus) }
        var proposed: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: 0x4C54524E, id: nextID), GetEventDispatcherTarget(), UInt32(kEventHotKeyExclusive), &proposed)
        guard status == noErr else { throw HotKeyError.conflict }
        if let reference { UnregisterEventHotKey(reference) }
        reference = proposed; activeID = nextID; nextID &+= 1
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil; activeID = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
    // Routes a synthetic Carbon event only within this app's dispatcher; never posts a system key.
    func checkDispatch() throws {
        guard let activeID else { throw HotKeyError.conflict }
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), 0, &event) == noErr,
              let event else { throw HotKeyError.handler(OSStatus(eventNotHandledErr)) }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: 0x4C54524E, id: activeID)
        let setStatus = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         MemoryLayout<EventHotKeyID>.size, &identifier)
        guard setStatus == noErr else { throw HotKeyError.handler(setStatus) }
        let status = SendEventToEventTarget(event, GetEventDispatcherTarget())
        guard status == noErr else { throw HotKeyError.handler(status) }
    }
    enum HotKeyError: LocalizedError {
        case conflict, handler(OSStatus)
        var errorDescription: String? {
            switch self {
            case .conflict: return "快捷键注册失败或已被占用，请选择其他组合。"
            case .handler(let status): return "无法启动快捷键监听（\(status)），请退出并重新打开轻译。"
            }
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    let onRecord: (Shortcut) -> Void
    func makeNSView(context: Context) -> RecordingButton {
        let button = RecordingButton()
        button.bezelStyle = .rounded
        button.onRecord = onRecord
        button.updateTitle(shortcut.label)
        return button
    }
    func updateNSView(_ view: RecordingButton, context: Context) {
        view.onRecord = onRecord; view.updateTitle(shortcut.label)
    }
}

final class RecordingButton: NSButton {
    var onRecord: ((Shortcut) -> Void)?
    private var recording = false
    private var savedTitle = ""
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); target = self; action = #selector(record) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateTitle(_ label: String) {
        savedTitle = label
        if !recording { title = label + " · 点击录制" }
    }
    @objc private func record() {
        recording = true; title = "请按组合键（Esc 取消）"; window?.makeFirstResponder(self)
    }
    override func resignFirstResponder() -> Bool {
        recording = false; updateTitle(savedTitle); return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; updateTitle(savedTitle); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else {
            title = "请包含 ⌘、⌃ 或 ⌥"; return
        }
        var carbon: UInt32 = 0
        var label = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); label += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        label += names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        recording = false
        onRecord?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbon, label: label))
        updateTitle(savedTitle)
    }
}
