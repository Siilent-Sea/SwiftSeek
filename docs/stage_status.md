# SwiftSeek Track Status

## 轨道总览
- 当前活跃轨道：`everything-performance`
- 当前阶段：`F3`（功能落地，等待 Codex 验收）
- 轨道内已通过：F1（round 1 PASS）、F2（round 2 PASS），均 2026-04-24，session 019dbdb7-8fa3-72b0-9ad0-f389fa6b1a90
- 已归档轨道：`v1-baseline`（P0~P6 / PROJECT COMPLETE 2026-04-23）
- 已归档轨道：`everything-alignment`（E1~E5 / PROJECT COMPLETE 2026-04-24）

## 已归档轨道：`v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0 ~ P6

## 已归档轨道：`everything-alignment`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-24
- 范围：E1 ~ E5

## 当前活跃轨道：`everything-performance`

### 已通过：`F1`（搜索热路径性能，2026-04-24 round 1 PASS）
- Schema v4 新 `file_bigrams` 表
- SearchEngine 2-char 走 bigram 倒排；trigram 路径不变；1-char LIKE fallback
- SearchEngine prepared statement cache
- Database roots / settings cache + 写入 invalidate
- SwiftSeekBench 新 target（`--enforce-targets` 达标）
- Smoke +9 F1 用例，总计 107/107

### 当前轨道目标
- 先解决"建了索引但搜索仍慢"的核心问题
- 把当前已经部分落地的 Everything-like 功能按代码真实状态校正
- 性能 / 真实相关性 / 结果视图 / DSL / root 健康 / 索引自动化 按可验证顺序推进

### 当前阶段：`F3`（高密度结果视图与排序入口）

#### 当前阶段目标（全部已落地，等待 Codex 验收）
- ✅ 结果视图列布局保留：用户调整列宽后持久化，重启恢复
- ✅ 排序状态保留：用户点击列头切换后持久化，重启恢复到上次选择
- ✅ 非法 / 缺失持久值 fallback 到默认（scoreDescending / 程序默认列宽），不崩不乱
- ✅ 现有键盘流 / QuickLook / 右键 / 拖拽 / substring 高亮不回退（E2+UX polish 全部保留）

#### 当前阶段禁止事项
- 不做 DSL 扩张（F4）
- 不做新搜索后端
- 不做根本的键盘流重做

#### 代码状态（F3 快照）
- `Sources/SwiftSeekCore/SettingsTypes.swift`
  - 新 SettingsKey：`resultSortKey` / `resultSortAscending` / `resultColumnWidth{Name,Path,Mtime,Size}`
  - Database 扩展：`getResultSortOrder()` / `setResultSortOrder(_:)` / `getResultColumnWidth(key:)` / `setResultColumnWidth(key:width:)`
  - malformed row 自动 fallback
- `Sources/SwiftSeek/UI/SearchViewController.swift`
  - `columnResizeObserver` 订阅 `NSTableView.columnDidResizeNotification`，改变时按 column identifier 持久化到对应 settings key
  - loadView 用 `persistedWidth(for:)` 为每列选择初始宽度（miss 回退到程序默认）
  - loadView 用 `database.getResultSortOrder()` 恢复上次 sortOrder + AppKit `sortDescriptors`
  - `sortDescriptorsDidChange` 除了更新 UI，也 `database.setResultSortOrder` 持久化
  - deinit 清理 NotificationCenter observer
- `Sources/SwiftSeekSmokeTest/main.swift`
  - F3 +4 用例（fresh sort = scoreDescending / 每个 SortKey round-trip / malformed fallback / 每个 column width round-trip）
  - 总数 111 + 4 = 115 全绿

#### 完成判定
1. ✅ 结果视图密度不回退（沿用 E2 的 4 列 + 窄行高 22）
2. ✅ 主要字段一眼可扫（name / path / mtime / size 四列齐全）
3. ✅ 排序方式切换可用且持久化（score / name / path / mtime / size × 升降）
4. ✅ 键盘流、QuickLook、右键、拖拽不回退
5. ✅ `swift build` + smoke 全绿（115/115）

---

### 原 F2 阶段快照（归档保留）
- CLI default limit 接 DB，ranking regression matrix 锁定
- 文档一致性

### 原 F1 阶段快照（归档保留）

#### 当前阶段目标（全部已落地，等待 Codex 验收）
- ✅ 2 字符查询不再走 `%LIKE%` 全表扫描主路径 → Schema v4 新增 `file_bigrams` 表；`SearchEngine.bigramCandidates` 走倒排索引
- ✅ 3+ 字符查询继续保持索引驱动（trigram + HAVING count 不变）
- ✅ 1 字符 fallback 保留 LIKE，但明确不是主路径（只有纯 1-char query 才走）
- ✅ SearchEngine 加 prepared statement cache（key by SQL，NSLock 保护）
- ✅ Database 加 roots cache + settings cache，写入路径自动 invalidate
- ✅ 新 SwiftSeekBench executable target：warm 2-char / 3+char / 多词 timing 采样 + median/p95 + cache hit stats
- ✅ `docs/everything_performance_taskbook.md` 固化性能目标

#### 当前阶段禁止事项
- 不做结果视图重设计（F3）
- 不做相关性大改版（F2）
- 不做 DSL 扩张（F4）
- 不做热键 / root UI / 自动索引额外功能开发（F4/F5）

#### 当前代码状态（F1 快照）
- `Sources/SwiftSeekCore/Schema.swift`
  - currentVersion = 4
  - Migration(target:4) 创建 `file_bigrams` + `idx_file_bigrams_gram`
- `Sources/SwiftSeekCore/Gram.swift`
  - 新 `bigramSize = 2` / `bigrams(of:)` / `indexBigrams(nameLower:pathLower:)`
- `Sources/SwiftSeekCore/Database.swift`
  - `backfillFileBigrams` 在 v3→v4 迁移后跑
  - `insertFiles` 同时写 `file_grams` 和 `file_bigrams`（delete-then-insert 模式）
  - `cacheLock` + `rootsCached` + `settingsCached`
  - `listRoots` 命中 cache；`registerRoot` / `removeRoot` / `setRootEnabled` 自动 invalidate
  - `getSetting` 命中 cache（含 nil 值）；`setSetting` 按 key invalidate
  - 公开 `rootsCacheHits` / `rootsCacheMisses` 给 bench 观察
- `Sources/SwiftSeekCore/SearchEngine.swift`
  - `stmtLock` + `stmtCache` dictionary
  - `acquireStmt(_:handle:)` 获取或预编译并缓存
  - `executeQuery` 每次 reset+clear_bindings 复用
  - `candidates(tokens:limit:)` 路径分流：all long → trigram；all 2-char → bigram；mixed → trigram + 2-char post-filter；1-char → LIKE fallback
  - 新 `bigramCandidates(shortTokens:limit:)` 走 `file_bigrams` 表
  - 公开 `stmtCacheHits` / `stmtCacheMisses` 给 bench 观察
- `Package.swift` 新 `SwiftSeekBench` executable target
- `Sources/SwiftSeekBench/main.swift`
  - 10k fixture DB + 50 iters/query 默认
  - 2-char 目标 median ≤ 50ms / p95 ≤ 150ms
  - 3+char 目标 median ≤ 30ms / p95 ≤ 100ms
  - `--enforce-targets` 超标 exit(1)

#### 当前阶段完成判定标准
1. ✅ 2 字符查询不再以 `%LIKE%` 全表扫描为主路径
2. ✅ 3+ 字符查询继续保持索引驱动，无回退
3. ✅ 同类 SQL 不再每次搜索都重新 prepare（stmt cache hit rate 98%+ 实测）
4. ✅ roots / settings 热路径读取不再每次都直读 DB（rootsCacheHits/listRoots ≈ 99.7% 实测）
5. ✅ 仓库中有 benchmark / perf probe（`SwiftSeekBench`）
6. ✅ 文档固化目标（上面列出的 50ms / 30ms 数字）
7. ✅ `swift build` 成功
8. ✅ `SwiftSeekSmokeTest` 成功（107/107 含 9 条 F1 新用例）

#### 实测数据（release build，10k 合成文件，50 iters/query）
- warm 2-char `al`: median 2.38ms / p95 2.75ms
- warm 2-char `be`: median 4.52ms / p95 5.02ms
- warm 2-char `do`: median 2.75ms / p95 3.14ms
- warm 3+char `alpha`: median 2.96ms / p95 3.55ms
- warm 3+char `beta`: median 3.29ms / p95 3.90ms
- warm 3+char `docs`: median 2.93ms / p95 3.53ms
- warm 3+char `alpha beta`: median 1.40ms / p95 1.95ms
- stmt cache: 353 hits / 5 misses
- roots cache: 357 hits / 1 miss

### 当前最新 Codex 结论
- 轨道内历史结论：
  - `everything-performance / F1 / PASS`（round 1，2026-04-24）
  - `everything-performance / F2 / PASS`（round 2，2026-04-24）
- 当前阶段（F3）：功能面已落地，等待 round 1 验收。

### 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 当前 session id：`019dbdb7-8fa3-72b0-9ad0-f389fa6b1a90`
- 恢复策略：`codex exec resume <session_id>`
