import Foundation

/// J5 — pure path string helpers shared by the GUI context-menu
/// actions and smoke tests. Kept Foundation-only (no AppKit) so
/// the smoke target can exercise them without linking the GUI
/// module.
public enum PathHelpers {
    /// Last path component (file name including extension). For a
    /// path ending in `/` the trailing slash is stripped first so
    /// `/foo/bar/` yields `bar`. Empty input → empty string.
    public static func fileName(of path: String) -> String {
        if path.isEmpty { return "" }
        var s = path
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return (s as NSString).lastPathComponent
    }

    /// Parent directory path. `/foo/bar/baz.txt` → `/foo/bar`.
    /// Root (`/`) stays `/`; empty stays empty; relative paths
    /// without a slash return empty so callers can guard against
    /// it.
    public static func parentFolder(of path: String) -> String {
        if path.isEmpty { return "" }
        var s = path
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        let parent = (s as NSString).deletingLastPathComponent
        return parent
    }
}
