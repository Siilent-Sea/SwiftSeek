# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: REJECT (docs-only blockers anticipated; functional E3 complete)
TRACK: everything-alignment
STAGE: E3
ROUND: 1 (pending Codex verification)
DATE: 2026-04-24
SESSION_ID: 019dbd4c-e0c9-7370-8a0c-1d4263a9f19b

### Summary
- 功能面 E3 已落地：`SearchEngine.parseQuery(_:)` 支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:`；plain token 与 filter AND 组合；未知 key 保留为 plain token；未知 kind 静默忽略；空值忽略；filter-only 查询走单独候选路径并按 mtime desc 展示；CLI (`SwiftSeekSearch`) 经由 parser 天然支持无需改造。
- 本地自检：`swift build --disable-sandbox` 通过、`SwiftSeekSmokeTest` 85/85（新增 17 条 E3 用例全过）、`SwiftSeekStartup --db /tmp/ss-e3.sqlite3` → schema=3 + startup check PASS。
- 本轮仍按预期存在文档滞后窗口——本次 round 1 已在提交时同步刷新 5 个文档（本文件 / stage_status / next_stage / known_issues / agent-state json），交付给 Codex 复验。

### Blockers
- 待 Codex round 1 实际判定。预期本轮提交同步刷新文档后可直接 PASS。

### Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- E3 明确不做 query DSL（括号 / OR / NOT 等）、不做全文搜索、不做 AI 语义。若日后需要，留给单独轨道评估。
- `rootRestriction` prefix match 复用 `/` 边界规则与 P5 `pathUnderAnyRoot` 行为一致，避免 sibling-with-shared-prefix 误包。

### Evidence
- 检查文件：`docs/next_stage.md`、`docs/stage_status.md`、`docs/codex_acceptance.md`、`docs/known_issues.md`、`docs/agent-state/codex-acceptance-session.{txt,json}`、`Sources/SwiftSeekCore/SearchEngine.swift`、`Sources/SwiftSeekSmokeTest/main.swift`。
- 运行命令：`swift build --disable-sandbox`、`swift run --disable-sandbox SwiftSeekSmokeTest`、`swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-e3.sqlite3`。
- 观察：Build complete!；Smoke total 85 pass 85 fail 0；schema=3 + startup check PASS。

## 轨道内已通过阶段
- `E1` — 搜索相关性与结果上限（2026-04-24 round 2 PASS）
- `E2` — 结果视图与排序切换（2026-04-24 round 2 PASS）

## Next stage task book
- 见 `docs/next_stage.md`（当前是 E3 任务书骨架；E3 PASS 后刷新为 E4 任务书）
