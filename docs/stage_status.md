# SwiftSeek Track Status

## 轨道总览
- 当前活跃轨道：`everything-alignment`
- 当前阶段：`E1`
- 已归档轨道：`v1-baseline`

## 已归档轨道：`v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0 ~ P6
- 说明：这条记录只代表 v1 baseline 已完成，不是当前活跃轨道的停止条件

## 当前活跃轨道：`everything-alignment`

### 当前阶段：`E1`
搜索相关性与结果上限

### 当前阶段目标
- 让 plain query 支持多词 AND 语义，而不是只把整串 query 当成单个连续子串
- 在当前 `SearchEngine` 的 4 档粗分基础上，补上 basename / token boundary / path segment / extension bonus
- 把 GUI 搜索结果上限从固定 20 改为可配置，默认值提高
- 不改大 UI 框架，只处理 E1 必需的相关性和结果上限问题

### 当前阶段禁止事项
- 不做 query DSL
- 不做全文搜索
- 不做 AI 语义搜索
- 不做结果列表大改版
- 不做与 E1 无关的设置页扩 scope

### 当前代码现状
- `Sources/SwiftSeekCore/SearchEngine.swift`
  - `normalize` 只做 trim / lowercase / 空白折叠
  - `score()` 只有 1000 / 800 / 500 / 200 四档
  - 多词 query 仍按单个完整字符串做包含匹配，不是 terms AND
- `Sources/SwiftSeek/UI/SearchViewController.swift`
  - `runQuery` 内部固定 `let limit = 20`
  - 状态栏直接提示“仅显示前 20 条”
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
  - 当前没有结果上限设置项
- `Sources/SwiftSeek/App/GlobalHotkey.swift`
  - 仍是固定默认热键常量，尚未进入当前阶段

### 当前阶段完成判定标准
1. plain query 多词搜索具有 AND 语义
2. 排序至少补齐：
   - basename bonus
   - token boundary bonus
   - path segment bonus
   - extension bonus
3. GUI 不再固定只显示 20 条结果
4. 结果上限可以配置，默认值明显高于 20
5. `swift build` 成功
6. `swift run SwiftSeekSmokeTest` 成功，并新增覆盖 E1 规则的用例
7. 文档同步到：
   - `docs/codex_acceptance.md`
   - `docs/next_stage.md`
   - `docs/known_issues.md`（如果限制发生变化）

### 当前最新 Codex 结论
- 历史结论：`v1-baseline / P6 / PROJECT COMPLETE`
- 当前活跃轨道最新有效结论：`everything-alignment / E1 / REJECT`
- 原因：E1 目标尚未落地，当前仓库仍停留在 baseline 搜索能力

### 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 当前要求：优先使用项目内显式 session id
- 当前文件状态：等待本轨道首次正式验收续接时写入 / 刷新
