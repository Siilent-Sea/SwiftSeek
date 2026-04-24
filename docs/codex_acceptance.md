# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J3`
- 当前阶段验收结论：`J3 REJECT`
- 当前正式验收 session：`019dc07b-55f0-7712-9d7f-74441d7c81df`
- 日期：2026-04-25

### 当前审计结论
`c12db20` 不能通过 J3 验收。自动化 build / smoke 都通过，但纯 `OR` 查询的候选检索路径不完整，在真实库里会漏结果。

本轮实际确认：
- `parseQuery()` 确实把 `alpha|beta` 解析成 `orGroups`，没有误落到 AND token。
- 但 `search()` 明确不把 `orGroups` 纳入 `requireAnchors`；纯 `OR` 查询在没有 plain token / phrase token 时直接走 `filterOnlyCandidates()` fallback。
- `filterOnlyCandidates()` 的 fallback 是 `SELECT ... FROM files LIMIT ?` 的 bounded scan，不是完整 union 候选集；所以 `alpha|beta` 这类纯 OR 查询在真实库里只会在前 `candidatePool` 条记录里找命中，结果不完整。
- 现有 J3 smoke 的 OR 用例只在 5 个文件的微型 fixture 上验证，没覆盖“大于 LIMIT / 超出前 candidatePool 记录”的真实场景，所以没有抓住这个问题。
- build 与 smoke 本身无回归：`swift build --disable-sandbox` 通过，`swift run --disable-sandbox SwiftSeekSmokeTest` 为 `183/183`。

## 当前验收要求
J3 当前仍未通过。修复后必须重新验收，重点是把纯 `OR` 查询接到“完整但可控”的候选检索路径，而不是 bounded fallback。

J3 验收时必须检查：
- `*` / `?` wildcard、quoted phrase、OR、NOT 的语义清晰且与现有 `ext:` / `path:` / `recent:` / `frequent:` 可组合。
- 非法语法不崩溃，能容错为字面量或空结果。
- GUI 与 CLI 查询语义一致。
- build / smoke 仍通过；复杂语法不能把热路径明显拖垮。
- 纯 `OR` 查询在真实库里结果完整，不会因为候选池截断而漏命中。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
