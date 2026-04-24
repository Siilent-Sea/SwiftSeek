# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending E4 round 1)
TRACK: everything-alignment
STAGE: E4
ROUND: 1 (awaiting Codex)
DATE: 2026-04-24
SESSION_ID: 019dbd4c-e0c9-7370-8a0c-1d4263a9f19b

### Summary
- E4 功能已落地：`RootHealth` 5 档状态 + `Database.computeRootHealth`；`RebuildCoordinator.indexOneRoot` + `currentlyIndexingPath`；IndexingPane 状态列 + chained observer 实时刷新；新 root 自动后台索引（无 confirm 弹窗）；hidden toggle 切换后弹 “立即重建 / 稍后” 选择。
- 本地自检：`swift build --disable-sandbox` → Build complete!；`SwiftSeekSmokeTest` → 92/92（新 E4 用例 7 条全过）；`SwiftSeekStartup --db /tmp/ss-e4.sqlite3` → schema=3 + startup check PASS。
- 文档预刷新：本文件 / stage_status / next_stage / known_issues / agent-state json 已同步到 E4 状态。

### Blockers
- 待 Codex round 1 实际判定。

### Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- `indexOneRoot` 不会 stamp `last_rebuild_*`，因为那是整个 rebuild 周期的审计；单 root 属部分刷新。
- chained observer：IndexingPane 在 viewWillAppear 包住 AppDelegate 已有的 menu-bar 订阅，viewWillDisappear 恢复。保证菜单栏逻辑不被覆盖。
- offline vs unavailable：`fileExists` 失败 → offline；存在但 `isReadableFile` 失败 → unavailable。非目录路径同样判 offline（作为 root 不可用）。

### Evidence
- 检查文件：`docs/*`、`Sources/SwiftSeekCore/SettingsTypes.swift`、`Sources/SwiftSeekCore/RebuildCoordinator.swift`、`Sources/SwiftSeek/UI/SettingsWindowController.swift`、`Sources/SwiftSeekSmokeTest/main.swift`。
- 命令：`swift build --disable-sandbox`、`swift run --disable-sandbox SwiftSeekSmokeTest`、`swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-e4.sqlite3`。
- 观察：Build complete!；Smoke 92/92；schema=3 + startup check PASS。

## 轨道内已通过阶段
- E1（2026-04-24 round 2 PASS）
- E2（2026-04-24 round 2 PASS）
- E3（2026-04-24 round 1 PASS）

## Next stage task book
- 见 `docs/next_stage.md`（E4→E5 过渡骨架；E4 PASS 后展开为完整 E5 任务书）
