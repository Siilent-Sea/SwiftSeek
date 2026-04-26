import AppKit
import SwiftSeekCore

/// AppKit-side executor for `ResultAction`. Keeps `SwiftSeekCore` free of
/// `AppKit` while funnelling every real side-effect through one place.
///
/// H1: `perform` returns `Bool` — the caller needs to know whether
/// `.open` succeeded before writing to the usage table (we refuse to
/// bump `open_count` on a failed open). `.revealInFinder` and
/// `.copyPath` always return true; they have no failure mode we need
/// to surface for usage purposes.
///
/// M2 (everything-filemanager-integration): `.revealInFinder` is no
/// longer "always Finder" — when the caller passes a `database` the
/// runner reads the persisted `RevealTarget` and routes through the
/// `RevealResolver` strategy. Finder mode keeps the existing
/// `activateFileViewerSelecting` behaviour; custom-app mode hands the
/// target URL to the user-chosen `.app` via `NSWorkspace.open(...,
/// withApplicationAt:configuration:completionHandler:)`. Failures
/// (path empty / missing / not a `.app` / open returns error) fall
/// back to Finder + NSLog + invoke the optional `onFallback` so the
/// caller can surface a user-visible toast / alert.
///
/// `database` is optional so existing call sites (and Core unit
/// helpers) that don't have a Database handle still work — they just
/// keep the original Finder-only behaviour, matching M1 default.
enum ResultActionRunner {
    /// AppKit-friendly outcome surface. The reveal handler reports
    /// what actually happened so `SearchViewController` can decide
    /// whether to show a fallback toast.
    enum RevealOutcome {
        case finder
        case customApp(appName: String)
        case fallback(reason: String)
    }

    @discardableResult
    static func perform(_ action: ResultAction, target: ResultTarget) -> Bool {
        return perform(action, target: target, database: nil, onReveal: nil)
    }

    @discardableResult
    static func perform(_ action: ResultAction,
                        target: ResultTarget,
                        database: Database?,
                        onReveal: ((RevealOutcome) -> Void)?) -> Bool {
        let url = URL(fileURLWithPath: target.path)
        switch action {
        case .open:
            // NSWorkspace.open(URL) is the documented public entry point
            // and returns false when no handler was available or the URL
            // could not be opened.
            return NSWorkspace.shared.open(url)
        case .revealInFinder:
            performReveal(target: target, database: database, onReveal: onReveal)
            return true
        case .copyPath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(target.path, forType: .string)
            return true
        }
    }

    /// M2: route a reveal click through the persisted RevealTarget.
    /// Falls back to Finder for any of: no Database, read failure,
    /// .finder type, validation failure, NSWorkspace.open error.
    private static func performReveal(target: ResultTarget,
                                      database: Database?,
                                      onReveal: ((RevealOutcome) -> Void)?) {
        let url = URL(fileURLWithPath: target.path)
        // No DB handle (smoke test path, early init, etc.) → Finder.
        guard let db = database else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onReveal?(.finder)
            return
        }
        // DB read failure → Finder + log.
        let revealTarget: RevealTarget
        do {
            revealTarget = try db.getRevealTarget()
        } catch {
            NSLog("SwiftSeek: getRevealTarget failed, falling back to Finder: \(error)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onReveal?(.fallback(reason: "读取 reveal target 设置失败：\(error)"))
            return
        }
        let strategy = RevealResolver.decideStrategy(target: target, revealTarget: revealTarget)
        switch strategy {
        case .finder(let targetURL):
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            onReveal?(.finder)
        case .customApp(let appURL, let targetURL):
            let appName = (appURL.path as NSString).lastPathComponent
            let config = NSWorkspace.OpenConfiguration()
            // Bring the external app to the foreground so the user
            // sees it react to the reveal click; activates = true is
            // the documented way to mirror Finder's behaviour.
            config.activates = true
            // M2 round 2: capture the ORIGINAL target URL outside the
            // closure so the async-failure Finder fallback selects
            // the user's actual file, not the resolved external-app
            // URL (which is the parent dir under .parentFolder mode).
            // RevealResolver.finderFallbackURL(target:) is the single
            // source of truth and has dedicated smoke coverage.
            let fallbackURL = RevealResolver.finderFallbackURL(target: target)
            NSWorkspace.shared.open([targetURL],
                                    withApplicationAt: appURL,
                                    configuration: config) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        // Open failed at runtime (app crashed, signature
                        // rejection, sandbox refusal, etc.). Log + Finder
                        // fallback (using ORIGINAL target URL) + notify
                        // caller so they can show a toast.
                        NSLog("SwiftSeek: NSWorkspace.open failed for app=\(appURL.path) target=\(targetURL.path) — \(error). Falling back to Finder selecting original target=\(fallbackURL.path).")
                        NSWorkspace.shared.activateFileViewerSelecting([fallbackURL])
                        onReveal?(.fallback(reason: "用 \(appName) 打开失败：\(error.localizedDescription)"))
                    } else {
                        onReveal?(.customApp(appName: appName))
                    }
                }
            }
        case .fallbackToFinder(let targetURL, let reason):
            NSLog("SwiftSeek: reveal fell back to Finder — \(reason)")
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            onReveal?(.fallback(reason: reason))
        }
    }
}
