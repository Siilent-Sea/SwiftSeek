import Foundation

/// N3 (everything-dockless-hardening) — pure formatter that turns the
/// raw inputs (persisted `dock_icon_visible`, live AppKit activation
/// policy, Info.plist `LSUIElement`) into the multi-line status text
/// the Settings page renders below the existing Dock checkbox.
///
/// Lives in Core so the smoke test can pin every label, divergence
/// warning, and bundle-path line without spinning AppKit. AppKit-bound
/// values (activation policy, LSUIElement, bundle path, executable
/// path) are passed in by the caller — same contract as
/// `Diagnostics.DockStatusReport`, kept in lock-step so a user copying
/// the Settings detail and the Diagnostics block see the same words.
public enum DockSettingsState {
    /// Composite snapshot. All `String` so the UI can drop them
    /// straight into multi-line labels without any further formatting.
    public struct Status: Equatable, Sendable {
        /// "用户希望显示 Dock" / "用户希望隐藏 Dock（默认）"
        public let intentLabel: String
        /// "regular（Dock 可见）" / "accessory（菜单栏 agent）" /
        /// "prohibited" / "unknown" / "—（headless 报告）"
        public let effectivePolicyLabel: String
        /// "true（包体声明 agent）" / "false（包体允许 Dock）" /
        /// "—（Info.plist 未声明该 key）" / "—（headless 报告）"
        public let plistLabel: String
        /// e.g. "/Applications/SwiftSeek.app"
        public let bundlePathLabel: String
        /// e.g. "/Applications/SwiftSeek.app/Contents/MacOS/SwiftSeek"
        public let executablePathLabel: String
        /// nil when intent and effective policy agree. Non-nil
        /// surfaces a `⚠️` text explaining why Dock visibility is
        /// what it is right now (helps a user decide whether to
        /// click "restore menu bar mode" or relaunch).
        public let divergenceWarning: String?
        /// One-line "what does the user see right now" summary,
        /// suitable for the Settings note line above the restore
        /// button.
        public let summaryLine: String
    }

    /// Compose a Status from the AppKit-bound inputs. The caller is
    /// responsible for translating `NSApp.activationPolicy()` into a
    /// short label ("regular" / "accessory" / "prohibited" /
    /// "unknown" / nil for headless) and for fetching
    /// `Info.plist.LSUIElement` as Bool? (nil for absent / not Bool /
    /// headless).
    ///
    /// `bundlePath` / `executablePath` should be the strings already
    /// surfaced by `BuildInfo.bundlePath` and `BuildInfo.executablePath`
    /// so all three surfaces (this Status, `Diagnostics.snapshot`, the
    /// startup `Dock — …` log line) match.
    public static func compose(dockIconVisibleSetting: Bool,
                               activationPolicyLabel: String?,
                               lsUIElement: Bool?,
                               bundlePath: String,
                               executablePath: String) -> Status {
        // --- intent ------------------------------------------------------
        let intentLabel = dockIconVisibleSetting
            ? "用户希望显示 Dock"
            : "用户希望隐藏 Dock（默认）"

        // --- effective activation policy ---------------------------------
        let effectivePolicyLabel: String
        switch activationPolicyLabel {
        case "regular":
            effectivePolicyLabel = "regular（Dock 可见）"
        case "accessory":
            effectivePolicyLabel = "accessory（菜单栏 agent）"
        case "prohibited":
            effectivePolicyLabel = "prohibited"
        case "unknown":
            effectivePolicyLabel = "unknown"
        case nil:
            effectivePolicyLabel = "—（headless 报告）"
        case .some(let other):
            effectivePolicyLabel = other  // forward unknown labels verbatim
        }

        // --- plist LSUIElement ------------------------------------------
        let plistLabel: String
        if let v = lsUIElement {
            plistLabel = v
                ? "true（包体声明 agent）"
                : "false（包体允许 Dock）"
        } else if activationPolicyLabel != nil {
            plistLabel = "—（Info.plist 未声明该 key）"
        } else {
            plistLabel = "—（headless 报告）"
        }

        // --- divergence warning -----------------------------------------
        // Live activation policy "regular" but user intent = hidden →
        // means a previous run set dock_icon_visible=1 and the user
        // now expects no Dock; suggest restoring + relaunching.
        // Inverse: live "accessory" but user intent = visible → means
        // the toggle change hasn't taken effect yet (needs relaunch).
        var divergenceWarning: String? = nil
        if activationPolicyLabel == "regular" && !dockIconVisibleSetting {
            divergenceWarning =
                "⚠️ 当前进程已是 .regular（Dock 可见），但 dock_icon_visible 已是 0；下次启动会回到 agent 模式。可点下方“恢复菜单栏模式”确认设置不被未来意外翻回 1，然后退出 SwiftSeek 重启即可彻底隐藏 Dock。"
        } else if activationPolicyLabel == "accessory" && dockIconVisibleSetting {
            divergenceWarning =
                "⚠️ 当前进程是 .accessory（菜单栏 agent），但 dock_icon_visible 已是 1；这是因为切换需重启生效。退出 SwiftSeek 并重新打开后会切到 .regular（Dock 出现）。"
        }

        // --- summary line -----------------------------------------------
        // One-line "what would a user see right now". Tailored to the
        // common case (intent matches policy) and the two divergence
        // cases above.
        let summaryLine: String
        if dockIconVisibleSetting {
            switch activationPolicyLabel {
            case "regular":
                summaryLine = "✓ 当前以普通 App 形态运行：Dock 中可见，菜单栏入口同时保留。"
            case "accessory":
                summaryLine = "⚠️ 已勾选「在 Dock 显示」，但当前进程仍是菜单栏 agent；重启后生效。"
            case nil:
                summaryLine = "用户设置希望显示 Dock。当前 activation policy 未探测（headless）。"
            default:
                summaryLine = "用户设置希望显示 Dock。当前 activation policy=\(effectivePolicyLabel)。"
            }
        } else {
            switch activationPolicyLabel {
            case "accessory":
                summaryLine = "✓ 当前以菜单栏 agent 形态运行（默认）：Dock 中不显示，仅保留菜单栏入口。"
            case "regular":
                summaryLine = "⚠️ 设置已是隐藏 Dock，但当前进程仍是 .regular；这通常意味着上一次启动 dock_icon_visible 还是 1，下次启动会切回 agent。"
            case nil:
                summaryLine = "用户设置希望隐藏 Dock（默认）。当前 activation policy 未探测（headless）。"
            default:
                summaryLine = "用户设置希望隐藏 Dock（默认）。当前 activation policy=\(effectivePolicyLabel)。"
            }
        }

        return Status(intentLabel: intentLabel,
                      effectivePolicyLabel: effectivePolicyLabel,
                      plistLabel: plistLabel,
                      bundlePathLabel: bundlePath,
                      executablePathLabel: executablePath,
                      divergenceWarning: divergenceWarning,
                      summaryLine: summaryLine)
    }

    /// N3: render the Settings detail block as a single newline-joined
    /// String for an `NSTextField(wrappingLabelWithString:)`. Field
    /// labels are kept in lock-step with `Diagnostics.snapshot`'s
    /// "Dock 状态（N1）：" block (intent / effective policy / plist /
    /// bundle / executable) so a user copying either surface sees the
    /// same vocabulary.
    public static func detailText(_ status: Status) -> String {
        var lines: [String] = [
            status.summaryLine,
            "  用户意图：\(status.intentLabel)",
            "  effective activation policy：\(status.effectivePolicyLabel)",
            "  Info.plist LSUIElement：\(status.plistLabel)",
            "  bundle path：\(status.bundlePathLabel)",
            "  executable path：\(status.executablePathLabel)",
        ]
        if let warn = status.divergenceWarning {
            lines.append(warn)
        }
        return lines.joined(separator: "\n")
    }
}
