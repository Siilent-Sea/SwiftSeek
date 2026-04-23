import AppKit
import SwiftSeekCore

/// AppKit-side executor for `ResultAction`. Keeps `SwiftSeekCore` free of
/// `AppKit` while funnelling every real side-effect through one place.
enum ResultActionRunner {
    static func perform(_ action: ResultAction, target: ResultTarget) {
        let url = URL(fileURLWithPath: target.path)
        switch action {
        case .open:
            NSWorkspace.shared.open(url)
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyPath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(target.path, forType: .string)
        }
    }
}
