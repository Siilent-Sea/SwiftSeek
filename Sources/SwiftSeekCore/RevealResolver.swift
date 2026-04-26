import Foundation

/// M2 — pure helpers used by `ResultActionRunner` to translate a
/// `RevealTarget` configuration plus a concrete `ResultTarget` into
/// "what URL do we hand to which app, and do we need to fall back to
/// Finder?" Lives in Core (no AppKit) so smoke tests can pin every
/// branch without spinning the GUI / NSWorkspace.
public enum RevealResolver {
    /// Result of validating the persisted custom-app path. Each
    /// failure case carries enough info for the AppKit layer to log
    /// and surface a user-visible error before falling back to Finder.
    public enum CustomAppValidation: Equatable, Sendable {
        case ok(URL)
        case empty
        case notFound(path: String)
        case notAnApp(path: String)
    }

    /// Decision tree for a single reveal click. The AppKit layer
    /// consumes this and either calls Finder's
    /// `activateFileViewerSelecting` or `NSWorkspace.open([target],
    /// withApplicationAt: app, ...)`. `fallbackToFinder` is the
    /// honest "we tried but couldn't" branch — caller must surface
    /// the reason to the user, not silently swallow.
    public enum Strategy: Equatable, Sendable {
        case finder(targetURL: URL)
        case customApp(appURL: URL, targetURL: URL)
        case fallbackToFinder(targetURL: URL, reason: String)
    }

    /// Resolve which URL we should hand to the external app.
    ///   - `.item` → the file or directory itself.
    ///   - `.parentFolder` → if the target is a regular file, its
    ///     parent directory; if the target is itself a directory, the
    ///     directory itself (opening "the parent of /Foo" loses the
    ///     user's context — landing inside the chosen folder is what
    ///     they expect from a "show in <FM>" gesture).
    public static func resolveTargetURL(target: ResultTarget,
                                        openMode: ExternalRevealOpenMode) -> URL {
        let url = URL(fileURLWithPath: target.path)
        switch openMode {
        case .item:
            return url
        case .parentFolder:
            if target.isDirectory {
                // Opening the parent of a chosen directory drops the
                // user one level higher than they expect; preserve the
                // chosen directory itself.
                return url
            }
            return url.deletingLastPathComponent()
        }
    }

    /// Validate a persisted `customAppPath`. Caller passes a
    /// `fileExists` probe (defaults to FileManager.default) so this
    /// helper stays mockable in smoke tests without polluting the
    /// real filesystem. The probe returns `(exists, isDirectory)`
    /// which matches FileManager's `fileExists(atPath:isDirectory:)`
    /// shape.
    public static func validateCustomAppPath(
        _ path: String,
        fileExists: (String) -> (exists: Bool, isDirectory: Bool) = defaultFileExists
    ) -> CustomAppValidation {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let probe = fileExists(trimmed)
        guard probe.exists else { return .notFound(path: trimmed) }
        // macOS .app bundles are directories with a `.app` suffix.
        // Reject regular files (e.g. user pointed at a binary) and
        // directories without the suffix (e.g. user pointed at
        // `/Applications` itself).
        guard probe.isDirectory else { return .notAnApp(path: trimmed) }
        guard trimmed.hasSuffix(".app") else { return .notAnApp(path: trimmed) }
        return .ok(URL(fileURLWithPath: trimmed))
    }

    /// Compose validation + target-URL resolution into a single
    /// strategy. AppKit consumes the result.
    public static func decideStrategy(
        target: ResultTarget,
        revealTarget: RevealTarget,
        fileExists: (String) -> (exists: Bool, isDirectory: Bool) = defaultFileExists
    ) -> Strategy {
        let targetURL = URL(fileURLWithPath: target.path)
        switch revealTarget.type {
        case .finder:
            return .finder(targetURL: targetURL)
        case .customApp:
            switch validateCustomAppPath(revealTarget.customAppPath, fileExists: fileExists) {
            case .ok(let appURL):
                let resolved = resolveTargetURL(target: target, openMode: revealTarget.openMode)
                return .customApp(appURL: appURL, targetURL: resolved)
            case .empty:
                return .fallbackToFinder(targetURL: targetURL,
                                         reason: "未配置自定义 App 路径")
            case .notFound(let p):
                return .fallbackToFinder(targetURL: targetURL,
                                         reason: "自定义 App 不存在：\(p)")
            case .notAnApp(let p):
                return .fallbackToFinder(targetURL: targetURL,
                                         reason: "路径不是 .app bundle：\(p)")
            }
        }
    }

    /// Default FileManager-backed probe. Pulled out as a free
    /// function so smoke tests can pass a deterministic stub.
    public static let defaultFileExists: (String) -> (exists: Bool, isDirectory: Bool) = { path in
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return (exists, isDir.boolValue)
    }
}
