import AppKit
import Sparkle

@MainActor
final class ReleaseManager: NSObject {
    private var controller: SPUStandardUpdaterController?
    private var checkMenuItem: NSMenuItem?

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static var projectURL: URL? { (Bundle.main.object(forInfoDictionaryKey: "LTProjectURL") as? String).flatMap(URL.init(string:)) }

    func configure(menuItem: NSMenuItem, enabled: Bool) {
        checkMenuItem = menuItem
        guard enabled,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        menuItem.target = controller
        menuItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let controller else {
            if let project = Self.projectURL { NSWorkspace.shared.open(project.appendingPathComponent("releases/latest")) }
            return
        }
        controller.checkForUpdates(sender)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "轻译",
            .applicationVersion: Self.version,
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            .credits: NSAttributedString(string: "中英翻译 · 随选随译")
        ])
    }
}
