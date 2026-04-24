# Codex 验收记录

本文件只保留当前有效结论。

VERDICT: REJECT (docs-only blockers; functional E1 accepted)
TRACK: everything-alignment
STAGE: E1
ROUND: 1
DATE: 2026-04-24
SESSION_ID: 019dbd4c-e0c9-7370-8a0c-1d4263a9f19b
COMMIT: ecde76a

SUMMARY:
- 功能面 E1 目标已全部落地并通过实测：`SearchEngine` 已实现空白分词 + 逐 token AND；已补齐 basename (+50) / token-boundary (+30) / path-segment (+40) / extension (+80) / multi-token all-in-basename (+100) bonus；`search_limit` 作为持久化设置，范围 20..1000，默认 100；`SearchViewController` 每次查询都从 DB 读取 limit 并在状态文案里动态回显；设置页常规 pane 加了 GUI 配置入口。
- Codex 实测重跑：`swift build --disable-sandbox` → `Build complete!`；`SwiftSeekSmokeTest` → `Smoke total: 61 pass: 61 fail: 0`（其中 10 个新增 E1 用例全 PASS）；`SwiftSeekStartup --db /tmp/ss-e1.sqlite3` → `schema=3` + `startup check PASS`。
- 本轮 REJECT 的原因不是代码问题，而是此前文档（`codex_acceptance.md` / `next_stage.md` / `known_issues.md` / `stage_status.md` 与 `docs/agent-state/` 会话状态）仍停留在 “E1 尚未落地” 的旧结论，未满足 AGENTS.md 要求的文档同步条件。本次 round 2 已按要求刷新，准备重验。

BLOCKERS (round 1):
1. 本文件自身仍描述 “E1 未实现”，与当前代码冲突。— 已在本次刷新修复。
2. `docs/next_stage.md` 仍是 E1 任务书，而按协议 E1 通过后应切到 E2 任务书。— 已刷新为 E2 任务书。
3. `docs/known_issues.md` 与 `docs/stage_status.md` 仍把 “GUI 固定 20 条”、“多词不是 AND”、“bonus 未实现” 写成当前限制 / 当前最新结论。— 已刷新。
4. `docs/agent-state/codex-acceptance-session.{txt,json}` 缺失。— 已写入。

REQUIRED_FIXES (round 1):
1. 将 `docs/codex_acceptance.md` 改为反映本轮真实验收结果和证据。✓
2. 将 `docs/next_stage.md` 改为仅面向 E2 的任务书。✓
3. 更新 `docs/known_issues.md` 与 `docs/stage_status.md`，去掉已被 E1 解决的限制，写明新的阶段状态。✓
4. 按会话协议写入 `docs/agent-state/codex-acceptance-session.{txt,json}`。✓

NON_BLOCKING_NOTES:
1. 本轮 review 时 working tree 是干净的（`git status --short` 无输出），结论针对 HEAD `ecde76a`。
2. 未发现明显越界实现；改动仍局限在 E1 规定的搜索相关性、结果上限和对应 smoke 覆盖内。
3. 本轮即使文档问题补齐，最高结论也仅能是 `PASS`（E1），不会是 `PROJECT COMPLETE`，因为 E2–E5 还没验收。

EVIDENCE:
- 实际检查文件：`docs/everything_alignment_taskbook.md`、`docs/stage_status.md`、`docs/agent-state/README.md`、`Sources/SwiftSeekCore/SearchEngine.swift`、`Sources/SwiftSeekCore/SettingsTypes.swift`、`Sources/SwiftSeekCore/Database.swift`、`Sources/SwiftSeek/UI/SearchViewController.swift`、`Sources/SwiftSeek/UI/SettingsWindowController.swift`、`Sources/SwiftSeekSmokeTest/main.swift`、`docs/codex_acceptance.md`、`docs/next_stage.md`、`docs/known_issues.md`。
- 实际运行命令：`git status --short`、`git log --oneline -5`、`swift build --disable-sandbox`、`swift run --disable-sandbox SwiftSeekSmokeTest`、`swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-e1.sqlite3`。
- 实际观察结果：`Build complete!`；`Smoke total: 61 pass: 61 fail: 0`；`schema=3 + startup check PASS`；E1 的 10 个新增 smoke 全 PASS。

NEXT_STAGE_TASKBOOK:
- 见 `docs/next_stage.md`（E1 通过后将切到 E2）。
