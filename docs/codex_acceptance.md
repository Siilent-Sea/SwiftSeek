# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: REJECT (docs-only blockers; functional G1 accepted)
TRACK: everything-footprint
STAGE: G1
ROUND: 1
DATE: 2026-04-24
SESSION_ID: 019dbdf8-b2c9-7c03-b316-dbbf7040d5d9
COMMIT_AT_REVIEW: HEAD before round 2 doc sync

### Summary
G1 功能面已落地（commit `G1: DB footprint stats + maintenance entries`）并在 2026-04-24 由 Codex round 1 验收。Codex 确认功能全部到位：CLI、Core API、Settings UI、smoke 126/0、startup PASS、VACUUM 风险横幅 + exit 1 都正常。

但 round 1 仍给 REJECT，原因不在代码，在 4 份状态文档仍保留旧口径：
1. `docs/agent-state/codex-acceptance-session.{txt,json}` 还停留在 `everything-performance / F5`
2. `docs/codex_acceptance.md` 仍写 `VERDICT: REJECT / ROUND: 0` + "G1 尚未实现"（立项时的占位状态）
3. `docs/stage_status.md` 第 92 行左右仍写 "G1 尚未实现"
4. `docs/manual_test.md` 顶部 note 还指向 `everything-performance`

Round 2 将 4 份文档同步到 HEAD 真实状态。

### Blockers (round 1)
1. agent-state 指向已归档轨道 session — 违反本仓 AGENTS 会话规则。
2. codex_acceptance.md / stage_status.md 仍写"G1 尚未实现"。
3. manual_test.md 顶部 note 指向旧轨道。

### Required fixes (round 1)
1. 用本次新轨道 session id 覆盖 `docs/agent-state/codex-acceptance-session.{txt,json}`（track=everything-footprint / stage=G1 / session=019dbdf8-b2c9-7c03-b316-dbbf7040d5d9）。 ✓
2. 更新 `docs/codex_acceptance.md` 与 `docs/stage_status.md` 反映 round 1 真实验收。 ✓
3. `docs/manual_test.md` header note 切到 `everything-footprint`。 ✓

### Non-blocking notes
1. Codex round 1 实际对上了任务书 G1 的 7 条验收标准（CLI stats / 维护入口 / fallback / VACUUM 二次确认 / build + smoke）。
2. GUI 维护页这轮是代码审查 + manual_test 清单，不是实际点按截图；headless 验收环境下可接受。
3. CLI VACUUM 风险横幅文字可考虑补一句"只能临时压实，不能根治"以进一步和 GUI 对齐（非 blocker）。

### Evidence (Codex round 1 实际操作)
- 实际运行命令：`swift build --disable-sandbox`、`swift run --disable-sandbox SwiftSeekSmokeTest`、`swift run --disable-sandbox SwiftSeekStartup --db /tmp/...`、`swift run --disable-sandbox SwiftSeekDBStats --db /tmp/...`、`.build/debug/SwiftSeekDBStats --db /tmp/... --run vacuum`
- 实际观察：Build complete! / 126 pass 0 fail / schema=4 + PASS / 完整 stats 输出 / vacuum 无 --yes 打印风险横幅并 exit 1

## 轨道内已通过阶段
（尚无 — G1 round 2 后再结算）

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24

## 当前阶段任务书
见 `docs/next_stage.md` + `docs/everything_footprint_taskbook.md` G1 段（第 13-71 行）。
