import Foundation

/// L4 — pure helpers for the single-instance defense. The
/// AppKit-bound parts (NSRunningApplication query, distributed
/// notification posting/observing, NSApp.terminate) live in the
/// app target's AppDelegate; this Core file owns the formatting
/// and decision logic that can be smoke-tested without spinning
/// the GUI.
public enum SingleInstance {
    /// One detected sibling instance, summarized in a way that
    /// doesn't depend on AppKit. The app target builds these from
    /// `NSRunningApplication.bundleURL` / `executableURL` /
    /// `processIdentifier`.
    public struct Sibling: Equatable, Sendable {
        public let pid: Int32
        public let bundlePath: String?
        public let executablePath: String?

        public init(pid: Int32, bundlePath: String?, executablePath: String?) {
            self.pid = pid
            self.bundlePath = bundlePath
            self.executablePath = executablePath
        }
    }

    /// Decide whether a newly-launching SwiftSeek should defer to a
    /// sibling. Returns nil if no qualifying sibling exists; returns
    /// the sibling that should be activated otherwise.
    ///
    /// Design:
    ///   - "Sibling" means a running app instance with the same bundle
    ///     id but a different process id. The caller is responsible
    ///     for filtering by bundle id; this function operates over the
    ///     pre-filtered list and excludes our own pid.
    ///   - When multiple siblings exist (rare; user manually launched
    ///     three times), pick the lowest pid as the canonical owner.
    ///     Lower pid ≈ older process; deferring to the older process
    ///     gives the most stable user experience (it already has
    ///     menubar item / hotkey installed).
    ///   - Returning nil is the "we are first" path; the caller should
    ///     proceed with normal startup.
    public static func chooseSibling(myPid: Int32,
                                     candidates: [Sibling]) -> Sibling? {
        let others = candidates.filter { $0.pid != myPid }
        guard !others.isEmpty else { return nil }
        // Prefer lowest pid (oldest process).
        return others.min(by: { $0.pid < $1.pid })
    }

    /// Format a one-line conflict log suitable for NSLog, including
    /// our own identity (so stale-bundle bug reports get to triage
    /// the same way K1 does) and the sibling we detected. Caller
    /// passes our own bundle / executable path explicitly because
    /// `BuildInfo.bundlePath` / `executablePath` already encode the
    /// dev-fallback rules we want to keep.
    public static func conflictLogLine(ourPid: Int32,
                                       ourBundlePath: String,
                                       ourExecutablePath: String,
                                       sibling: Sibling) -> String {
        let theirBundle = sibling.bundlePath ?? "?"
        let theirExec = sibling.executablePath ?? "?"
        return "SwiftSeek: another instance detected — sibling pid=\(sibling.pid) bundle=\(theirBundle) exec=\(theirExec); our pid=\(ourPid) bundle=\(ourBundlePath) exec=\(ourExecutablePath); deferring to sibling and exiting"
    }

    /// Distributed notification name used to ask an existing
    /// SwiftSeek instance to surface its settings window. Posting
    /// this from a launching second instance is best-effort: the
    /// receiver might not be ready, might be in a different user
    /// session, or might ignore for other reasons. Caller should
    /// also call `NSRunningApplication.activate(options:)` directly
    /// as the more reliable activation path.
    public static let showSettingsNotificationName = "com.local.swiftseek.menubar-agent.show-settings"
}
