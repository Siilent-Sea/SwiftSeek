# 下一阶段任务书（准入 E4）

## Track
`everything-alignment`

## Stage
`E3` 当前刚落地（等待 Codex 验收）。本文件是 E3 → E4 的过渡任务书骨架；在 E3 PASS 之后再把正文展开到 E4。

## 目标（E4 预告）
让 SwiftSeek 的索引状态与 root 健康对用户自解释：
- 新增 root 自动后台索引，无需再弹“要不要现在建立索引”
- hidden / exclude 改动的生效路径明确可感知
- root 可用性：就绪 / 索引中 / 离线 / 不可访问 / 已暂停 的状态展示
- 外接盘拔出 / 挂载的反馈

## E4 明确做什么（预告）
- 在 `SettingsWindowController` 的 roots 列表为每一 root 展示当前状态
- 新增 root 流程从“弹窗 confirm”切换到“自动后台任务 + 可取消”
- hidden / exclude 切换后在 UI 明确告知“已生效的部分”与“需要重建的部分”
- 外接盘 / 不可访问 root 的检测路径

## E4 明确不做
- 云盘 / 网络盘实时一致性承诺
- 复杂后台服务化
- 热键配置（留 E5）
- 结果视图或查询语法扩展（E2 / E3 已锁）

## 涉及关键文件（预告）
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/RebuildCoordinator.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

---

## 过渡期说明
E3 round 1 验收完成后本文件需要刷新：
1. 若 E3 拿到 PASS，正文展开为完整 E4 任务书（目标 / 必须做 / 不做 / 关键文件 / 验收标准 / 测试要求）。
2. 若 E3 被 REJECT，维持当前 E3 状态，按 Codex required fix 修后重验，不进 E4。
