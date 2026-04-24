# 下一阶段任务书（过渡 F4 → F5）

## Track
`everything-performance`

## Stage
F4 当前刚落地（等待 Codex 验收）。本文件是 F4 → F5 过渡骨架。

## F5 目标（预告）
索引自动化与最终收尾，把轨道带到 PROJECT COMPLETE。

### 必须做
- 继续打磨 add root 自动后台索引（E4/F-系列已起步，可考虑 `--watch-seconds` 或 polling-watcher 的 UI 可感知）
- hidden / exclude 变化后可感知生效链路（当前已有弹窗 / 立即清理）
- 如成本可控，可引入轻量 usage-based tie-break（不破坏现有相关性）
- 收口 README / manual_test / known_issues
- 为本轨道准备最终验收

### 明确不做
- 不引入新的大搜索后端
- 不做大规模 UI 重写
- 不碰 F1-F4 已 sealed 的能力

### 涉及关键文件
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/RebuildCoordinator.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/codex_acceptance.md`

### 验收标准
1. 设置改动后系统行为更自解释
2. root 添加、后台索引、状态反馈链路顺畅
3. 如引入 usage tie-break 不破坏基础相关性
4. 文档 / 手测 / 已知限制与最终代码对齐
5. 具备 PROJECT COMPLETE 的条件

---

## 过渡期说明
F4 round 1 验收完成后本文件需要刷新：
1. 若 F4 PASS，正文展开为完整 F5 任务书
2. 若 F4 REJECT，维持 F4 状态按 Codex required fix 修后重验
