# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
**VERDICT: PROJECT COMPLETE**
TRACK: everything-usage
STAGE: H5
ROUND: 2
DATE: 2026-04-24
SESSION_ID: 019dbe5f-9680-7872-9eac-cc41e5f0f40e

### Summary
`everything-usage` 全轨道现已 `PROJECT COMPLETE`。H1-H4 已在同一 Codex 验收 session 通过；H5 提交 `49841be` 落地 usage benchmark 与轨道 roll-up，提交 `7847dd3` 修完上一轮 H5 文档 blocker：README 不再误称“没有 Run Count / 最近打开 / usage tie-break”，`docs/known_issues.md` 的搜索相关性段已改成 H2 实际状态，`docs/everything_usage_bench.md` 的最终结论段已去重并与表格数据对齐。

本轮实际验收确认：
- `SwiftSeekBench` 已支持 `--usage-rows` / `--record-open-ops`，可测 usage JOIN、`recent:` / `frequent:` 和 `recordOpen` 路径；轻量实跑确认 `--usage-rows=0` 保持 G5 兼容输出，`--usage-rows>0` 会打印 H5 usage 段。
- `docs/everything_usage_bench.md` 已给出 100k / 500k 实测数据、复现命令、边界说明与 H1-H4 合同结论，且最终摘要不再与表格矛盾。
- `README.md`、`docs/known_issues.md`、`docs/stage_status.md`、`docs/manual_test.md` 现已与 H1-H5 真实状态对齐。
- `swift build --disable-sandbox` 成功，`swift run --disable-sandbox SwiftSeekSmokeTest` 实际跑到 `161/161`。

### Blockers / Required fixes
- None

### Non-blocking notes
1. 当前环境默认 `swift build` / `swift run` 会因为模块缓存与 CLT SDK 组合报错；按仓库文档加 `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache` 且带 `--disable-sandbox` 后可通过。
2. `docs/everything_usage_gap.md` 仍保留轨道开启时的 gap 文本，属于历史差距快照约定，不影响本轮 `PROJECT COMPLETE`。
3. 500k 规模下 warm 3+char 仍高于 F1 在 10k 规模时的旧目标，这已在 G5/H5 文档里诚实记录为规模效应事实，不是 usage 轨道 blocker。

## 当前轨道阶段
- 当前活跃轨道：**无**（`everything-usage` 已归档）
- 完整阶段计划：`docs/everything_usage_taskbook.md`（历史参考）
- 差距清单：`docs/everything_usage_gap.md`（历史参考）

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24

## 轨道切换说明
新轨道必须使用新的 Codex 验收 session；不得复用任何已归档轨道（`everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`）的 session id。
