# 下一阶段任务书（过渡 F1 → F2）

## Track
`everything-performance`

## Stage
F1 当前刚落地（等待 Codex 验收）。本文件是 F1 → F2 的过渡骨架。

## F2 目标（预告）
把"排序更像 Everything"与"limit 真正一致"重新做实。

### 必须做
- 重新审视 plain query 多词 AND 的真实效果（E1 已实现，F2 校准）
- 继续校准 basename / token boundary / path segment / extension bonus
- 统一 GUI / CLI / settings 的结果上限语义：`SwiftSeekSearch` CLI 当前默认 `--limit 20`，需改为与 DB 的 `search_limit` 一致或明确可覆盖
- 文档与代码重新对齐

### 明确不做
- 不做大性能架构重写（F1 已收口）
- 不做结果视图重设计（F3）
- 不做复杂 DSL（F4）
- 不引入新 bonus 评分维度（保持现有 4 档 + all-in-basename）

### 涉及关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSearch/main.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `docs/known_issues.md`

### 验收标准
1. 多词 AND 与 ranking 行为有明确可重复验证结果
2. GUI 与 CLI 的结果上限行为不再互相漂移
3. 文档对相关性和 limit 的描述与代码一致
4. `swift build` 与 smoke 全绿

---

## 过渡期说明
F1 round 1 验收完成后本文件需要刷新：
1. 若 F1 PASS，正文展开为完整 F2 任务书
2. 若 F1 REJECT，维持 F1 状态按 Codex required fix 修后重验
