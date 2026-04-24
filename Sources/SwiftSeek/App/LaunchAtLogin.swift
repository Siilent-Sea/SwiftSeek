import Foundation
import ServiceManagement

/// J6 — thin wrapper around `SMAppService.mainApp` to register /
/// unregister SwiftSeek as a login item.
///
/// Real caveat: `SMAppService` inspects the app bundle's code
/// signature. An unsigned SwiftPM binary + ad-hoc signed `.app`
/// bundle MAY register successfully but the login trigger can be
/// unreliable across macOS updates. We surface any
/// `register()` / `unregister()` errors verbatim; callers (the
/// Settings UI) show them to the user. We do NOT silently swallow
/// failures — that would be an anti-pattern ("checkbox on but no
/// launch happens").
enum LaunchAtLogin {
    enum ToggleError: Error, CustomStringConvertible {
        case unsupportedOS
        case registerFailed(String)
        case unregisterFailed(String)
        var description: String {
            switch self {
            case .unsupportedOS:
                return "当前系统不支持 SMAppService 登录项 API（需要 macOS 13+）"
            case let .registerFailed(m): return "注册登录项失败：\(m)"
            case let .unregisterFailed(m): return "取消登录项失败：\(m)"
            }
        }
    }

    /// Current registration state (live query from SMAppService).
    /// Returns nil on unsupported OS / undecipherable state rather
    /// than lying.
    static func isRegistered() -> Bool? {
        guard #available(macOS 13, *) else { return nil }
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            return true
        case .notRegistered, .notFound:
            return false
        case .requiresApproval:
            // User has to approve in System Settings -> General ->
            // Login Items. Treat as "not yet effective" from UI's
            // perspective; the checkbox stays visually ON because
            // the user asked for it.
            return true
        @unknown default:
            return nil
        }
    }

    /// Attempt to register. Throws on failure so the UI can show
    /// the real error. On success the live status may still be
    /// `.requiresApproval` — callers should nudge the user to
    /// System Settings in that case.
    static func register() throws {
        guard #available(macOS 13, *) else { throw ToggleError.unsupportedOS }
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw ToggleError.registerFailed(error.localizedDescription)
        }
    }

    static func unregister() throws {
        guard #available(macOS 13, *) else { throw ToggleError.unsupportedOS }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw ToggleError.unregisterFailed(error.localizedDescription)
        }
    }
}
