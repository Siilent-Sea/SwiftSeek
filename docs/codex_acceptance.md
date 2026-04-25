# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K1`
- 当前阶段验收结论：尚未验收
- 当前正式验收 session：尚未创建
- 日期：2026-04-25

### 当前审计结论
本轮只做新轨道立项与任务书落盘，不假装已经完成打包或产品化。

已确认的代码优先事实：
- `everything-ux-parity` 已归档：J1-J6 已完成设置窗口生命周期、Run Count 可见性、查询表达、搜索历史、上下文菜单、首次使用引导、Launch at Login 说明与窗口状态记忆。
- `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` 已存在，无可见窗口时调用 `showSettings(nil)`。
- `SettingsWindowController.windowShouldClose(_:)` 已实现 hide-only close。
- `SettingsWindowController` 当前通过 KVO 观察 `selectedTabViewItemIndex`，没有使用非法 `tabView.delegate`。
- `LaunchAtLogin.swift` 使用公开 `SMAppService.mainApp`，但注释与 UI 已承认未签名 / 未公证构建可能失败或需系统批准。
- `scripts/build.sh` 仍只交付 `.build/release` 可执行文件；脚本注释明确不做 `.app` bundle / signing / notarization。
- `scripts/build.sh` 末尾仍打印“schema 当前为 v3”，但当前 `Schema.currentVersion` 是 7。
- `scripts/make-icon.swift` 只生成 iconset PNG，仍需手工 `iconutil` 生成 `AppIcon.icns`。
- 本地存在 `SwiftSeek.app/Contents/Info.plist` 与 `AppIcon.icns`，`codesign -dv` 显示 ad-hoc 签名；但 `SwiftSeek.app/` 被 `.gitignore` 忽略，不是可重复发布流水线。
- About / diagnostics 目前没有 app version、commit、build timestamp、bundle path、executable path 等稳定 build identity。

## 当前验收要求
K1 完成后，Codex 才能给出 `PASS` 或 `REJECT`。K1 不允许因为 `everything-ux-parity` 已经 `PROJECT COMPLETE` 而自动通过。

验收时必须检查：
- 设置窗口 release gate 已写入 `docs/manual_test.md` 或等价 checklist。
- 设置窗口关闭 / 菜单栏重开 / 主菜单重开 / Dock reopen 路径可执行。
- 设置 tab 切换不使用非法 delegate 方案。
- About / diagnostics 或等价 UI 显示 build identity。
- 启动日志打印 build identity。
- `scripts/build.sh` 不再输出 schema v3 等过期内容。
- build / smoke 仍通过，或记录不可运行原因。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`

## 轨道切换说明
`everything-productization` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
