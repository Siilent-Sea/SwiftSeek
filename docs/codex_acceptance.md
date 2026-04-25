# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-menubar-agent`
- 当前阶段：`L4`
- 上一阶段验收结论：`L3 PASS`
- 当前正式验收 session：`019dc5fc-318e-7d31-bb00-2810eaf6642c`
- 日期：2026-04-26

## L3 验收结论

L3 round 1 基于提交 `75d3a79` 验收，结论为 `PASS`。

本轮确认成立的事实：

- `Sources/SwiftSeekCore/MenubarStatus.swift` 是 AppKit-free 纯 formatter，提供 `Snapshot`、`snapshot(database:indexingDescription:)`、`formatRoots(rows:database:)` 和 `tooltipText(snapshot:)`。tooltip 固定 5 行：build、索引、模式、roots、DB 大小。
- `MenubarStatus.snapshot` 读取 BuildInfo、IndexMode、roots、RootHealth、DatabaseStats，并对字段读取失败给出短 fallback，不把状态读取错误扩散到 AppDelegate。
- `AppDelegate.installStatusItem()` 在原有索引行与退出分隔线之间加入 4 个 disabled 状态行：build、模式、roots、DB 大小。
- `AppDelegate` 作为 `NSMenuDelegate` 在 `menuNeedsUpdate(_:)` 中刷新状态；`reflectRebuildState(_:)` 更新 `lastIndexingDescription` 并调用 `refreshMenubarStatus()`，让 tooltip 在菜单关闭时也能跟随索引状态变化。
- `SwiftSeekSmokeTest` 新增 5 个 L3 用例：empty DB roots label、roots enabled count、不健康 roots、tooltip 5-line ordered format、`formatRoots([])`；总数从 212 提升到 217。
- `docs/install.md`、`docs/release_checklist.md`、`docs/known_issues.md`、`docs/manual_test.md` 已同步 L3 tooltip / 菜单状态 / fallback / non-goals。
- L3 round 1 未实现最近 / 常用子菜单；这是可接受的，因为 L3 taskbook 把它标为"如果实现"，不是必做项。
- L3 没有提前实现 L4 单实例 / 多 bundle 防护。

自动化验证：

- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox` 通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest` 通过，结果 `217/217`，5 个 L3 用例均通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox` 通过，并生成 `dist/SwiftSeek.app`。
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 显示 `LSUIElement => false`、`GitCommit => 75d3a79`、`CFBundleIdentifier => com.local.swiftseek`。
- `plutil -lint dist/SwiftSeek.app/Contents/Info.plist` 通过。
- `codesign -dv --verbose=2 dist/SwiftSeek.app` 显示 `Identifier=com.local.swiftseek`、`Signature=adhoc`、`TeamIdentifier=not set`。
- `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns` 存在，大小 273908 bytes，`file` 显示 Mac OS X icon / `ic04` type。

验收侧文档收口：

- `docs/release_checklist.md` 调整 §5c / §5d 顺序，保持 L2 在 L3 前。
- `docs/known_issues.md` 把 L3 相关残留表述改为已落地，并把后续未完成范围收窄为 L4。

未在本沙箱执行的验证：

- 真实 GUI tooltip 弹出。
- 菜单打开时 `menuNeedsUpdate(_:)` 的实际刷新。
- 索引状态图标切换与 tooltip/menu 文本同步。
- Dock visible 模式下菜单栏状态增强的兼容性。

这些 GUI 项已写入 `docs/manual_test.md` §33aa 与 `docs/release_checklist.md` §5d，发布前仍必须在真实 macOS GUI 环境中手动执行。

## 当前验收要求

下一次 Codex 验收应检查 L4：单实例 / 多 bundle 防护与最终收口。

L4 验收时至少检查：

- 重复打开同一 `.app` 不会产生两个长期常驻菜单栏实例。
- `dist/SwiftSeek.app` 与 `/Applications/SwiftSeek.app` 并存时，行为可解释且有日志或文档化处理路径。
- Launch at Login 与手动启动并发不造成重复常驻。
- 检测到已有实例时，新实例不会静默长期常驻；能唤醒旧实例则唤醒，不能唤醒则日志清楚并退出。
- L1 no Dock、L2 Dock 显示开关、L3 菜单栏状态、搜索、设置、退出和全局热键不回归。
- `docs/install.md`、`docs/manual_test.md`、`docs/release_checklist.md`、`docs/known_issues.md`、`docs/stage_status.md` 已同步 L4。
- 若 L4 通过且没有残留阻塞项，Codex 可判断 `everything-menubar-agent` 是否达到 `PROJECT COMPLETE`。

## 历史归档轨道

- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`
- `everything-productization`：K1-K6 / PROJECT COMPLETE 2026-04-26，session `019dc54e-017d-7de3-a24f-35c23f09ce08`

## 轨道切换说明

`everything-menubar-agent` 使用新的 Codex 验收 session `019dc5fc-318e-7d31-bb00-2810eaf6642c`；不得复用 `everything-productization` session `019dc54e-017d-7de3-a24f-35c23f09ce08`，也不得复用更早归档轨道 session。
