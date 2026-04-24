# 下一阶段任务书

## 当前状态
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H5`
- 阶段名称：benchmark 与轨道收口

`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint` 都已归档。`everything-footprint` 的 `PROJECT COMPLETE` 不覆盖使用历史、打开次数、最近打开和 usage-based ranking。

## 给 Claude 的 H5 执行任务

### 阶段目标
`everything-usage` 的功能闭环已经齐了，H5 只做最终 benchmark 与文档收口，证明 usage join、recordOpen、recent/frequent 和 H4 隐私控制在真实规模下没有把 SwiftSeek 的体验带崩，并给出可复现证据，供最终 `PROJECT COMPLETE` 判定使用。

### 必须实现
1. 基于现有 `SwiftSeekBench` 或等价 bench 路径，补齐 usage 轨道核心 benchmark：
   - 普通搜索在开启 usage join 后的延迟
   - `recent:` 查询延迟
   - `frequent:` 查询延迟
   - `recordOpen(path:)` 或等价写入路径的耗时
2. benchmark 至少覆盖：
   - 100k 规模
   - 500k 规模
   - usage 表存在显著行数时的路径（不要只测空 `file_usage`）
3. benchmark 输出必须能直接复现：
   - 命令
   - fixture / 数据规模
   - 机器与构建前提
   - 关键结果汇总
4. 如果 benchmark 暴露 usage 轨道真实 blocker，可修必要问题；但修复必须直接服务于 benchmark 收口，不能顺手扩 scope。
5. 文档收口：
   - `README.md` 明确 SwiftSeek usage 语义边界与已支持能力
   - `docs/known_issues.md` 更新为 H5 后的真实剩余限制
   - `docs/manual_test.md` 增补 H5 benchmark / 验证步骤
   - `docs/everything_usage_gap.md` / `docs/everything_usage_taskbook.md` / `docs/stage_status.md` 对齐最终状态

### 明确不做
- 不新增系统级 usage 导入或其他 App 历史读取。
- 不把 benchmark 扩成全文搜索、AI 语义搜索、复杂仪表盘或大规模 UI 改造。
- 不重写 H1-H4 已通过的语义合同。
- 不记录 reveal/copy 为 Run Count。
- 不读取 macOS 全局使用历史。
- 不使用 private API。
- 不上传、不同步、不做遥测。

### 关键文件
- `Sources/SwiftSeekBench/main.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `README.md`
- `docs/stage_status.md`
- `docs/everything_usage_gap.md`
- `docs/everything_usage_taskbook.md`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. benchmark 覆盖 usage 轨道关键读写路径，并包含非空 `file_usage` 数据集。
2. benchmark 结果以可复现方式落到文档，不是口头结论。
3. 100k / 500k 下结果足以判断 usage 轨道没有把 SwiftSeek 的主路径体验带崩。
4. `swift build --disable-sandbox` 与 `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。
5. 文档收口完成，Codex 可据此直接判断 `everything-usage` 是否 `PROJECT COMPLETE`。

### 必须补的测试 / 手测
- 保持现有 smoke 全绿；如修了 benchmark 暴露的问题，补最小必要回归 smoke。
- bench：100k 普通搜索 + usage join。
- bench：500k 普通搜索 + usage join。
- bench：100k / 500k 的 `recent:` / `frequent:` 查询。
- bench：非空 `file_usage` 下 `recordOpen` 写入。
- 手测：按文档命令可重跑 benchmark，并能得到同量级结论。

## Codex 验收提示
H5 是 `everything-usage` 的最终收口阶段。完成后调用 Codex 时，若 benchmark 与文档都成立，应该直接申请该轨道的 `PROJECT COMPLETE`，仍不得混用已归档 `everything-footprint` session。
