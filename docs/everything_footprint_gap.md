# SwiftSeek Everything-footprint Gap

本文档基于当前代码审计，记录 SwiftSeek 在 500k+ 文件规模下的大库体积、迁移和维护体验差距。它不推翻 `everything-performance` 的搜索性能结论；新问题集中在长期 footprint。

## 1. full-path bigram/trigram 膨胀

### 当前现状
- `Sources/SwiftSeekCore/Schema.swift` schema v4 同时存在：
  - `file_grams(file_id, gram)`
  - `file_bigrams(file_id, gram)`
- `Sources/SwiftSeekCore/Gram.swift` 中：
  - `indexGrams(nameLower:pathLower:) = grams(nameLower) ∪ grams(pathLower)`
  - `indexBigrams(nameLower:pathLower:) = bigrams(nameLower) ∪ bigrams(pathLower)`
- 也就是说，文件名和完整路径都会被滑窗写入 trigram/bigram 表。

### 为什么是问题
完整路径通常远长于 basename。对 500k+ 文件，深目录和重复路径前缀会产生大量 gram 行，即使 `PRIMARY KEY(file_id, gram)` 能去掉同一文件内重复 gram，也不能去掉跨文件重复写入的 `(file_id, gram)` 行。

### 用户影响
- 主 DB 可膨胀到数 GB。
- `file_grams + file_bigrams` 成为主要体积来源。
- 搜索变快，但长期磁盘占用、备份、迁移、维护成本升高。

### 推荐优先级
高

### 建议解决阶段
`G2` 设计 compact index，`G3` 实现 Schema v5 与分批回填，`G4` 暴露索引模式。

## 2. v4 migration 巨型事务风险

### 当前现状
- `Database.migrate()` 对所有 pending migrations 使用单个 `BEGIN IMMEDIATE` / `COMMIT`。
- v2 会调用 `backfillFileGrams()`。
- v4 会调用 `backfillFileBigrams()`。
- 两个 backfill 都执行 `SELECT id, name_lower, path_lower FROM files;`，先把所有行放入 Swift 数组，再逐行写入 gram 表。

### 为什么是问题
大库升级时，v4 bigram 回填可能在一个巨型事务里生成海量写入。WAL 可能暴涨，启动迁移会变慢，失败后回滚成本高，并且全量 rows 数组会带来额外内存压力。

### 用户影响
- 大库首次升级或迁移时 App 启动可能长时间卡住。
- 中途失败后的恢复体验不可控。
- 用户很难判断迁移是在正常执行还是卡死。

### 推荐优先级
高

### 建议解决阶段
`G3`

## 3. 缺少 DB stats / table stats

### 当前现状
- `Database` 只有通用 `countRows(in:)`。
- 设置页 About / Diagnostics 只展示 DB path、schema、roots/excludes/files、隐藏文件开关和上次重建摘要。
- 维护页只展示重建入口和 `last_rebuild_*`。
- CLI `SwiftSeekIndex` 只输出 `roots` 与 `files` 行数。
- `SwiftSeekBench` 只测搜索 timing 和 cache hit。

### 为什么是问题
用户遇到数 GB DB 时，看不到 DB 大在哪里，也看不到 `file_grams`、`file_bigrams`、WAL 或 per-table size。

### 用户影响
- 只能手工打开 sqlite3 排查。
- 无法判断是文件数、路径长度、WAL 未 checkpoint，还是 gram 表策略导致体积异常。

### 推荐优先级
高

### 建议解决阶段
`G1`

## 4. 缺少 checkpoint / VACUUM / optimize 的 App 内维护入口

### 当前现状
- 代码检索未发现 `VACUUM`、`wal_checkpoint`、`PRAGMA optimize`、`dbstat`、`page_count` 或 `page_size` 的产品路径。
- 当前用户需要自己用 sqlite3 执行压实或 checkpoint。

### 为什么是问题
WAL 模式下，长期索引和重建后 WAL 可能增长。VACUUM 可以压实主库，但需要额外空间、可能耗时很长，也要求用户理解风险。

### 用户影响
- 普通用户没有安全维护入口。
- 手工 sqlite3 操作容易在 App 仍运行时执行，带来锁等待、失败或误操作。

### 推荐优先级
高

### 建议解决阶段
`G1`

## 5. 缺少紧凑索引模式

### 当前现状
- 当前索引策略固定：basename 和 full path 都进入 bigram/trigram。
- `SettingsTypes.swift` 没有 index mode / compact mode 设置。
- UI 没有“紧凑模式 / 完整路径子串模式”的选择。

### 为什么是问题
full-path substring 对 `path:` 和任意路径片段查询有帮助，但对大库非常昂贵。500k+ 文件长期使用时，默认把完整路径滑窗写入两张 gram 表不够克制。

### 用户影响
- 用户无法用更小 DB 换取少量路径子串能力下降。
- 也无法只在明确需要时开启完整路径子串高级模式。

### 推荐优先级
高

### 建议解决阶段
`G2` 设计，`G3` 实现，`G4` UI 接线。

## 6. 缺少 root 级索引体积归因

### 当前现状
- roots 表只保存 path/enabled。
- diagnostics 没有按 root 展示 files 数、gram 行数、bigram 行数或估算体积。
- 现有 `files` 表没有显式 root_id，归因只能通过 path prefix 计算。

### 为什么是问题
当 DB 变大时，用户需要知道哪个 root 贡献了主要体积，才能决定移除、排除或重建某个目录。

### 用户影响
- 大库维护只能靠猜。
- 外接盘、开发目录、包管理缓存目录等高体积 root 无法快速定位。

### 推荐优先级
中

### 建议解决阶段
`G1` 提供初步按 path prefix 归因，`G3/G4` 随 schema / mode 设计继续完善。

## 7. benchmark 缺少 footprint 指标

### 当前现状
- `Sources/SwiftSeekBench/main.swift` 是 F1 搜索热路径 probe。
- 它能生成合成文件并统计 warm search median/p95，但没有输出：
  - DB size
  - WAL size
  - grams/bigrams row count
  - avg grams/bigrams per file
  - indexing time 与 DB size 的对照
  - v4 与 compact 模式对比

### 为什么是问题
当前性能轨道证明了“搜得快”，但没有证明“长期库体积可控”。footprint 优化必须用大规模指标验收。

### 用户影响
- 后续 compact index 是否真实降体积无法被 Codex 验收。
- 500k 场景只能靠用户真实库反馈，缺少可重复回归基准。

### 推荐优先级
中

### 建议解决阶段
`G1` 增加 stats probe，`G5` 做 500k benchmark 与最终对比。

## 为什么新轨道叫 `everything-footprint`

`everything-performance` 已经解决“搜索热路径够不够快”的问题。当前用户反馈的核心不再是 search latency，而是索引库在大规模长期使用下的磁盘 footprint、迁移 footprint、维护 footprint。`everything-footprint` 这个名字明确把目标限定在体积、维护、迁移和可观测性，不把新轨道误导成又一轮泛 Everything 功能扩张。
