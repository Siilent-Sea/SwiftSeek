# SwiftSeek Track Status

## 轨道总览
- 当前活跃轨道：`everything-alignment`
- 当前阶段：`E1`（功能面已落地；round 2 文档刷新中 / 等待 Codex 复验）
- 已归档轨道：`v1-baseline`

## 已归档轨道：`v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0 ~ P6
- 说明：这条记录只代表 v1 baseline 已完成，不是当前活跃轨道的停止条件

## 当前活跃轨道：`everything-alignment`

### 当前阶段：`E1`
搜索相关性与结果上限。

### 当前阶段目标（全部已落地）
- ✅ plain query 支持多词 AND 语义
- ✅ `SearchEngine` 4 档基础分上补齐 basename / token boundary / path segment / extension bonus + 多词 all-in-basename bonus
- ✅ GUI 搜索结果上限从固定 20 改为可配置（持久化 + 设置页入口），默认提高到 100
- ✅ 不改大 UI 框架

### 当前阶段禁止事项（仍然生效）
- 不做 query DSL（留给 E3）
- 不做全文搜索 / OCR / AI 语义
- 不做结果列表大改版（留给 E2）
- 不做与 E1 无关的设置页扩 scope

### 当前代码状态（E1 round 2 快照）
- `Sources/SwiftSeekCore/SearchEngine.swift`
  - `tokenize(_:)` 拆分空白
  - `search()` 多词 AND：候选召回用 union-of-grams + HAVING，post-filter 每 token substring
  - `scoreTokens()` 多词求和；`scoreToken()` 单词带 4 个 bonus；`score()` 保留 back-compat
- `Sources/SwiftSeekCore/SettingsTypes.swift`
  - `SearchLimitBounds`（min 20, max 1000, default 100）
  - `SettingsKey.searchLimit`
  - `Database.{get,set}SearchLimit` with clamping
- `Sources/SwiftSeek/UI/SearchViewController.swift`
  - runQuery 每次从 `database.getSearchLimit()` 读上限，NSLog + fallback
  - 状态栏文案动态回显 limit
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
  - GeneralPane 加 NSTextField + NSStepper 的结果上限配置 UI
- `Sources/SwiftSeekSmokeTest/main.swift`
  - P2 原 7 个断言已按 E1 加分规则更新
  - 新增 10 个 E1 用例（tokenize / AND / 4 bonus / all-in-basename / limit round-trip with clamping / limit 实际封顶 / 默认值不是 20）

### 当前阶段完成判定标准
1. ✅ plain query 多词搜索具有 AND 语义
2. ✅ 排序至少补齐 basename / token boundary / path segment / extension bonus
3. ✅ GUI 不再固定只显示 20 条结果
4. ✅ 结果上限可以配置（持久化 + 设置页入口），默认值 100
5. ✅ `swift build` 成功
6. ✅ `swift run SwiftSeekSmokeTest` 成功，61/61（新增 E1 10 条全 PASS）
7. ✅ 文档同步：
   - `docs/codex_acceptance.md`（round 2 刷新到反映真实验收结果）
   - `docs/next_stage.md`（切到 E2 任务书）
   - `docs/known_issues.md`（E1 已解决的限制已移除 / 标注）
   - `docs/stage_status.md`（本文件）
   - `docs/agent-state/codex-acceptance-session.{txt,json}`（本轨道会话 id 写回）

### 当前最新 Codex 结论
- 历史结论：`v1-baseline / P6 / PROJECT COMPLETE`（归档，不作当前轨道停止条件）
- 当前活跃轨道最新结论：
  - `everything-alignment / E1 / REJECT`（round 1，2026-04-24）
    - 原因：功能面 E1 全部落地，但文档未同步。4 项文档 required fix 已全部在 round 2 完成。
- 等待 Codex round 2 复验。

### 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- `codex-acceptance-session.txt`：纯文本 session id，1 行
- `codex-acceptance-session.json`：结构化 session 元数据
- 当前 session id：`019dbd4c-e0c9-7370-8a0c-1d4263a9f19b`
- 恢复策略：后续验收优先使用 `codex exec --session-id` 或等价方式读这个 session id，不要仅依赖 `resume --last`
