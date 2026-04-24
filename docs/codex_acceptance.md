# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J3`
- 当前阶段验收结论：`J2 PASS`
- 当前正式验收 session：`019dc07b-55f0-7712-9d7f-74441d7c81df`
- 日期：2026-04-25

### 当前审计结论
`69a7098` 已满足 J2 的自动化与文档要求，可以放行到 J3。

本轮实际确认：
- `SearchWindowController` 默认宽度从 680 调到 1020，并设置 `setFrameAutosaveName("SwiftSeekSearchPanel")`，默认窗口已能容纳 H2 六列。
- `SearchViewController` 给“打开次数 / 最近打开”列补了明确 tooltip，并把 header 右键菜单绑定到“重置列宽”；重置时会清理持久化列宽、即时恢复默认列宽，并在窗口过窄时自动拉宽。
- `Database.resetResultColumnWidths()` 只清 6 个 `result_col_width_*` 键，并逐项失效 settings cache；不会碰 `result_sort_key` / `result_sort_asc`。
- `Sources/SwiftSeekSmokeTest/main.swift` 新增 3 条 J2 smoke，覆盖列宽重置、幂等性和“不会破坏排序设置”。
- `docs/manual_test.md` 已补 J2 GUI 手测步骤；`docs/known_issues.md` 已把 Run Count 可见性问题改成“J2 已落地”。
- `Sources/` 本轮改动只涉及 `SearchWindowController.swift`、`SearchViewController.swift`、`SettingsTypes.swift`、`SwiftSeekSmokeTest/main.swift`，没有提前实现 J3-J6，也没有改动 H1-H5 usage 数据链路或 H2 tie-break 语义。

## 当前验收要求
J2 已 `PASS`。进入 J3 后，必须补齐 wildcard / quote / OR / NOT 查询语法，但不能把 DSL 扩成括号表达式或 regex，也不能牺牲既有热路径表现。

J3 验收时必须检查：
- `*` / `?` wildcard、quoted phrase、OR、NOT 的语义清晰且与现有 `ext:` / `path:` / `recent:` / `frequent:` 可组合。
- 非法语法不崩溃，能容错为字面量或空结果。
- GUI 与 CLI 查询语义一致。
- build / smoke 仍通过；复杂语法不能把热路径明显拖垮。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
