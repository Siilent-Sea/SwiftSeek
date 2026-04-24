# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending F4 round 1)
TRACK: everything-performance
STAGE: F4
ROUND: 1 (awaiting Codex)
DATE: 2026-04-24
SESSION_ID: 019dbdb7-8fa3-72b0-9ad0-f389fa6b1a90

### Summary
F4 功能面已落地：
1. `filterOnlyCandidates` 6 级优先级重排：`path:` ≥3 走 file_grams，`path:` ==2 走 file_bigrams，`ext:` trailing-wildcard LIKE，`root:` prefix LIKE，`kind:` is_dir=?，最后 bounded scan。消除 F1 gap 文档里提到的"path-only 落 bounded scan"低效路径。
2. 0 结果空态提示：新 `degradedRootsHint()` 聚合所有 offline / unavailable / paused root，空态文案带上"（root 状态 · 未挂载：X · 不可访问：Y · 已停用：Z）"尾注。把 RootHealth 从设置页 badge 推到搜索主路径。
3. 文档：`known_issues.md` 第 7 节重写为完整 DSL 支持/不支持清单；第 5 节 root 状态扩大描述覆盖搜索窗口。
4. smoke +3：path-only filter 命中正确集合、path+ext 组合、computeRootHealth 对 mixed roots 正确分类。

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 118 / 0
- `SwiftSeekStartup` → schema=4 + startup check PASS

### Blockers / Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- 未改 SearchEngine 的 parseQuery 支持范围；此轮是候选检索路径改进 + UI 可解释性，不是 DSL 语法扩张。
- `hidden:` 单独使用仍走 bounded scan（罕见且不可索引的 predicate，保留兜底）。

## 轨道内已通过阶段
- F1（2026-04-24 round 1 PASS）
- F2（2026-04-24 round 2 PASS）
- F3（2026-04-24 round 2 PASS）

## 历史归档轨道
- `v1-baseline`：P0 ~ P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1 ~ E5 / PROJECT COMPLETE 2026-04-24
