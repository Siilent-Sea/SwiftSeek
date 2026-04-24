# 下一阶段任务书

## 当前状态
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H3`
- 阶段名称：最近打开 / 常用项体验

`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint` 都已归档。`everything-footprint` 的 `PROJECT COMPLETE` 不覆盖使用历史、打开次数、最近打开和 usage-based ranking。

## 给 Claude 的 H3 执行任务

### 阶段目标
基于 H1-H2 已有的 usage 数据模型、动作记录、结果列和 tie-break，补齐 `recent:` / `frequent:` 这类入口，让用户能直接回到最近或最常打开的目标，同时不污染普通搜索语义。

### 必须实现
1. 提供“最近打开”入口：
   - `recent:` 查询前缀，或等价明确入口
   - 返回 `lastOpenedAt DESC` 的 SwiftSeek 内部打开历史
2. 提供“常用项”入口：
   - `frequent:` 查询前缀，或等价明确入口
   - 返回 `openCount DESC` 的 SwiftSeek 内部高频项
3. 普通搜索语义不能被 recent/frequent 模式污染：
   - 普通 query 继续走现有文本搜索 + H2 tie-break
   - `recent:` / `frequent:` 必须是显式模式，不要偷偷改变普通空查询或普通关键词结果
4. 若支持空查询展示最近/常用，必须写清楚触发条件与解释；如果不做空查询展示，也要保持行为明确一致。
5. 文档明确：
   - recent 只来自 SwiftSeek 内部 `.open`
   - frequent 只来自 SwiftSeek 内部 `openCount`
   - 不读取 macOS 最近项目或系统全局历史

### 明确不做
- 不做设置页“关闭记录 / 清空历史”。
- 不做 usage benchmark / 500k 收口。
- 不改 H2 已完成的结果列与 tie-break 合同。
- 不做复杂仪表盘或新页面级信息架构。
- 不记录 reveal/copy 为 Run Count。
- 不读取 macOS 全局使用历史。
- 不使用 private API。
- 不上传、不同步、不做遥测。

### 关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. `recent:` 或等价入口能返回最近打开项，排序正确。
2. `frequent:` 或等价入口能返回打开次数最高项，排序正确。
3. 普通搜索不会被 recent/frequent 模式污染。
4. 若实现空查询展示，行为是可解释、可验证的。
5. 文档明确 recent/frequent 只来自 SwiftSeek 内部历史，不代表 macOS 全局历史。
7. `swift build --disable-sandbox` 与 `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。

### 必须补的测试 / 手测
- smoke：`recent:` 查询按 `lastOpenedAt DESC` 返回。
- smoke：`frequent:` 查询按 `openCount DESC` 返回。
- smoke：普通 query 不受 `recent:` / `frequent:` 实现影响。
- 若做空查询展示：补对应 smoke 或最少有可重复手测方案。
- 手测：recent/frequent 入口可用，且结果与 sqlite3 直接查 `file_usage` 对得上。

## Codex 验收提示
H3 完成后调用 Codex 时必须继续使用 `everything-usage` 当前轨道的新验收 session，不得混用已归档 `everything-footprint` session。
