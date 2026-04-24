# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J3`
- 当前阶段验收结论：`J3 REJECT`
- 当前正式验收 session：`019dc07b-55f0-7712-9d7f-74441d7c81df`
- 日期：2026-04-25

### 当前审计结论
`83d6026` 仍不能通过 J3 验收。上一轮“纯 OR 落到 bounded fallback”的主 blocker 已修掉，但 OR 中包含纯 wildcard alt 的语义仍不成立。

本轮实际确认：
- `search()` 现在在 `requireAnchors` 为空但 `orGroups` 非空时，确实会走 `orUnionCandidates()`，上一轮“纯 OR bounded fallback”问题已被修掉。
- 新增 smoke 也覆盖了“大于 bounded window 的纯 OR 命中”场景，`184/184` 全绿。
- 但 `orUnionCandidates()` 明确把纯 wildcard alt（如 `*` / `?`）直接跳过，只依赖其他 alt 驱动候选检索；如果 query 是 `*|foo`，最终只会返回 `foo` 候选，不会返回 `*` 本该覆盖的其它结果。
- 当一个 OR group 全部由纯 wildcard alt 组成（如 `*|?`）时，`orUnionCandidates()` 会返回空集，post-filter 根本没有行可评估，语义直接失真。
- 这与当前文档“wildcard 可在 OR 中使用”的写法冲突，因此 J3 仍不能放行。

## 当前验收要求
J3 当前仍未通过。修复后必须重新验收，重点是把纯 `OR` 查询接到“完整但可控”的候选检索路径，而不是 bounded fallback。

J3 验收时必须检查：
- `*` / `?` wildcard、quoted phrase、OR、NOT 的语义清晰且与现有 `ext:` / `path:` / `recent:` / `frequent:` 可组合。
- 非法语法不崩溃，能容错为字面量或空结果。
- GUI 与 CLI 查询语义一致。
- build / smoke 仍通过；复杂语法不能把热路径明显拖垮。
- 纯 `OR` 查询在真实库里结果完整，不会因为候选池截断而漏命中。
- wildcard 出现在 OR alt 时语义仍成立；`*|foo` 不能退化成仅 `foo`。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`

## 轨道切换说明
`everything-ux-parity` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
