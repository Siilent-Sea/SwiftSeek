# 下一阶段任务书

## 当前状态
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H4`
- 阶段名称：使用历史管理与隐私控制

`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint` 都已归档。`everything-footprint` 的 `PROJECT COMPLETE` 不覆盖使用历史、打开次数、最近打开和 usage-based ranking。

## 给 Claude 的 H4 执行任务

### 阶段目标
usage 已经能被记录、排序和直接查询，H4 要把它变成“可控的隐私数据”：用户能关闭记录、清空历史，并且 UI / 排序 / recent/frequent / stats 会立刻反映这一变化。

### 必须实现
1. 设置页增加“记录使用历史”开关与“清空使用历史”入口。
2. 开关持久化到现有 settings 模型，并明确默认值。
3. 关闭记录后：
   - `.open` 不再写入 `file_usage`
   - H2 的 usage tie-break / 排序 / 结果列，以及 H3 的 recent/frequent 都要体现“没有新历史写入”的状态
4. 清空使用历史后：
   - `file_usage` 被清空
   - 结果列归零或显示 `—`
   - usage tie-break 立即退回“无 usage 数据”行为
   - `recent:` / `frequent:` 结果同步清空
5. `SwiftSeekDBStats` 或等价现有 stats 路径要能展示 usage 表行数或体积信息，至少让用户知道 usage 数据存在且已被清空。
6. 文档明确隐私边界：
   - usage 只记录 SwiftSeek 内部行为
   - 关闭后不再新增记录
   - 清空会移除现有记录
   - 不上传、不遥测、不跨设备同步

### 明确不做
- 不做 usage benchmark / 500k 收口。
- 不改 H2/H3 已通过的搜索、tie-break 和 recent/frequent 语义合同，除非是“关闭记录/清空历史后应反映为空”这一必要效果。
- 不做复杂隐私面板或导出个人历史。
- 不记录 reveal/copy 为 Run Count。
- 不读取 macOS 全局使用历史。
- 不使用 private API。
- 不上传、不同步、不做遥测。

### 关键文件
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/DatabaseStats.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekDBStats/main.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. usage history 开关持久化成功。
2. 关闭后 `.open` 不再写入 usage。
3. 清空后 `file_usage` 为空，结果列 / 排序 / recent/frequent 立即反映。
4. DB stats 能展示 usage 表行数或体积信息。
5. 文档明确关闭/清空后的语义与隐私边界。
7. `swift build --disable-sandbox` 与 `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。

### 必须补的测试 / 手测
- smoke：settings round-trip for usage history enabled/disabled。
- smoke：disabled 状态下 `recordOpen` 不写入。
- smoke：clear history 后 `file_usage` 为空。
- smoke：recent/frequent 在清空后返回空。
- smoke：DBStats usage 行数或体积可读。
- 手测：设置页开关与清空入口可用，sqlite3 查表结果与 UI 一致。

## Codex 验收提示
H4 完成后调用 Codex 时必须继续使用 `everything-usage` 当前轨道的新验收 session，不得混用已归档 `everything-footprint` session。
