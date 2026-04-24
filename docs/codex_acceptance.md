# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J5`
- 当前阶段验收结论：`J4 PASS`
- 当前正式验收 session：`019dc07b-55f0-7712-9d7f-74441d7c81df`
- 日期：2026-04-25

### 当前审计结论
`98a1561` 已满足 J4 的自动化与文档要求，可以放行到 J5。

本轮实际确认：
- Schema 已升到 v7，新增 `query_history(query PK, last_used_at, use_count)` 和 `saved_filters(name PK, query, created_at, updated_at)`，与 `file_usage` 明确分离。
- `QueryHistoryTypes.swift` 已补齐 privacy toggle、query UPSERT、recent list、clear、saved filter save/remove/list，行为边界和 J4 任务书一致。
- 搜索窗底部动作栏已新增“最近/收藏”入口；设置窗口维护页已新增“搜索历史与 Saved Filters”区块，含开关、清空、列表、新建、删除。
- 查询记录锚定在 `.open` 成功后的 committed intent，而不是每次输入；这与本轮文档和隐私边界说明一致。
- build 与 smoke 实跑通过：`swift build --disable-sandbox` 成功，`swift run --disable-sandbox SwiftSeekSmokeTest` 为 `194/194`。

## 当前验收要求
J4 已 `PASS`。进入 J5 后，必须补齐结果右键菜单与文件操作增强，让用户减少跳回 Finder 的次数，但不能把 Reveal / Copy 计入 Run Count，也不能越界做完整文件管理器。

J5 验收时必须检查：
- 右键菜单包含约定动作，目标正确。
- Copy Name / Full Path / Parent Folder 写入剪贴板内容准确。
- Open With 使用公开 AppKit API。
- Move to Trash 有确认与失败反馈。
- 只有 Open 增加 Run Count。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
