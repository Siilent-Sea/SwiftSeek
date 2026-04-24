# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J2`
- 当前阶段验收结论：`J1 PASS`
- 当前正式验收 session：尚未创建
- 日期：2026-04-25

### 当前审计结论
`14c94ab` 已满足 J1 的自动化与文档要求，可以放行到 J2。

本轮实际确认：
- `SettingsWindowController` 现在自己担任 `NSWindowDelegate`，`windowShouldClose(_:)` 走 hide-only：`orderOut(nil)` + `return false`，设置窗口不会进入不可恢复的 closed 状态。
- `AppDelegate.showSettings(_:)` 先 `NSApp.activate`，并在 controller 存在但 `window == nil` 时防御性重建。
- `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` 已补齐，覆盖无可见窗口时的 Dock reopen。
- `Sources/SwiftSeekSmokeTest/main.swift` 新增 J1 smoke，用 `NSWindow` + hide-only delegate stand-in 覆盖关闭后可重复重开 10 次的模式验证。
- `docs/manual_test.md` 已补 J1 GUI 手测步骤；`docs/known_issues.md` 已把设置窗口关闭后不可重开、Dock/Menu Bar/主菜单 reopen 问题标记为 J1 已解决。
- `Sources/` 本轮改动只涉及 `AppDelegate.swift`、`SettingsWindowController.swift`、`SwiftSeekSmokeTest/main.swift`，没有提前实现 J2-J6，也没有触碰 `SearchEngine` / `SearchResult` / `Schema`。

## 当前验收要求
J1 已 `PASS`。进入 J2 后，必须重新以“用户实际可见”为准复核 Run Count / 最近打开，而不是只重复 H1-H5 数据层已存在。

J2 验收时必须检查：
- 结果表“打开次数 / 最近打开”默认可见且语义清楚。
- 历史列宽异常时有恢复默认列宽或等价恢复路径。
- `recordOpen`、结果列显示、`recent:` / `frequent:` 三者对同一数据一致。
- Run Count 文档和 UI 都明确只统计 SwiftSeek 内部成功 `.open`。
- build / smoke 仍通过；GUI 可见性用手测补齐证据。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
