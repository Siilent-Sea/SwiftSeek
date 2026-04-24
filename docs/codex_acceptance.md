# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J6`
- 当前阶段验收结论：`J5 PASS`
- 当前正式验收 session：`019dc07b-55f0-7712-9d7f-74441d7c81df`
- 日期：2026-04-25

### 当前审计结论
`b7cbf79` 已满足 J5 的自动化与文档要求，可以放行到 J6。

本轮实际确认：
- 结果右键菜单已扩展为：打开、使用其他应用打开、在 Finder 中显示、复制名称、复制完整路径、复制所在文件夹路径、移到废纸篓。
- `PathHelpers.swift` 提供了纯 Foundation 的 `fileName(of:)` 和 `parentFolder(of:)`，GUI 动作和 smoke 共用同一语义。
- `openWithSelected()` 通过 `NSOpenPanel` + `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` 走公开 AppKit API，没有越界到 private API。
- `trashSelected()` 现在有二次确认；Rename 没有硬上，而是在文档里明确写出推迟原因。
- Run Count / query history 边界保持不变：只有 `openSelected()` 仍调用 `recordOpen` 与 `recordQueryHistory`；Reveal / Copy / Open With / Trash 都不接 usage 统计。
- build 与 smoke 实跑通过：`swift build --disable-sandbox` 成功，`swift run --disable-sandbox SwiftSeekSmokeTest` 为 `196/196`。

## 当前验收要求
J5 已 `PASS`。进入 J6 后，需要把首次使用、权限提示、Launch 行为、窗口状态记忆和最终文档收口统一补齐，并为 `everything-ux-parity` 的最终 `PROJECT COMPLETE` 做准备。

J6 验收时必须检查：
- 首次使用用户能看懂先加 root、为何需要权限、索引模式怎么选。
- 权限不足时不是沉默失败。
- Launch at Login 有真实实现或明确推迟说明，不能假实现。
- 窗口状态记忆不破坏现有列宽 / 排序持久化。
- README / manual_test / known_issues / ux parity gap / acceptance 文档与最终代码一致。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
