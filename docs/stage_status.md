# SwiftSeek Track Status

## 轨道总览
- 当前活跃轨道：`everything-alignment`
- 当前阶段：`E3`（查询语法与过滤；功能落地，等待 Codex 验收）
- 已归档轨道：`v1-baseline`
- 轨道内已通过阶段：`E1`（2026-04-24 round 2 PASS），`E2`（2026-04-24 round 2 PASS）

## 已归档轨道：`v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0 ~ P6
- 说明：这条记录只代表 v1 baseline 已完成，不是当前活跃轨道的停止条件

## 当前活跃轨道：`everything-alignment`

### 已通过：`E1`（搜索相关性与结果上限，2026-04-24 round 2 PASS）
- 多词 AND、4 个加分规则 + 多词 all-in-basename、结果上限持久化

### 已通过：`E2`（结果视图与排序切换，2026-04-24 round 2 PASS）
- 4 列高密度视图、列头排序、pure function `SearchEngine.sort(_:by:)`

### 当前阶段：`E3`
查询语法与过滤能力。

### 当前阶段目标（均已落地，待 Codex 验收）
- ✅ 支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:` 字段过滤
- ✅ plain query 与 filter 可组合（AND）
- ✅ 解析规则明确稳定：未知 key 当作 plain token；空值忽略；未知 kind 静默忽略
- ✅ CLI (`SwiftSeekSearch`) 与 GUI 使用同一 parser，无需 CLI 改造
- ✅ filter-only 查询走单独候选路径并按 mtime desc 展示

### 当前阶段禁止事项
- 不做全文内容搜索
- 不做 AI 语义搜索
- 不做复杂 DSL（括号 / OR / NOT 等）
- 不做 E4 / E5 范畴的改动

### 当前代码状态（E3 快照）
- `Sources/SwiftSeekCore/SearchEngine.swift`
  - 新增 `QueryKind` / `HiddenFilterMode` / `QueryFilters` / `ParsedQuery`
  - `parseQuery(_:)` 公开解析入口：tokenize 后按 `key:value` 分类
  - `search()` 分两条路径：plainTokens 非空走原 candidate + rank；空则走 `filterOnlyCandidates` + mtime desc
  - `matches(nameLower:pathLower:path:isDir:filters:)` 是测试友好的公开 filter predicate
  - `filterOnlyCandidates` 按 ext > root > kind 优先级选最有选择性的 SQL
  - `rowMatches` / `extension_` / `rootRestriction` prefix match 保持与 P5 `pathUnderAnyRoot` 一致的 `/` 边界规则
- `Sources/SwiftSeekSearch/main.swift`
  - 无需改动；位置参数已拼接成单 query string，新 parser 天然生效
- `Sources/SwiftSeekSmokeTest/main.swift`
  - 新增 17 条 E3 用例（parser 9 条 + predicate 5 条 + e2e 3 条）
  - smoke 总数 51 + 10 (E1) + 7 (E2) + 17 (E3) = 85，全绿

### 当前阶段完成判定标准
1. ✅ 5 个过滤语法稳定解析
2. ✅ 过滤语法与 plain query 可组合
3. ✅ CLI 与 GUI 保持核心语义一致
4. ✅ 文档说明支持/不支持语法
5. ✅ `swift build` + smoke 全绿
6. ✅ 非法 / 冲突语法容错

### 当前最新 Codex 结论
- 轨道内最新 PASS：`E2 / round 2 / 2026-04-24`
- 当前阶段（E3）：等待 round 1 验收

### 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 当前 session id：`019dbd4c-e0c9-7370-8a0c-1d4263a9f19b`
- 恢复策略：`codex exec resume <session_id>`
