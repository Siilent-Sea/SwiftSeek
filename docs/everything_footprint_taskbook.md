# SwiftSeek Everything-footprint 任务书

目标：在保留 `everything-performance` 搜索速度成果的前提下，把 SwiftSeek 的大库体积、迁移和维护体验推进到 500k+ 文件长期可用的水平。

硬约束：
- 当前轨道固定为 `everything-footprint`
- 阶段固定为 `G1` 到 `G5`
- 不做全文搜索、OCR、AI 语义搜索、云盘一致性、跨平台或 Electron/Web UI
- 每次只做当前阶段，不允许提前实现后续阶段

---

## G1：DB 体积观测与维护入口

### 阶段目标
先让用户知道 DB 到底大在哪里，并提供安全维护入口。本阶段不改变索引 schema。

### 明确做什么
- 新增 DB stats 能力，至少统计：
  - DB file size
  - WAL size
  - `PRAGMA page_count`
  - `PRAGMA page_size`
  - `files` count
  - `file_grams` count
  - `file_bigrams` count
  - avg grams per file
  - avg bigrams per file
- 如 SQLite 支持 `dbstat`，优先展示 per-table size；不支持则 fallback 到 row count + page info。
- 新增 CLI 或 bench 子命令，例如 `SwiftSeekDBStats` 或 `SwiftSeekBench --db-stats`。
- 设置 / 维护页显示简版 DB stats。
- 增加 checkpoint / optimize / VACUUM 的安全入口。
- VACUUM 必须提示：
  - 退出其他 SwiftSeek 进程
  - 需要额外临时空间
  - 可能耗时较长

### 明确不做什么
- 不改 Schema v4。
- 不创建 Schema v5。
- 不改变 `file_grams` / `file_bigrams` 写入策略。
- 不实现 compact index。
- 不改搜索 ranking、DSL、结果视图或热键。
- 不把 VACUUM 写成根治 DB 膨胀的方案。

### 涉及关键文件
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekBench/main.swift` 或新增 CLI target
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `Package.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. CLI 或 bench 命令能对指定 DB 输出完整 stats。
2. 设置 / 维护页能显示简版 stats，并能手动刷新。
3. stats 读取失败不会影响 App 搜索和设置页打开。
4. checkpoint / optimize / VACUUM 能从维护入口触发，失败有错误展示。
5. VACUUM 前有明确风险提示和二次确认。
6. 文档说明 G1 只是观测和维护入口，不解决根本索引膨胀。
7. `swift build` 与 `swift run SwiftSeekSmokeTest` 通过。

### 必须补的测试 / benchmark / 手测
- smoke：fresh DB stats 不崩，缺表 / 空表 fallback 正常。
- smoke：`file_grams` / `file_bigrams` row count 与 avg 计算正确。
- smoke 或 CLI fixture：WAL size 字段存在且可读。
- 手测：设置页维护区展示 DB stats。
- 手测：VACUUM 二次确认文案包含退出其他进程、临时空间、耗时提示。

---

## G2：紧凑索引策略设计

### 阶段目标
先设计 compact index 策略和兼容路径，不直接盲改 schema。

### 明确做什么
- 输出 schema proposal。
- 输出 search semantics proposal。
- 输出 migration plan。
- 输出 rollback / rebuild plan。
- 输出 benchmark target。
- 评估候选方向：
  - 默认只对 basename 建立 bigram / trigram。
  - 路径只建 segment/token index，而不是完整路径滑窗。
  - `path:` 查询优先走 path segment / prefix / root 限定。
  - full-path substring index 做成可选高级模式。
  - 保留现有行为兼容策略。

### 明确不做什么
- 不直接实现 Schema v5。
- 不删除 v4 表。
- 不改变现有用户库。
- 不做 UI 切换。

### 涉及关键文件
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/Gram.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `docs/architecture.md`
- `docs/everything_footprint_gap.md`
- `docs/everything_footprint_taskbook.md`

### 验收标准
1. 文档明确 compact mode 与 full-path substring mode 的能力差异。
2. 文档明确 v4 到 v5 的数据迁移策略。
3. 文档明确失败恢复、回滚和重建策略。
4. 文档明确 500k benchmark 目标。
5. Codex 可以据此判断 G3 是否越界。

### 必须补的测试 / benchmark / 手测
- 本阶段以设计文档为主。
- 需要新增 proposal 中的验收矩阵，包括体积、搜索语义、迁移恢复、回滚。

---

## G3：Schema v5 与分批回填

### 阶段目标
真实实现 compact index schema，并避免巨型事务。

### 明确做什么
- 引入 Schema v5。
- 新增 compact index 表或等价结构。
- 实现分批 backfill。
- batch 之间做 checkpoint 或等价 WAL 控制。
- 增加可恢复进度表或 meta state。
- 不在 app 启动时做不可控长事务。
- 明确老 v4 数据库升级路径。
- 支持失败后继续。

### 明确不做什么
- 不做索引模式 UI。
- 不删除用户数据。
- 不要求用户手工 sqlite3 修库。
- 不把所有历史库强制一次性重建。

### 涉及关键文件
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/Gram.swift`
- `Sources/SwiftSeekCore/Indexer.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/architecture.md`
- `docs/manual_test.md`

### 验收标准
1. fresh DB 可创建 v5 schema。
2. v4 DB 可升级到 v5，且不会在单个巨型事务内完成全部 backfill。
3. backfill 失败后可以继续。
4. checkpoint / WAL 控制路径可观测。
5. compact index 下常见查询仍可用。
6. 旧 v4 行为兼容策略清楚。
7. `swift build`、smoke 和新增 migration tests 通过。

### 必须补的测试 / benchmark / 手测
- v4 到 v5 migration fixture。
- 中断 / 失败后继续的 backfill test。
- batch size 与 checkpoint 行为测试。
- compact index 查询语义回归测试。
- 手测：大库升级时 UI/CLI 不表现为无提示卡死。

---

## G4：索引模式 UI 与重建流程

### 阶段目标
让用户能选择索引模式，并理解体积/能力差异。

### 明确做什么
- 支持 Compact 默认模式。
- 支持 Full path substring 高级模式。
- 显示各模式的体积 / 能力差异。
- 切换后引导重建。
- 维护页可触发 compact rebuild。
- 文档说明不同模式下的查询能力差异。

### 明确不做什么
- 不再重做底层 schema 设计。
- 不做无提示自动删除索引数据。
- 不做与 footprint 无关的 UI 重写。

### 涉及关键文件
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/RebuildCoordinator.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`
- `README.md`

### 验收标准
1. 设置页能选择索引模式。
2. 模式切换不会静默破坏现有搜索结果，必须引导重建或明确状态。
3. Compact 是默认推荐模式。
4. Full path substring 明确标注体积成本。
5. 搜索行为与当前模式一致。
6. 文档与 UI 文案一致。

### 必须补的测试 / benchmark / 手测
- settings round-trip：index mode 持久化。
- rebuild flow：切换模式后提示与重建链路。
- search regression：compact / full 模式下查询语义差异可预期。
- 手测：用户能从 UI 理解模式差异。

---

## G5：500k 规模 benchmark 与最终收口

### 阶段目标
用大规模数据证明 `everything-footprint` 轨道有效，并准备最终验收。

### 明确做什么
- 增加 synthetic 500k benchmark 或可配置规模 benchmark。
- 指标至少包括：
  - DB size
  - WAL size
  - grams/bigrams row count
  - indexing time
  - warm search median/p95
  - startup/migrate time
- 对比旧 v4 与新 compact 模式。
- 收口 docs / manual_test / known_issues。
- 给 Codex 足够证据判断 `PROJECT COMPLETE`。

### 明确不做什么
- 不为了 benchmark 引入真实用户路径扫描。
- 不做新的搜索产品功能。
- 不扩大到全文内容搜索或 AI 语义搜索。

### 涉及关键文件
- `Sources/SwiftSeekBench/main.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `README.md`

### 验收标准
1. benchmark 能在可配置文件数下生成可重复数据。
2. 500k 或等价规模的指标能输出 DB size、WAL size、row count、indexing time、warm search median/p95、startup/migrate time。
3. 有 v4 / compact 对比数据。
4. 文档清楚说明 compact 模式收益和 tradeoff。
5. 当前轨道没有遗留 blocker。

### 必须补的测试 / benchmark / 手测
- benchmark 参数解析和输出格式测试。
- compact vs full 模式对比报告。
- 手测：真实或合成大库 stats 可读，维护入口可用。
- 最终回归：build、smoke、bench、manual_test 全部对齐。
