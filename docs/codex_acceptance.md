# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending G5 final / PROJECT COMPLETE)
TRACK: everything-footprint
STAGE: G5 (final)
ROUND: 1 (awaiting Codex)
DATE: 2026-04-24
SESSION_ID: 019dbdf8-b2c9-7c03-b316-dbbf7040d5d9

### Summary
G5 是 `everything-footprint` 最终阶段。G1-G4 已通过独立验收：
- G1 — DB 体积观测 + 维护入口（round 2 PASS）
- G2 — Schema v5 / compact proposal + 冻结合同（round 2 PASS）
- G3 — Schema v5 + 分流 indexer/searchEngine + MigrationCoordinator（round 2 PASS）
- G4 — 索引模式 UI + 维护页回填按钮（round 2 PASS）

G5 新改动：
- `SwiftSeekBench` 扩展：`--mode {compact,fullpath,both}`，对比报告，checkpoint 后读 stats
- 新 `docs/everything_footprint_bench.md`：20k 实测 + 500k 投影 + F1 目标回归
- README / known_issues / manual_test / stage_status 最终对齐

### 实测数据（20k 文件，release，2026-04-24）
| 指标 | Compact | Fullpath | 比例 |
|------|---------|----------|------|
| main DB 文件 | 39.7 MB | 128 MB | **0.31× (3.2× 更小)** |
| 索引行数 | 868,794 | 4,763,509 | **0.18× (5.5× 更少)** |
| 首次索引时间 | 1.42s | 6.77s | **0.21× (4.7× 更快)** |
| warm 2-char median | 2.68ms | 3.24ms | 都 <F1 50ms |
| warm 3+char median | 4.11ms | 3.47ms | 都 <F1 30ms |

500k 投影：compact ~1.0 GB vs fullpath ~3.2 GB（与用户实际 586k=3.4GB 吻合）。

### 请求颁发
如 G5 满足任务书要求且 G1-G4 不回退，请颁发 `VERDICT: PROJECT COMPLETE for everything-footprint track`。

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 138 / 0（G5 未添新 smoke；benchmark 自己作为 acceptance 证据）
- `SwiftSeekStartup` → schema=5 + PASS
- `SwiftSeekBench --mode both --files 20000 --iters 30` → 实测数据如上

### Blockers / Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- 10× 体积缩小的 G2 粗估在实测中体现为 3-5×（见 bench.md "未达目标原因"）。合成 fixture 的 basename 比现实长，导致 compact 相对优势略被低估；用户 500k 库从 3.4GB 降到约 1GB 仍是决定性收益。
- compact 的 3+char p95 = 13.92ms 比 fullpath 的 3.76ms 稍高，但仍远在 F1 100ms 目标内。`path:` segment 前缀 JOIN 天然比 gram IN 慢一些；大多数场景不落 p95。

## 轨道内已通过阶段
- G1（round 2 PASS）
- G2（round 2 PASS）
- G3（round 2 PASS）
- G4（round 2 PASS）

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
