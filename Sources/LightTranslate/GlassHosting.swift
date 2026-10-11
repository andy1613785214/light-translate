import AppKit
import SwiftUI

enum GlassHosting {
    @MainActor
    static func make<Content: View>(_ content: Content) -> NSView {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        content.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.topAnchor.constraint(equalTo: content.topAnchor),
            host.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 22
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 22
        material.layer?.masksToBounds = true
        material.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        return material
    }
}

struct GlassActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.primary.opacity(configuration.isPressed ? 0.13 : 0.065), in: Capsule())
            .contentShape(Capsule())
    }
}
