# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-menubar-agent`
- 当前阶段：`L4`
- 当前阶段验收结论：`PROJECT COMPLETE`
- 当前正式验收 session：`019dc5fc-318e-7d31-bb00-2810eaf6642c`
- 日期：2026-04-26

## L4 验收结论

L4 round 1 基于提交 `73cac42` 验收，结论为 `PROJECT COMPLETE`。

本轮确认成立的事实：

- `Sources/SwiftSeekCore/SingleInstance.swift` 是 AppKit-free 纯 helper，提供 `Sibling`、`chooseSibling(myPid:candidates:)`、`conflictLogLine(...)` 和稳定 notification name `com.local.swiftseek.menubar-agent.show-settings`。
- `chooseSibling` 过滤当前 pid，并在多个 sibling 中选择最低 pid 作为 canonical owner。
- `conflictLogLine` 一行内包含 sibling pid / bundle / exec、our pid / bundle / exec，并明确写出 `deferring to sibling and exiting`。
- `AppDelegate.applicationDidFinishLaunching` 顺序正确：K1 build identity 三连 → `maybeDeferToExistingInstance()` → `installShowSettingsObserver()` → L1 `.accessory` → main menu / DB / L2 preference / coordinator / status item / search window / hotkey。
- 检测到 sibling 时，新实例日志记录冲突，激活旧实例，发送 distributed notification 要求旧实例 show settings，并在下一 runloop tick `NSApp.terminate(nil)`；early return 不安装第二套 status item、hotkey 或 DB writer。
- bundle id 为 nil 的 raw `swift run` dev 路径有明确 skip 日志并正常 fall through。
- `SwiftSeekSmokeTest` 新增 6 个 L4 用例；总数从 217 提升到 223。
- `docs/install.md`、`docs/release_checklist.md`、`docs/known_issues.md`、`docs/manual_test.md` 已同步 L4 单实例 / 多 bundle 防护、边界和手测矩阵。

自动化验证：

- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox` 通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest` 通过，结果 `223/223`，6 个 L4 用例均通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox` 通过，并生成 `dist/SwiftSeek.app`。
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 显示 `LSUIElement => false`、`GitCommit => 73cac42`、`CFBundleIdentifier => com.local.swiftseek`。
- `plutil -lint dist/SwiftSeek.app/Contents/Info.plist` 通过。
- `codesign -dv --verbose=2 dist/SwiftSeek.app` 显示 `Identifier=com.local.swiftseek`、`Signature=adhoc`、`TeamIdentifier=not set`。
- `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns` 存在，大小 273908 bytes，`file` 显示 Mac OS X icon / `ic04` type。

验收侧文档收口：

- `docs/release_checklist.md` smoke baseline 更新为 223。
- `docs/known_issues.md` 把 L4 相关残留表述改为已落地，保留 ad-hoc / 未公证 / 无 DMG / 无 auto updater 边界。
- `docs/next_stage.md` 改为无下一阶段任务书。
- `docs/stage_status.md`、`docs/agent-state/*` 已同步 `PROJECT COMPLETE`。

未在本沙箱执行的验证：

- 真实 GUI 多实例场景。
- `NSRunningApplication.runningApplications(withBundleIdentifier:)` 在真实 LaunchServices 中的返回。
- `DistributedNotificationCenter` round-trip。
- 菜单栏图标去重、旧实例窗口前置、Launch at Login + 手动启动 race。

这些 GUI 项已写入 `docs/manual_test.md` §33ab 与 `docs/release_checklist.md` §5e，发布前仍必须在真实 macOS GUI 环境中手动执行。

## 轨道最终结论

`everything-menubar-agent` 达到 `PROJECT COMPLETE`：

- L1：默认隐藏 Dock + 菜单栏主入口，已通过。
- L2：Dock 显示开关与激活策略稳定化，已通过。
- L3：菜单栏菜单增强与状态可见性，已通过。
- L4：单实例 / 多 bundle 防护与最终收口，已通过。
- K1-K6 productization 能力没有回退。
- 当前仍明确不承诺正式 Developer ID 签名、公证、DMG、auto updater、跨用户单实例、private API 或新搜索能力。

## 历史归档轨道

- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`
- `everything-productization`：K1-K6 / PROJECT COMPLETE 2026-04-26，session `019dc54e-017d-7de3-a24f-35c23f09ce08`
- `everything-menubar-agent`：L1-L4 / PROJECT COMPLETE 2026-04-26，session `019dc5fc-318e-7d31-bb00-2810eaf6642c`

## 后续说明

当前没有下一阶段任务书。后续如果开启新轨道，必须重新更新 `docs/stage_status.md` 与对应 gap / taskbook；历史 `PROJECT COMPLETE` 不自动传递给新轨道。
