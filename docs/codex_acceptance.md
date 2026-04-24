# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending F2 round 1)
TRACK: everything-performance
STAGE: F2
ROUND: 1 (awaiting Codex)
DATE: 2026-04-24
SESSION_ID: 019dbdb7-8fa3-72b0-9ad0-f389fa6b1a90

### Summary
F2 功能面已落地：
1. `SwiftSeekSearch` CLI 默认 limit 改为读 `settings.search_limit`（fresh DB 默认 100）；`--limit N` 显式覆盖保留；stderr 日志明确标注 limit 来源。
2. Ranking regression matrix：F2 新增 4 条 smoke（5 种典型 `alpha` 命中 exact score；multi-token AND all-in-name +100 vs split-path 的堆叠；CLI default vs DB；setSearchLimit 立即生效）。
3. 文档和代码对齐：known_issues 第 4 节移除"CLI 仍是固定 20"的旧说法。

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 111 / 0（F2 +4 用例全过）
- `SwiftSeekStartup` → schema=4 + startup check PASS

### Blockers / Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- F1 round 1 Codex 备注 environment 限制（SwiftShims module cache / SDK 不匹配），但 PASS 依据文件 + 结构审读 + 本地自检结果。
- F2 未引入新 bonus 维度；只是用测试锁定当前 E1/F1 的得分公式。

## 轨道内已通过阶段
- F1（2026-04-24 round 1 PASS）

## 历史归档轨道
- `v1-baseline`：P0 ~ P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1 ~ E5 / PROJECT COMPLETE 2026-04-24
