# 下一阶段任务书（过渡 F3 → F4）

## Track
`everything-performance`

## Stage
F3 当前刚落地（等待 Codex 验收）。本文件是 F3 → F4 过渡骨架。

## F4 目标（预告）
把 DSL 和 root 健康状态真的做实、做透、让用户可解释。

### 必须做
- 复查 `ext:` / `kind:` / `path:` / `root:` / `hidden:` 的真实行为与可用性
- filter-only 查询路径的效率（当前部分会落 bounded scan，F4 做实）
- `RootHealth` 从设置页 badge 推进到更完整心智：至少让搜索返回路径与 root 状态对应
- 让用户能解释"为什么这个 root 没结果"（paused / offline / unavailable / 未索引）

### 明确不做
- 不做全文搜索
- 不做云盘一致性承诺
- 不做复杂布尔查询语言（OR / NOT / 括号）
- 不改搜索后端

### 涉及关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `docs/known_issues.md`

### 验收标准
1. DSL 核心字段可用且高频场景效率可接受
2. `RootHealth` 不再只停留在设置页 badge
3. root 状态与搜索结果之间的关系对用户更可解释
4. 文档能准确描述当前支持 / 不支持的 DSL 能力
5. `swift build` + smoke 全绿

---

## 过渡期说明
F3 round 1 验收完成后本文件需要刷新：
1. 若 F3 PASS，正文展开为完整 F4 任务书
2. 若 F3 REJECT，维持 F3 状态按 Codex required fix 修后重验
