# 下一阶段任务书

## 当前状态
**无活跃轨道。**

`everything-performance` 轨道已于 2026-04-24 由 Codex 独立验收颁发 `VERDICT: PROJECT COMPLETE`。

## 历史完成
- `v1-baseline`（P0-P6）：2026-04-23 PROJECT COMPLETE
- `everything-alignment`（E1-E5）：2026-04-24 PROJECT COMPLETE
- `everything-performance`（F1-F5）：2026-04-24 PROJECT COMPLETE

## 如何启动新轨道
以用户驱动为前提。启动新轨道需要在仓库内完成以下登记：

1. 在 `docs/stage_status.md` 顶部标注新轨道名和当前阶段
2. 新增 `docs/<track>_taskbook.md` 详细任务书（目标 / 阶段划分 / 验收标准 / 非目标）
3. 选择合适的 session id 策略：
   - 直接在 `docs/agent-state/codex-acceptance-session.{txt,json}` 中替换为新 session id
   - 或另起一份 `codex-acceptance-session-<track>.json` 并在 stage_status 中指向新文件

Codex 不会主动开启新轨道。Claude 也不会，除非用户明确发起。
