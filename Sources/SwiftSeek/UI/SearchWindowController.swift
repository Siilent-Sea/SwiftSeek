import AppKit
import SwiftSeekCore

final class SearchWindowController: NSWindowController {
    private let viewController: SearchViewController

    init(database: Database) {
        self.viewController = SearchViewController(database: database)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.title = "SwiftSeek"
        panel.contentViewController = viewController
        panel.center()
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func toggle() {
        if let w = window, w.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let w = window else { return }
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            var f = w.frame
            f.origin.x = sf.midX - f.width / 2
            f.origin.y = sf.midY - f.height / 2 + sf.height * 0.1
            w.setFrame(f, display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        viewController.focusInput()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

extension SearchWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Auto-hide when user clicks away, matching Spotlight / Alfred.
        hide()
    }
}
