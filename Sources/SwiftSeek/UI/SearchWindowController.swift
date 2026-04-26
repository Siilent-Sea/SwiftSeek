import AppKit
import SwiftSeekCore

final class SearchWindowController: NSWindowController {
    private let viewController: SearchViewController

    init(database: Database) {
        self.viewController = SearchViewController(database: database)
        // J2: panel default width bumped 680 -> 1020. With H2's 6
        // columns (名称 260 + 路径 320 + 修改时间 120 + 大小 80 +
        // 打开次数 80 + 最近打开 120 = 980px), the previous 680px
        // default cropped the last two new columns out of sight —
        // which is why users reported "no Run Count visible" even
        // after H1-H5 landed. 1020 gives ~40px of breathing room.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 420),
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
        // J2: persist user resize across launches. Uses a
        // namespaced autosave key so it doesn't collide with
        // other NSWindows.
        panel.setFrameAutosaveName("SwiftSeekSearchPanel")
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
        // M3: pull fresh reveal target labels every time the search
        // window pops, so a Settings change made while the window was
        // hidden surfaces in the button + right-click menu without
        // requiring an app relaunch.
        viewController.refreshRevealLabels()
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
