# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
**VERDICT: PROJECT COMPLETE for everything-footprint track**
TRACK: everything-footprint
STAGE: G5 (final)
ROUND: 3
DATE: 2026-04-24
SESSION_ID: 019dbdf8-b2c9-7c03-b316-dbbf7040d5d9

### Summary
`everything-footprint` 已结案。G1-G5 均通过独立验收：
- G1 round 2 PASS — DB 体积观测 + 维护入口
- G2 round 2 PASS — Schema v5 / compact proposal 冻结合同
- G3 round 2 PASS — Schema v5 + 分流 indexer/search + MigrationCoordinator
- G4 round 2 PASS — 索引模式 UI + 维护页回填按钮
- G5 round 3 PROJECT COMPLETE — 500k 实测 + reopen/migrate 计时 + 最终文档收口

### 500k 实测数据（release，2026-04-24，iters=20）

| 指标 | Compact | Fullpath | 比例 |
|------|---------|----------|------|
| **main DB** | **1.07 GB** | **3.46 GB** | **0.31×（3.2× 更小）** |
| **索引行数总** | 23,024,963 | 118,932,793 | **0.19×（5.2× 更少）** |
| **首次索引时间** | **44.87s** | **197.62s** | **0.23×（4.4× 更快）** |
| **reopen time** | **0.001s** | **0.001s** | 持平 — G3 migrate CREATE-only 证据 |
| **migrate time** | **0.000s** | **0.000s** | 持平（启动时 schema 已最新，无 backfill） |
| warm 2-char median | 2.62ms | 3.22ms | 都 < F1 50ms ✓ |
| warm 2-char p95 | 5.25ms | 6.30ms | 都 < F1 150ms ✓ |
| warm 3+char median | 89.63ms | 95.97ms | ⚠️ 超 F1 30ms（见 bench.md "诚实记录"） |
| warm 3+char p95 | 258.96ms | 397.45ms | ⚠️ 超 F1 100ms；compact 仍快 35% |

### 20k 实测（对照，release，2026-04-24）

| 指标 | Compact | Fullpath | 比例 |
|------|---------|----------|------|
| main DB 文件 | 39.7 MB | 128 MB | **0.31× (3.2× 更小)** |
| 索引行数 | 868,794 | 4,763,509 | **0.18× (5.5× 更少)** |
| 首次索引时间 | 1.42s | 6.77s | **0.21× (4.7× 更快)** |
| warm 2-char median | 2.68ms | 3.24ms | 都 <F1 50ms |
| warm 3+char median | 4.11ms | 3.47ms | 都 <F1 30ms |

20k 和 500k 两个规模下 main DB size 比例都稳定在 0.31×，线性成立。

### 关键确认

1. **用户报告 586k=3.4GB，实测 500k=3.46GB** — 数据模型正确，fullpath v4 体积预测真实。
2. **compact 500k=1.07GB** — 用户如切到 compact 可把 3.4GB 降到 1GB 级别。
3. **reopen/migrate = 0.001s / 0.000s @500k** — G3 migrate CREATE-only 承诺在 500k 规模下得到验证，用户升级 v4→v5 不会遇到"启动卡几分钟"。
4. **compact backfill 由 MigrationCoordinator 后台分批跑**，不阻塞主线程，可中断续跑。

### Codex round 3 verdict（原文摘录）

> VERDICT: PROJECT COMPLETE
> TRACK: everything-footprint
> STAGE: G5
> ROUND: 3
> SUMMARY: round 2 的 3 个文档 blocker 已全部关闭... G5 的核心证据现在完整成立：500k 双模式实测、reopen/migrate 计时、500k 体积/行数/索引耗时/查询中位数与 p95、以及与用户 586k=3.4GB 的现实对照都已落盘... `everything-footprint` 轨道可以结案。
> BLOCKERS: None
> REQUIRED_FIXES: None

### Non-blocking notes（Codex 留存）
1. 500k 下 warm 3+char 已明确超出 F1 在 10k 规模时的旧目标，但文档已诚实记录为"规模效应事实"，而不是本轨道实现回退。不视为 `everything-footprint` 的未完成项。
2. 10× 体积缩小的 G2 粗估在实测中体现为 3-5×（见 bench.md "为什么没达 10×"）；用户真实 500k 库从 3.4GB 降到约 1GB 仍是决定性收益。

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 138 / 0
- `SwiftSeekStartup` → schema=5 + PASS
- `SwiftSeekBench --mode both --files 500000 --iters 20` → 上表实测数据
- `SwiftSeekBench --mode both --files 20000 --iters 30` → 对照实测数据

## 轨道内已通过阶段
- G1（round 2 PASS）
- G2（round 2 PASS）
- G3（round 2 PASS）
- G4（round 2 PASS）
- G5（round 3 PROJECT COMPLETE）

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
