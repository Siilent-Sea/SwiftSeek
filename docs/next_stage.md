# 下一阶段任务书

## 当前状态
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H2`
- 阶段名称：Usage-based ranking 与结果列

`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint` 都已归档。`everything-footprint` 的 `PROJECT COMPLETE` 不覆盖使用历史、打开次数、最近打开和 usage-based ranking。

## 给 Claude 的 H2 执行任务

### 阶段目标
在 H1 已有 usage 数据模型和 `.open` 动作记录的基础上，把 usage 接到搜索结果与排序里，让常用项在“同等文本相关性”下更稳定靠前，并把 Run Count / 最近打开展示到结果表中。

### 必须实现
1. `SearchResult` 增加 usage 字段：
   - `open_count`
   - `last_opened_at`
2. `SearchEngine` 查询路径要能把 usage 数据 join 进结果，但不能破坏当前 plain token / DSL / compact/fullpath 的现有搜索语义。
3. ranking 引入 usage tie-break：
   - 只在同等文本相关性下生效
   - 不允许低相关结果因为 usage 高而压过高相关结果
   - 需要把 tie-break 规则写清楚，避免出现“看起来像随机”的顺序
4. 结果表增加列：
   - 打开次数
   - 最近打开
5. 列头排序增加：
   - usage / open count
   - last opened
6. 排序与列宽持久化继续走现有 settings 模型，不能破坏 name/path/mtime/size 现有 round-trip。
7. 文档明确：
   - Run Count / 最近打开只来自 SwiftSeek 内部 `.open`
   - 不是 macOS 全局启动次数
   - 不是系统 recent items

### 明确不做
- 不做 `recent:` / `frequent:` 入口或空查询推荐。
- 不做设置页“关闭记录 / 清空历史”。
- 不做 usage benchmark / 500k 收口。
- 不把 usage 当作主 score 直接加权，禁止压过文本相关性。
- 不记录 reveal/copy 为 Run Count。
- 不读取 macOS 全局使用历史。
- 不使用 private API。
- 不上传、不同步、不做遥测。

### 关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. 搜索结果能稳定带出 `open_count` / `last_opened_at`。
2. 同 score 结果中，高 usage 项靠前。
3. 不同 score 结果中，高相关项仍优先。
4. 结果表展示打开次数和最近打开两列。
5. 用户可按 usage / last opened 排序。
6. name/path/mtime/size 的原有排序和持久化不回退。
7. `swift build --disable-sandbox` 与 `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。

### 必须补的测试 / 手测
- smoke：`SearchResult` usage 字段 round-trip。
- smoke：同 score 下 usage tie-break 生效。
- smoke：低 score 高 usage 不压过高 score。
- smoke：按 usage / last opened 排序 round-trip。
- 手测：结果表显示新列并可排序。
- 手测：连续打开同一文件后，重新搜索能看到列值变化且排序符合预期。

## Codex 验收提示
H2 完成后调用 Codex 时必须继续使用 `everything-usage` 当前轨道的新验收 session，不得混用已归档 `everything-footprint` session。
