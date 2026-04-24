# 下一阶段任务书（everything-alignment 收尾）

## Track
`everything-alignment`

## Stage
E5 当前刚落地。E1-E4 均已 PASS。本文件是轨道最终收尾前最后一轮提示。

## 目标
- 热键配置 + 使用习惯优化 + 文档收尾 = E5 已完成
- 本轨道如 Codex round 1 通过，可颁发 `PROJECT COMPLETE for everything-alignment track`

## E5 完成判定（复述自 docs/everything_alignment_taskbook.md）
1. 热键可配置且持久化 ✅
2. 热键冲突与无效输入有明确反馈（注册失败弹窗 + 自动回滚）✅
3. 如果引入 usage-based tie-break，必须可解释且不破坏基础相关性 — 本轮未引入（非必需）
4. 文档与手测对齐最终行为 ✅

## 如果 Codex 颁发 PROJECT COMPLETE
- 本文件保留作为 v2+ 新轨道启动点的参考模板
- `docs/stage_status.md` 的 "当前活跃轨道" 将变更为 "（无活跃轨道，待用户确认新轨道）"
- `docs/codex_acceptance.md` 将把 `PROJECT COMPLETE` 固定为最终结论

## 如果 Codex 仍 REJECT
- 按 required fix 修 + re-verify，直到 PASS
- 不启动新轨道
