# 下一阶段任务书（准入 E5）

## Track
`everything-alignment`

## Stage
E4 当前刚落地（等待 Codex 验收）。本文件是 E4 → E5 的过渡任务书骨架；在 E4 PASS 之后再把正文展开到 E5。

## 目标（E5 预告）
收掉高频使用层面最后一批短板 —— 热键可配置、使用习惯优化、文档收尾。

## E5 明确做什么（预告）
- 全局热键可配置（GUI 修改、持久化、运行时重注册）
- 热键冲突与无效输入有明确反馈
- 文档与手测对齐最终行为
- 为当前活跃轨道准备最终验收（PROJECT COMPLETE 条件）

## E5 明确不做
- 不引入新的搜索后端
- 不做大规模 UX 重写
- 不碰 E1-E4 已经 sealed 的能力

## 涉及关键文件（预告）
- `Sources/SwiftSeek/App/GlobalHotkey.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/Database.swift`（settings 持久化）
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

---

## 过渡期说明
E4 round 1 验收完成后本文件需要刷新：
1. 若 E4 拿到 PASS，展开为完整 E5 任务书。
2. 若 E4 被 REJECT，维持当前 E4 状态，按 Codex required fix 修后重验。
