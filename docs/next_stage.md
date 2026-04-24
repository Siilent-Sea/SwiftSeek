# 下一阶段任务书（过渡 G2 → G3）

## Track
`everything-footprint`

## Stage
G2 当前刚落地（纯设计文档，等待 Codex 验收）。本文件是 G2 → G3 的过渡骨架。

## G3 目标（预告）
按 `docs/everything_footprint_v5_proposal.md` 真实实现 compact index schema v5 + 分批 backfill，**不在启动主线程做大事务**。

### 必须做
- Schema v5：`file_name_grams` / `file_name_bigrams` / `file_path_segments` / `migration_progress`
- `Database.migrate()` v4→v5 只 CREATE，不 backfill
- `settings.index_mode`：新 DB 默认 `compact`，v4 升级默认 `fullpath`（保留现有能力）
- `MigrationCoordinator` 分批回填（每批 ~5000 行，每批独立事务 + checkpoint）
- `migration_progress` 可恢复断点 / 支持失败后继续
- Indexer 根据 `index_mode` 写对应表
- SearchEngine candidates 按 mode 分流
- 单元测试覆盖：fresh DB v5 / v4 升级不做大事务 / 分批 backfill 可中断续跑 / mode 切换行为

### 明确不做
- 不做 UI 切换（G4）
- 不删除 v4 `file_grams` / `file_bigrams`
- 不强制一次性重建
- 不要求用户手工 sqlite3 修库

### 关键文件
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/Gram.swift`
- `Sources/SwiftSeekCore/Indexer.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- 新 `Sources/SwiftSeekCore/MigrationCoordinator.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/architecture.md`
- `docs/manual_test.md`

---

## 过渡期说明
G2 round 1 验收完成后本文件需刷新：
1. 若 G2 PASS，正文展开为完整 G3 任务书
2. 若 G2 REJECT，维持 G2 状态按 Codex required fix 修后重验
