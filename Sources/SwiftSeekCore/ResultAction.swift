import Foundation

/// The three user-visible actions available on a search hit. The AppKit layer
/// owns the real side-effects (NSWorkspace, pasteboard) — this enum is the
/// shared vocabulary and is declared here so unit tests in `SwiftSeekCore`
/// can assert on state transitions without importing AppKit.
public enum ResultAction: String, Equatable, Sendable {
    case open           // open file / directory with default handler
    case revealInFinder // select in Finder window
    case copyPath       // write canonical path to clipboard
}

/// A light-weight descriptor of a target the user is about to act on. The
/// AppKit layer constructs it from a `SearchHit`, then hands it off to its
/// own `ResultActionRunner` which knows how to execute each case with real
/// `NSWorkspace` / `NSPasteboard` calls. Keeping the struct Core-side lets
/// us round-trip the model through tests and plugins without UI coupling.
public struct ResultTarget: Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }
}
