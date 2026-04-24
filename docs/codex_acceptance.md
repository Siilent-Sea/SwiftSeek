# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending G4 round 1)
TRACK: everything-footprint
STAGE: G4
ROUND: 1
DATE: 2026-04-24
SESSION_ID: 019dbdf8-b2c9-7c03-b316-dbbf7040d5d9

### Summary
G4 按 G2 冻结合同在 Settings → 常规 tab 增加索引模式选择器：
- 两选项：Compact（默认推荐）/ Full path substring（高级，更大体积）
- 每项附 note 说明能力差异（plain query / path: 语义 / 体积）
- 切换弹窗引导：
  - → compact：提示切换含义 + "切换并开始 compact 回填" 启动 `MigrationCoordinator.backfillCompact`（后台）
  - → fullpath：提示 v4 表若已清空需重建
  - 取消时 popup 回滚到前值
- 设置已持久化，SearchEngine / Indexer 按 F1 cache 命中新 mode
- 模式切换后不影响已索引的 fullpath v4 数据（保留，切回立即可用）

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 138 / 0（G4 +3 用例：mode round-trip / compact↔fullpath 来回切换语义 / stmt cache 跨 mode 不污染）
- `SwiftSeekStartup --db /tmp/ss-g4.sqlite3` → schema=5 + PASS

### Blockers / Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- rebuild 目标表由 mode 决定（Indexer 已做，G3 验收过）；RebuildCoordinator 不需额外改动
- compact 回填在 UI 切换时直接启动。维护 tab 当前无专用 "继续回填" 按钮（维护页已有 DB stats 让用户观察进度）；如需独立按钮可在 G5 收尾时再加

## 轨道内已通过阶段
- G1（2026-04-24 round 2 PASS）
- G2（2026-04-24 round 2 PASS）
- G3（2026-04-24 round 2 PASS）

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
