# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
**VERDICT: PROJECT COMPLETE for everything-ux-parity track**
TRACK: everything-ux-parity
STAGE: J6 (final)
ROUND: 1
DATE: 2026-04-25
SESSION_ID: 019dc07b-55f0-7712-9d7f-74441d7c81df

### Summary
`everything-ux-parity` 已结案。J1-J6 均通过独立验收：
- J1 round 1 PASS — 设置窗 hide-only close + Dock reopen + 菜单入口稳定（commit 14c94ab）
- J2 round 1 PASS — 搜索窗加宽 + 列 tooltip + 重置列宽，Run Count 真正可见（commit 69a7098）
- J3 round 3 PASS — wildcard / phrase / OR / NOT；纯 OR 走 orUnionCandidates；OR + 纯 wildcard alt 走 bounded scan union（commit 695b1ae）
- J4 round 1 PASS — Schema v7 query_history + saved_filters；隐私开关；搜索窗下拉 + 设置页管理（commit 98a1561）
- J5 round 1 PASS — 右键菜单扩到 Open With… / Copy Name / Copy 完整路径 / Copy 所在文件夹路径 / Trash 二次确认；Run Count 隔离（commit b7cbf79）
- J6 round 1 PROJECT COMPLETE — 首次使用 banner + Launch at Login (SMAppService 公开 API) + 窗口 frame 记忆 + 设置 tab 记忆（commit 8c5f327）

### 关键实现确认

1. **J1 生命周期**：`SettingsWindowController` 绑 `NSWindowDelegate`，`windowShouldClose` 只 orderOut；`AppDelegate` 实现 `applicationShouldHandleReopen`。smoke 覆盖 10 次关闭-打开循环。
2. **J2 可见性**：搜索面板默认宽 680→1020（6 列不被挤出），`setFrameAutosaveName`。header tooltip 明确"Run Count 只记录 SwiftSeek 内部 .open，不代表 macOS 全局启动次数"。header 右键"重置列宽"清 6 个持久化键并即时恢复默认。
3. **J3 查询语法**：`parseQuery` 产出 `plainTokens` / `phraseTokens` / `excludedTokens` / `excludedPhrases` / `orGroups`。候选检索三路：requireAnchors（plain+phrase 提 anchor）→ orUnionCandidates（纯 OR 每 alt 单独 gram 检索 + 大库 bounded scan union 覆盖纯 wildcard alt）→ filterOnlyCandidates（纯 filter / 纯 NOT / 纯 wildcard 回落）。smoke 18 条覆盖完整语义。
4. **J4 搜索历史**：Schema v7 `query_history(query PK)` 自然去重；`saved_filters(name PK)` UPSERT 安全。`SearchViewController.openSelected` 仅在 .open 成功后写 history（不因 typing 污染）。搜索窗"最近/收藏"菜单 + 设置页 Saved Filter 管理 + 隐私开关 + 清空。
5. **J5 上下文菜单**：新 `PathHelpers` 纯 Foundation，smoke 7 场景（unicode / trailing slash / root / empty / relative）。`Open With…` NSOpenPanel + `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` 公开 API。Trash 二次确认。Run Count 隔离：只 `.open` 累加。Rename 推迟（多表索引 + FSEvents 竞争成本高，文档明确）。
6. **J6 首次使用 / Launch / 窗口记忆**：
   - 首次使用 banner 覆盖 4 个决策点（roots / 权限 / 索引模式 / Run Count 语义）
   - `LaunchAtLogin.swift` 包 SMAppService.mainApp 公开 API；register/unregister 失败时 NSAlert 显示真实错误 + 常见原因；UI 展示"意图"与"系统实际状态"两面，无假成功
   - `SettingsWindowController` 加 `setFrameAutosaveName`；NSTabViewDelegate 持久化 tab index
   - 不破坏 F3 列宽 / J2 搜索窗 autosave / J4 搜索历史持久化

### Codex round 1 verdict（原文摘录）

> VERDICT: PROJECT COMPLETE
> TRACK: everything-ux-parity
> STAGE: J6
> ROUND: 1
> SUMMARY: `8c5f327` 把 J6 要求的最后几块收口了... 代码层面没有看到假实现... 自动化验证成立：`swift build --disable-sandbox` 通过，`swift run --disable-sandbox SwiftSeekSmokeTest` 为 `198/198`... 轨道级闭环已成立：J1 生命周期、J2 Run Count 可见性、J3 查询表达、J4 搜索历史 / Saved Filters、J5 上下文菜单、J6 首次使用 / Launch / 窗口状态记忆彼此一致。
> BLOCKERS: None
> REQUIRED_FIXES: None

### Non-blocking notes（Codex 留存）
1. Launch at Login 的用户体验仍受 macOS 签名/批准策略约束。当前实现诚实暴露这个边界：未签名 / 未公证构建在部分系统上可能需要手动批准，这不是 J6 blocker。
2. P5 `RebuildCoordinator` 并发 smoke 偶发抖动（不是 J6 回归），值得未来新轨道硬化。

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 198 / 198（P0-J6 全覆盖）
- `SwiftSeekStartup` → schema=7 + PASS（J4 bumped）

## 轨道内已通过阶段
- J1（round 1 PASS）
- J2（round 1 PASS）
- J3（round 3 PASS）
- J4（round 1 PASS）
- J5（round 1 PASS）
- J6（round 1 PROJECT COMPLETE）

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25

## 轨道切换说明
新轨道必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
