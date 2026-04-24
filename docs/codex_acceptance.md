# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J4`
- 当前阶段验收结论：`J3 PASS`
- 当前正式验收 session：`019dc07b-55f0-7712-9d7f-74441d7c81df`
- 日期：2026-04-25

### 当前审计结论
`695b1ae` 已满足 J3 的自动化与文档要求，可以放行到 J4。

本轮实际确认：
- `orUnionCandidates()` 现在会在遇到纯 wildcard alt 时拉起一次 bounded scan union，补齐 `*|foo` / `*|?` 这类无 anchor alt 的覆盖面。
- `Sources/SwiftSeekSmokeTest/main.swift` 新增 round 3 smoke，明确验证 `*|foo` 不再退化成只返回 foo 命中，`*|?` 也不再返回空集。
- J3 round 1 的纯 OR bounded-window 回归 smoke、J3 round 3 的 wildcard-in-OR smoke、以及既有 wildcard / phrase / NOT / 容错 smoke 全部通过。
- `Sources/` 本轮只改了 `SearchEngine.swift` 与 `SwiftSeekSmokeTest/main.swift`，没有碰 J1/J2 行为，也没有改 H2 usage tie-break。
- build 与 smoke 实跑通过：`swift build --disable-sandbox` 成功，`swift run --disable-sandbox SwiftSeekSmokeTest` 为 `186/186`。

## 当前验收要求
J3 已 `PASS`。进入 J4 后，必须补齐搜索历史、Saved Filters 与快速过滤器，但不能把搜索历史和 file usage 混成同一张表，也不能引入云同步或遥测。

J4 验收时必须检查：
- 普通查询执行后写入最近查询历史。
- 重复查询去重并更新时间。
- 可以清空历史，清空后 UI 立即反映。
- 可以保存当前查询为 Saved Filter，并支持删除。
- 入口不干扰普通 typing 搜索性能，文档明确隐私边界。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
