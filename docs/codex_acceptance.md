# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending F3 round 1)
TRACK: everything-performance
STAGE: F3
ROUND: 1 (awaiting Codex)
DATE: 2026-04-24
SESSION_ID: 019dbdb7-8fa3-72b0-9ad0-f389fa6b1a90

### Summary
F3 功能面已落地：
1. **Sort order 持久化**：新 `SettingsKey.result_sort_key` / `result_sort_asc`；`Database.{get,set}ResultSortOrder`；SearchViewController loadView 恢复、sortDescriptorsDidChange 保存。malformed 行自动 fallback scoreDescending。
2. **Column width 持久化**：每列一个 settings key（`result_col_width_{name,path,mtime,size}`）；`NSTableView.columnDidResizeNotification` 触发保存；loadView 用已保存宽度初始化，缺失则用程序默认。
3. **保留行为**：现有键盘流 / QuickLook / 右键 / 拖拽 / E2 多列视图 / E1 substring 高亮全部不动。

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 115 / 0（F3 +4 用例全过）
- `SwiftSeekStartup` → schema=4 + startup check PASS

### Blockers / Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- F3 没有引入新的视图组件；列宽 + sort 状态都通过已有 settings 表。
- deinit 清理了 NotificationCenter observer；无 leak。

## 轨道内已通过阶段
- F1（2026-04-24 round 1 PASS）
- F2（2026-04-24 round 2 PASS）

## 历史归档轨道
- `v1-baseline`：P0 ~ P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1 ~ E5 / PROJECT COMPLETE 2026-04-24
