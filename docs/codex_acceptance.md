# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J1`
- 当前阶段验收结论：尚未验收
- 当前正式验收 session：尚未创建
- 日期：2026-04-25

### 当前审计结论
本轮只做新轨道立项与任务书落盘，不假装已经修复业务代码。

已确认的代码优先事实：
- `AppDelegate.showSettings(_:)` 会复用 `settingsWindowController`，并调用 `showWindow` / `makeKeyAndOrderFront`。
- `SettingsWindowController` 的 `NSWindow` 已设置 `isReleasedWhenClosed = false`。
- 当前没有 `applicationShouldHandleReopen(_:hasVisibleWindows:)`。
- 当前没有设置窗口 `windowShouldClose` / hide-only delegate 策略。
- 主菜单和菜单栏都有“设置…”入口，但用户已经复现关闭设置窗口后不可重新打开，因此 J1 必须以真实 GUI 手测为准。
- `Schema` v6、`UsageTypes`、`SearchEngine`、`SearchViewController` 已经有 usage / Run Count 数据链路和结果列，但用户反馈“没看到启动次数”，所以 J2 必须复核用户可见性，而不能只复述 H1-H5 已完成。

## 当前验收要求
J1 完成后，Codex 才能给出 `PASS` 或 `REJECT`。J1 不允许因为 `everything-usage` 已经 `PROJECT COMPLETE` 而自动通过。

验收时必须检查：
- 设置窗口关闭后能从菜单栏图标重新打开。
- 设置窗口关闭后能从主菜单重新打开。
- 无可见窗口时 Dock 点击能重新唤起可操作窗口或明确入口。
- 搜索窗口 show / hide / toggle 行为没有回归。
- `docs/manual_test.md` 已补 J1 GUI 手测。
- build / smoke 仍通过，或记录不可运行原因。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
