# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending G3 round 1)
TRACK: everything-footprint
STAGE: G3
ROUND: 1
DATE: 2026-04-24
SESSION_ID: 019dbdf8-b2c9-7c03-b316-dbbf7040d5d9

### Summary
G3 按 G2 proposal 冻结合同真实实现 Schema v5 + compact index 双写路径 + MigrationCoordinator 分批回填。

**Schema**
- `Schema.currentVersion = 5`；migration target 5 CREATE-only：`file_name_grams` / `file_name_bigrams` / `file_path_segments` / `migration_progress`
- `Database.migrate()` v5 分支 seeds `settings.index_mode`：新 DB `compact`，升级 DB `fullpath`（保留能力）
- **不跑 backfill 在 migrate() 内**

**Gram.swift**
- 新 `nameGrams(nameLower:)` / `nameBigrams(nameLower:)`（basename-only）
- 新 `pathSegments(pathLower:)`（按 `/` 切，去空）

**Database.insertFiles**
- 读 `indexMode` 一次
- fullpath mode：继续写 `file_grams` + `file_bigrams`（pre-G3 行为不变）
- compact mode：写 `file_name_grams` + `file_name_bigrams` + `file_path_segments`
- 不双写

**SearchEngine**
- 每次 search 读 `indexMode`（F1 cache）
- `candidates` / `filterOnlyCandidates` / `bigramCandidates` / `gramCandidates` / `likeCandidates` 都 mode-aware
- 新 `pathSegmentCandidates` 走 `file_path_segments` 做 segment-prefix 匹配
- fullpath mode：post-filter plain token 允许 name OR path（pre-G3 行为）
- compact mode：post-filter plain token 只认 name；path: token 走 segment 前缀（Gram.pathSegments）
- `matches(...)` 公 API 加 `mode: IndexMode = .fullpath` 默认参数，保持 backward compat

**MigrationCoordinator**（新 file）
- 后台线程 + 小事务分批（默认 batchSize = 5000）+ 每批 `wal_checkpoint(PASSIVE)`
- 写 `migration_progress.compact_backfill_last_file_id` 支持 resume
- `resume: false` 重置 resume 点
- State machine：idle / running；并发调用返回 false

**Smoke**
- 4 个 P2/F1/F2/G1 fixture 加 `setIndexMode(.fullpath)` 保留 v4 regression 语义
- +7 新 G3 用例：
  - schema v5 fresh DB 有所有新表
  - index_mode 默认值（fresh=compact / v4 升级=fullpath）
  - compact indexer 正确写入
  - compact search 语义（proposal §5.1 正反例）
  - path:-token segment-prefix 匹配
  - MigrationCoordinator 分批 backfill + 进度回调 + compact search 可用
  - migration_progress.last_file_id 持久化
- 总 133 pass / 0 fail

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 133 / 0
- `SwiftSeekStartup --db /tmp/ss-g3.sqlite3` → schema=5 + PASS

### Blockers / Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- UI（设置页 mode 切换、"开始回填"按钮、进度条）留给 G4。当前 G3 只做 Core + CLI 可用。
- 500k benchmark 最终数字留给 G5。
- 未删除 v4 `file_grams` / `file_bigrams`；保留作为 rollback 目标。

## 轨道内已通过阶段
- G1（2026-04-24 round 2 PASS）
- G2（2026-04-24 round 2 PASS）

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
