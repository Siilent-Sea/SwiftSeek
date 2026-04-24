import AppKit
import SwiftSeekCore

/// AppKit-side executor for `ResultAction`. Keeps `SwiftSeekCore` free of
/// `AppKit` while funnelling every real side-effect through one place.
///
/// H1: `perform` now returns `Bool` — the caller needs to know whether
/// `.open` succeeded before writing to the usage table (we refuse to
/// bump `open_count` on a failed open). `.revealInFinder` and
/// `.copyPath` always return true; they have no failure mode we need
/// to surface for usage purposes.
enum ResultActionRunner {
    @discardableResult
    static func perform(_ action: ResultAction, target: ResultTarget) -> Bool {
        let url = URL(fileURLWithPath: target.path)
        switch action {
        case .open:
            // NSWorkspace.open(URL) is the documented public entry point
            // and returns false when no handler was available or the URL
            // could not be opened.
            return NSWorkspace.shared.open(url)
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        case .copyPath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(target.path, forType: .string)
            return true
        }
    }
}
