# SwiftSeek Track Status

本文件是当前活跃轨道的唯一状态入口。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-footprint`
- 当前阶段：`G2`（纯设计文档，等待 Codex 验收）
- 轨道内已通过：G1（2026-04-24 round 2 PASS）
- 已归档轨道：`v1-baseline`、`everything-alignment`、`everything-performance`
- 当前轨道任务书：`docs/everything_footprint_taskbook.md`
- 当前差距清单：`docs/everything_footprint_gap.md`

## 已归档轨道

### `v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0-P6
- 边界：只代表 v1 基线能力完成。

### `everything-alignment`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-24
- 范围：E1-E5
- 边界：只代表 Everything-like 体验第一轮对齐完成。

### `everything-performance`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-24
- 范围：F1-F5
- 结论：搜索热路径、相关性接线、结果视图、DSL、RootHealth 与索引自动化已完成一轮性能和落地收口。
- 新轨道原因：真实 500k+ 文件使用暴露出新的大库体积、迁移和维护体验问题，`everything-performance` 的完成结论不覆盖 DB footprint。

## 当前活跃轨道：`everything-footprint`

### 当前轨道目标
在不推翻 `everything-performance` 搜索速度成果的前提下，降低大库长期使用成本，让 SwiftSeek 在 500k+ 文件规模下具备成熟工具应有的：
- DB 体积可观测性
- WAL / checkpoint / VACUUM / optimize 的安全维护入口
- 可配置的紧凑索引策略
- 可恢复、可分批、可失败续跑的迁移路径
- 500k 级别 benchmark 证据

### 代码优先审计结论
- `Sources/SwiftSeekCore/Schema.swift` 当前 schema 为 v4，同时存在 `file_grams` 和 `file_bigrams`。
- `Sources/SwiftSeekCore/Gram.swift` 的 `indexGrams(nameLower:pathLower:)` 与 `indexBigrams(nameLower:pathLower:)` 都对文件名和完整路径做滑窗 union。
- `Sources/SwiftSeekCore/Database.swift` 的 v2 gram backfill 与 v4 bigram backfill 都在 `migrate()` 的单个 `BEGIN IMMEDIATE` 事务里执行，并先把 `files` 全量读入内存。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 的维护页目前只提供重建索引和上次重建摘要，不展示 DB/WAL/table 体积，也没有 checkpoint / optimize / VACUUM 入口。
- `Sources/SwiftSeekBench/main.swift` 目前是 F1 搜索热路径 benchmark，不统计 DB size、WAL size、gram row count 或 500k footprint。
- `Sources/SwiftSeekIndex/main.swift` 只输出 roots/files 行数，不提供 DB stats 或维护命令。

## 已通过：`G1`（2026-04-24 round 2 PASS）
- DB stats API in Core (`DatabaseStats` + `Database.computeStats()`)
- `SwiftSeekDBStats` CLI target（含 `--run checkpoint/optimize/vacuum` + `--yes` + 风险横幅）
- Settings 维护页 DB 体积 block + 4 maintenance buttons + VACUUM 确认弹窗
- Smoke +7 → 126/126
- manual_test §33f

## 当前阶段：`G2` - 紧凑索引策略设计

### Round 1 REJECT（2026-04-24）
- blocker 1：compact path 语义未冻结（"取决于实现"留给 G3 的自由度过大）
- blocker 2：rebuild plan 不够成形（mode 切换触发条件、目标表、migration_progress 生命周期、越界边界都缺）

### Round 2（当前提交）
- ✅ 冻结 compact path 语义：plain query 只命中 basename；`path:<token>` 走 segment **前缀**匹配；4 正例 + 4 反例
- ✅ 扩完整 rebuild/rollback plan：触发场景 / 响应矩阵、rebuild 目标表规则、migration_progress 生命周期、越界 / 符合设计行为清单
- ✅ 文档与 G3 实现之间的合同完全对齐

### 当前阶段禁止事项
- 不直接实现 Schema v5（G3）
- 不删除 v4 `file_grams` / `file_bigrams`
- 不改用户现有库
- 不做 UI 切换（G4）
- 不给最终 benchmark 数字（G5）

### 代码状态（G2 快照）
- 零代码改动
- 新增 `docs/everything_footprint_v5_proposal.md`（round 2 扩到 § 5.1 硬定义 + § 6.4 完整 rebuild plan + § 6.5 向前兼容）
- stage_status.md 本段

### 完成判定
1. ✅ 文档明确 compact mode vs full-path substring mode 的能力差异（§ 5.1 矩阵 + 8 正反例）
2. ✅ 文档明确 v4 到 v5 的数据迁移策略（§ 6.1 + 6.2）
3. ✅ 文档明确失败恢复、回滚和重建策略（§ 6.4 矩阵 + 生命周期 + 越界清单）
4. ✅ 文档明确 500k benchmark 目标（§ 8）
5. ✅ Codex 可据此判断 G3 是否越界（§ 6.4 "越界 / 符合设计" 双清单）

---

### 原 G1 阶段快照（归档保留）

### 当前阶段目标
先让用户知道 DB 到底大在哪里，并提供安全、可解释的维护入口。本阶段只做观测和维护入口，不改 schema，不改变索引语义。

### 当前阶段必须做
- 新增 DB stats 能力，至少统计：
  - DB file size
  - WAL size
  - `PRAGMA page_count`
  - `PRAGMA page_size`
  - `files` row count
  - `file_grams` row count
  - `file_bigrams` row count
  - avg grams per file
  - avg bigrams per file
- 如 SQLite 支持 `dbstat`，优先展示 per-table size；不支持时 fallback 到 row count + page info。
- 新增 CLI 或 bench 子命令，例如 `SwiftSeekDBStats` 或 `SwiftSeekBench --db-stats`。
- 设置 / 维护页显示简版 DB stats，至少让用户看见 DB 大小、WAL 大小、files/grams/bigrams 行数。
- 增加 checkpoint / optimize / VACUUM 的安全入口。
- VACUUM 前必须提示：
  - 退出其他 SwiftSeek 进程
  - 需要额外临时空间
  - 可能耗时较长

### 当前阶段禁止事项
- 不引入 Schema v5。
- 不删除或改写 `file_grams` / `file_bigrams` 的现有语义。
- 不实现 compact index。
- 不修改搜索 ranking、DSL、结果视图、热键等非 footprint 范围。
- 不把 VACUUM 伪装成根治方案，必须标注它只能临时压实当前库。
- 不在 app 启动时做大规模维护或不可控长事务。

### 当前阶段完成判定标准
1. 用户可以通过 CLI 或 bench 命令读取当前 DB footprint 指标。
2. 设置 / 维护页能显示简版 DB stats，且读取失败时不影响主 App 使用。
3. checkpoint / optimize / VACUUM 入口存在，并有清晰风险提示。
4. `dbstat` 不可用时有稳定 fallback。
5. 文档写明 G1 只是观测和维护入口，不解决根本体积膨胀。
6. `swift build` 与相关 smoke / 新增测试通过。

## 当前最新 Codex 结论
- `everything-footprint / G1 / REJECT round 1`（2026-04-24）
- `everything-footprint / G1 / PASS round 2`（2026-04-24，session 019dbdf8-b2c9-7c03-b316-dbbf7040d5d9）
- `everything-footprint / G2`：功能面已落地（纯设计 doc），等待 round 1 验收

## 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 当前 session id：`019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`（round 1 建立）
- 恢复策略：`codex exec resume <session_id>`
- 不得再混用已归档 `everything-performance` 的 session。
