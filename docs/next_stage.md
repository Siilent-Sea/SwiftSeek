# 下一阶段任务书

## 当前状态
- 当前活跃轨道：`everything-footprint`
- 当前阶段：`G1`
- 阶段名称：DB 体积观测与维护入口

`v1-baseline`、`everything-alignment`、`everything-performance` 都已归档。`everything-performance` 的 `PROJECT COMPLETE` 不覆盖当前大库体积、迁移和维护体验问题。

## 给 Claude 的 G1 执行任务

### 阶段目标
让用户能看清 SwiftSeek DB 到底大在哪里，并提供安全维护入口。本阶段只做观测和维护，不改索引 schema。

### 必须实现
1. 新增 DB stats 能力，至少输出：
   - DB file size
   - WAL size
   - `PRAGMA page_count`
   - `PRAGMA page_size`
   - `files` count
   - `file_grams` count
   - `file_bigrams` count
   - avg grams per file
   - avg bigrams per file
2. 如 SQLite 支持 `dbstat`，优先展示 per-table size；不支持时 fallback 到 row count + page info。
3. 新增 CLI 或 bench 子命令，例如：
   - `SwiftSeekDBStats`
   - 或 `SwiftSeekBench --db-stats`
4. 设置 / 维护页展示简版 DB stats，并支持手动刷新。
5. 增加 checkpoint / optimize / VACUUM 安全入口。
6. VACUUM 必须二次确认，并明确提示：
   - 退出其他 SwiftSeek 进程
   - 需要额外临时空间
   - 可能耗时较长

### 明确不做
- 不做 Schema v5。
- 不改 `file_grams` / `file_bigrams` 结构。
- 不实现 compact index。
- 不改变搜索语义、ranking、DSL、结果视图、热键。
- 不让 App 启动时自动执行 VACUUM 或大规模维护。
- 不把 VACUUM 写成根治 DB 膨胀的方案。

### 关键文件
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekBench/main.swift` 或新增 CLI target
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `Package.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. CLI / bench 能对指定 DB 输出完整 stats。
2. 设置 / 维护页能显示简版 stats，读取失败不影响 App 使用。
3. checkpoint / optimize / VACUUM 入口可用，失败有错误展示。
4. VACUUM 风险提示清晰，并有二次确认。
5. `dbstat` 不可用时 fallback 稳定。
6. 文档明确 G1 只是观测和维护入口，不解决根本体积膨胀。
7. `swift build` 与 `swift run SwiftSeekSmokeTest` 通过。

### 必须补的测试 / 手测
- fresh DB stats。
- 空表 / 缺表 fallback。
- `file_grams` / `file_bigrams` count 与 avg 计算。
- WAL size 字段可读。
- 设置页维护区 stats 手测。
- VACUUM 二次确认文案手测。

## Codex 验收提示
G1 完成后调用 Codex 时必须使用 `everything-footprint` 当前轨道的新验收 session，不得混用已归档 `everything-performance` session。
