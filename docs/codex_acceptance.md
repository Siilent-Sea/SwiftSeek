# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前轨道：`everything-dockless-hardening`
- 当前阶段：`N2`
- 最新验收结论：`PASS`（N1）
- 当前正式验收 session：`be0f0316-31b1-479f-be88-6069e185762c`
- 日期：2026-04-27

## 新轨道立项原因

用户真实反馈：`everything-menubar-agent` 已归档后，实际使用中 SwiftSeek 仍常驻 Dock。历史文档中的“默认 no Dock”不能再作为当前事实。

本轮代码优先审计确认：

- `scripts/package-app.sh` 仍写 `<key>LSUIElement</key><false/>`。
- `Sources/SwiftSeek/App/AppDelegate.swift` 启动时先 `NSApp.setActivationPolicy(.accessory)`，DB 打开后读取 `dock_icon_visible`。
- 如果 `dock_icon_visible=1`，AppDelegate 会切到 `.regular` 并记录 `Dock icon visible (user preference)`。
- `Sources/SwiftSeekCore/SettingsTypes.swift` 已有 `dock_icon_visible` 设置，默认 false；true 表示下次启动显示 Dock。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 已有 Dock 显示复选框和重启说明；N1 后已有完整 Dock 状态诊断，但还没有一键恢复菜单栏模式。
- `Sources/SwiftSeekCore/Diagnostics.swift` 已在 N1 增加 Dock mode 专用块，可直接展示 persisted setting、effective activation policy、Info.plist `LSUIElement`、bundle path、executable path。

## N1 验收结论

结论：`PASS`

验收依据：

- `Sources/SwiftSeekCore/Diagnostics.swift` 已新增 `DockStatusReport` / `DockStatusProbe`，`snapshot(...)` 已增加 `dockStatus` 可选 probe，并输出 `Dock 状态（N1）：` 块。
- `Sources/SwiftSeek/App/AppDelegate.swift` 已新增 `lsUIElementValueLabel()`、`lsUIElementBool()`、`activationPolicyLabel()`、`currentDockStatusReport()`，启动日志统一输出 `Dock — Info.plist LSUIElement=...; persisted dock_icon_visible=...; chosen activation policy=...`。
- `dock_icon_visible=1` 分支额外说明 Dock 可见来自用户设置，并给出设置页关闭路径；DB 读取失败 / 无 DB 分支保持 `.accessory` 默认并显式记录。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 的 About diagnostics 已传入 `dockStatus: { AppDelegate.currentDockStatusReport() }`。
- `Sources/SwiftSeekSmokeTest/main.swift` 已新增 6 个 N1 用例，完整 smoke 为 `262/262`。
- `docs/known_issues.md` 已把第 3 节改为 N1 已落地，并保留 SQLite / `plutil` 作为 fallback 排查路径。

边界确认：

- `scripts/package-app.sh` 仍写 `LSUIElement=false`。
- `SettingsKey.dockIconVisible = "dock_icon_visible"` 仍存在，默认缺失 / `0` 为隐藏 Dock。
- `AppDelegate` 仍默认先 `.accessory`，只在 `dock_icon_visible=1` 时切 `.regular`。
- N1 没有强制重写用户 DB，也没有声称 Dock 已最终稳定隐藏。

本轮实际验证：

- `env CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox --scratch-path /tmp/swiftseek-build`：通过。
- `env CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox --scratch-path /tmp/swiftseek-smoke SwiftSeekSmokeTest`：`262/262` 通过。
- `env CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox`：通过。
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist`：`GitCommit=9741d52`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`。
- `plutil -lint dist/SwiftSeek.app/Contents/Info.plist`：OK。
- `codesign -dv dist/SwiftSeek.app`：`Signature=adhoc`。
- 受当前沙箱限制，未做 GUI 启动 Console 手测；该项留到 N4 release-time 手测 gate。

## 下一阶段

见 [docs/next_stage.md](next_stage.md)。当前下一阶段为 N2。

## 历史归档轨道

- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`
- `everything-productization`：K1-K6 / PROJECT COMPLETE 2026-04-26，session `019dc54e-017d-7de3-a24f-35c23f09ce08`
- `everything-menubar-agent`：L1-L4 / PROJECT COMPLETE 2026-04-26，session `019dc5fc-318e-7d31-bb00-2810eaf6642c`
- `everything-filemanager-integration`：M1-M4 / PROJECT COMPLETE 2026-04-26，session `019dc959-3bf6-7671-ace6-cf3a3598e592`

## 会话规则

- `everything-dockless-hardening` 使用新的正式 Codex 验收 session `be0f0316-31b1-479f-be88-6069e185762c`。
- 不得复用 `everything-filemanager-integration` 的完成 session `019dc959-3bf6-7671-ace6-cf3a3598e592`。
- `docs/agent-state/codex-acceptance-session.txt` 与 `.json` 必须继续指向当前轨道 session。
