# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-filemanager-integration`
- 当前阶段：`M2`
- 最新验收结论：`PASS`
- 最新通过阶段：`M1`
- 当前正式验收 session：`019dc959-3bf6-7671-ace6-cf3a3598e592`
- 日期：2026-04-26

## M1 round 2 验收结论

`HEAD=fdae4714c987452c9231c2e725a171f9ff2188df` 通过 M1 验收。

Round 1 阻塞项已修复：

- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `onRevealTargetTypeChanged(_:)` 保存失败时现在会 `NSLog`、弹 `NSAlert`，并调用 `reflectRevealTargetState()` 回滚 UI 到已持久化状态。
- `onRevealOpenModeChanged(_:)` 同样会 `NSLog`、弹 `NSAlert`，并回滚 segmented 状态。
- `onPickRevealApp(_:)` 原有保存失败 `NSAlert` 仍保留。

M1 通过依据：

- `Sources/SwiftSeekCore/SettingsTypes.swift` 已有 `RevealTargetType`、`ExternalRevealOpenMode`、`RevealTarget.defaultTarget = (.finder, "", .parentFolder)`。
- 已有 `SettingsKey.revealTargetType` / `revealCustomAppPath` / `revealExternalOpenMode`。
- `Database.getRevealTarget()` / `setRevealTarget(_:)` 已落地；unknown type fallback 到 `.finder` 并保留 custom path，unknown open mode fallback 到 `.parentFolder`，missing path fallback 到 `""`。
- 设置页常规 pane 已有 Finder / 自定义 App popup、选择 App 按钮、`.application` `NSOpenPanel`、app summary、QSpace 文件名启发式、open mode segmented 和多行说明。
- 选择 `.app` 会保存为 `.customApp`，不存在隐藏选择状态。
- `ResultActionRunner.perform(.revealInFinder)` 仍是 Finder-only，M1 没有提前接入外部 app。
- 搜索窗口按钮和右键菜单仍是“在 Finder 中显示”，留给 M3 动态化。
- 未发现 QSpace bundle id、URL scheme、AppleScript 或 private API 接入。

## 本轮验证

已运行：

```bash
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox
plutil -p dist/SwiftSeek.app/Contents/Info.plist
plutil -lint dist/SwiftSeek.app/Contents/Info.plist
codesign -dv dist/SwiftSeek.app
```

观察结果：

- `swift build --disable-sandbox`：通过。
- `SwiftSeekSmokeTest`：229/229 通过。
- `package-app.sh --sandbox`：通过。
- `Info.plist`：`GitCommit=fdae471`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`。
- `codesign -dv`：`Signature=adhoc`、`Identifier=com.local.swiftseek`。
- L1-L4 / K1-K6 相关 smoke 覆盖项仍通过。

## 下一阶段

M2 任务书已写入 `docs/next_stage.md`。

M2 验收时重点检查：

- Finder 模式仍使用 `NSWorkspace.shared.activateFileViewerSelecting([url])`，不回退。
- custom app 模式按 `item` / `parentFolder` 解析并打开正确 URL。
- app path 空、失效、非 `.app`、打开失败时有用户可见反馈、NSLog，并 fallback 到 Finder。
- reveal / show 不增加 `file_usage.open_count`。
- 没有 QSpace 私有 API、bundle id、URL scheme 或 AppleScript。

## 历史归档轨道

- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`
- `everything-productization`：K1-K6 / PROJECT COMPLETE 2026-04-26，session `019dc54e-017d-7de3-a24f-35c23f09ce08`
- `everything-menubar-agent`：L1-L4 / PROJECT COMPLETE 2026-04-26，session `019dc5fc-318e-7d31-bb00-2810eaf6642c`

## 轨道切换说明

`everything-filemanager-integration` 使用当前新的 Codex 验收 session `019dc959-3bf6-7671-ace6-cf3a3598e592`；不得复用 `everything-menubar-agent` session `019dc5fc-318e-7d31-bb00-2810eaf6642c`，也不得复用更早归档轨道 session。
