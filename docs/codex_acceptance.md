# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: (pending F1 round 1 re-verification)
TRACK: everything-performance
STAGE: F1
ROUND: 1 (awaiting Codex)
DATE: 2026-04-24

### Summary
F1 功能面已落地，覆盖 4 项 blocker：

1. **2 字符查询主路径去掉 `%LIKE%`**：Schema v4 新增 `file_bigrams` 倒排表；`SearchEngine.bigramCandidates` 走 `JOIN file_bigrams` + `HAVING COUNT(DISTINCT gram)` 形态，与 trigram 主路径结构相同。
2. **prepared statement cache**：SearchEngine 内部按 SQL 字符串缓存 `OpaquePointer`；每次搜索 `sqlite3_reset` + `sqlite3_clear_bindings` 复用。实测 10k 库 50 iters × 7 query：353 hits / 5 misses。
3. **roots / settings 缓存**：Database 新增 `rootsCached` + `settingsCached`（NSLock 保护）；`listRoots` / `getSetting` 命中返回；`registerRoot` / `removeRoot` / `setRootEnabled` / `setSetting` 写入自动 invalidate。bench 实测 roots cache 357 hits / 1 miss。
4. **benchmark / perf probe**：新 `SwiftSeekBench` executable target；`--enforce-targets` 模式验证 median / p95 不超标。warm 2-char median 2-4ms，warm 3+char median 1-3ms，远低于 50ms / 30ms 文档目标。

### 本地自检
- `swift build --disable-sandbox` → Build complete!
- `SwiftSeekSmokeTest` → 107 pass / 0 fail（含 9 条 F1 新用例）
- `SwiftSeekStartup --db /tmp/ss-f1.sqlite3` → schema=4 + startup check PASS
- `SwiftSeekBench --enforce-targets` → 全部 [ok]，exit 0

### Blockers / Required fixes
- 待 Codex round 1 实际判定。

### Non-blocking notes
- `SwiftSeekSearch` CLI 默认 `--limit 20` 未改（F2 任务，不在 F1 scope）。
- Swift 6 `IndexProgress` Sendable warning 未动（非功能阻塞，留给 F5 或单独整理）。
- bigram 表对磁盘大小有影响：10k 文件约新增 40k bigrams。文档明确说明，不是 bug。

## 轨道内已通过阶段
（尚无）

## 历史归档轨道
- `v1-baseline`：P0 ~ P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1 ~ E5 / PROJECT COMPLETE 2026-04-24
