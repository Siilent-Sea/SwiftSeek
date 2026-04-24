# 下一阶段任务书（过渡 F2 → F3）

## Track
`everything-performance`

## Stage
F2 当前刚落地（等待 Codex 验收）。本文件是 F2 → F3 的过渡骨架。

## F3 目标（预告）
把结果列表从"已多列"推进到"更像文件搜索器"的高密度视图。

### 必须做
- 提升结果密度（行高 / 间距 / 字号 / 截断策略收口）
- 强化 name / path / mtime / size 的扫读效率
- 增强排序方式切换体验（sort desc 更明确 / persisted across restarts 可选）
- 收口列布局与状态保留（列宽、显示/隐藏某列、排序状态）

### 明确不做
- 不做 DSL 扩张（F4）
- 不做新搜索后端
- 不做根本的键盘流重做

### 涉及关键文件
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `docs/manual_test.md`

### 验收标准
1. 结果视图更高密度（可目测或通过固定行高 / 字号度量）
2. 主要字段一眼可扫
3. 相关性 / 路径 / 名称 / 修改时间 / 大小 等排序入口可用
4. 现有键盘流、QuickLook、右键、拖拽不回退
5. `swift build` + smoke 全绿

---

## 过渡期说明
F2 round 1 验收完成后本文件需要刷新：
1. 若 F2 PASS，正文展开为完整 F3 任务书
2. 若 F2 REJECT，维持 F2 状态按 Codex required fix 修后重验
