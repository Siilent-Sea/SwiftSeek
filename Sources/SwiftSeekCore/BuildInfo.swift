import Foundation

/// K1 — runtime build-identity surface so users + dev can answer
/// "is this the bundle I think I'm running?" without guessing.
///
/// Reading order:
///   1. `Bundle.main.infoDictionary` — populated for `.app` bundles
///      whose `Info.plist` carries `CFBundleShortVersionString`,
///      `GitCommit`, and `BuildDate` keys (K2 will automate writing
///      these; K1 only consumes them).
///   2. Hard-coded fallback constants — used when running via
///      `swift run` / no Info.plist (e.g. dev loop).
///
/// Never returns nil so the About / Diagnostics UI and startup
/// logging always have a printable string. "dev" / "unknown" /
/// "0" make stale-bundle detection obvious in screenshots and
/// pasted diagnostics.
public enum BuildInfo {
    /// Default version when Info.plist key is missing. Bumped per
    /// release; tracks the SwiftSeek public version line.
    public static let fallbackAppVersion = "1.0-dev"

    /// Default commit when Info.plist key is missing. Used by
    /// `swift run` / fresh-clone dev path; release builds (.app
    /// produced by K2's package script) overwrite this via
    /// `GitCommit` Info.plist key.
    public static let fallbackGitCommit = "dev"

    /// Default build date when Info.plist key is missing.
    public static let fallbackBuildDate = "unknown"

    /// `CFBundleShortVersionString` if available, else
    /// `fallbackAppVersion`.
    public static var appVersion: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.isEmpty {
            return v
        }
        return fallbackAppVersion
    }

    /// Git commit short hash. Read from Info.plist key `GitCommit`
    /// (custom; K2 package script writes it). Falls back to
    /// `fallbackGitCommit` for `swift run` / dev builds.
    public static var gitCommit: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "GitCommit") as? String,
           !v.isEmpty {
            return v
        }
        return fallbackGitCommit
    }

    /// ISO-style timestamp set by the package script. Same Info.plist
    /// pattern as `gitCommit`.
    public static var buildDate: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "BuildDate") as? String,
           !v.isEmpty {
            return v
        }
        return fallbackBuildDate
    }

    /// Path to the running `.app` bundle, or "—" when the binary
    /// isn't bundled (CLI dev run). Useful for stale-bundle
    /// triage: if the path is `/Applications/SwiftSeek.app` but the
    /// user is editing source under `~/code/...`, that's a smoking
    /// gun.
    public static var bundlePath: String {
        let p = Bundle.main.bundlePath
        if p.isEmpty { return "—" }
        return p
    }

    /// Path to the actual executable. Differs from `bundlePath` when
    /// running outside `.app` (e.g. directly executing
    /// `.build/release/SwiftSeek`). Always non-empty in practice.
    public static var executablePath: String {
        Bundle.main.executablePath ?? "—"
    }

    /// One-line summary suitable for a startup log or About header.
    public static var summary: String {
        "SwiftSeek \(appVersion) commit=\(gitCommit) build=\(buildDate)"
    }

    /// Multi-line block for diagnostics copy-out.
    public static var multilineSummary: String {
        """
        version: \(appVersion)
        commit:  \(gitCommit)
        build:   \(buildDate)
        bundle:  \(bundlePath)
        binary:  \(executablePath)
        """
    }
}
