# SwiftSeek Everything-usage Gap

本文档基于当前代码审计，记录 SwiftSeek 在使用历史、打开次数、最近打开和 usage-based ranking 方面与 Everything-like 体验的差距。

边界先写清：SwiftSeek 只能可靠记录“通过 SwiftSeek 触发的行为”。不要承诺读取 macOS 全局启动次数、系统最近项目、其他 launcher 的历史，不能使用 private API，也不能扫描系统隐私数据。

## 1. 缺少 open_count / run_count 数据模型

### 当前现状
- `Sources/SwiftSeekCore/Schema.swift` 当前 `Schema.currentVersion = 5`。
- v5 schema 包含 `files`、`roots`、`excludes`、`settings`、v4 fullpath gram 表、v5 compact index 表和 `migration_progress`。
- 目前没有 `file_usage`、`open_count`、`run_count`、`last_opened_at` 之类结构。

### 为什么是问题
Everything-like 工具常见 Run Count / 使用次数是结果解释和常用项排序的重要信号。SwiftSeek 现在即使用户每天通过它打开同一个文件，也没有地方持久化这类行为。

### 用户影响
- 无法展示 Run Count。
- 无法展示最近打开。
- 无法基于用户习惯优化重复搜索体验。

### 推荐优先级
高

### 建议解决阶段
`H1`

## 2. 缺少 last_opened_at

### 当前现状
- `SearchResult` 当前只有 `path`、`name`、`isDir`、`size`、`mtime`、`score`。
- DB 里也没有最近打开时间字段或表。

### 为什么是问题
`mtime` 是文件系统修改时间，不等于用户最近使用时间。用户经常需要找“刚通过 SwiftSeek 打开过的文件”，当前无法表达。

### 用户影响
- 结果视图无法显示“最近打开”。
- 后续也无法实现 `recent:` 或最近打开入口。

### 推荐优先级
高

### 建议解决阶段
`H1` 存储，`H2/H3` 展示和入口。

## 3. 打开动作未写入使用历史

### 当前现状
- `Sources/SwiftSeek/UI/ResultActionRunner.swift` 的 `.open` 分支只是 `NSWorkspace.shared.open(url)`。
- `Sources/SwiftSeek/UI/SearchViewController.swift` 的 `openSelected()` 只调用 `ResultActionRunner.perform(.open, target:)` 并关闭窗口。
- 没有任何对 `Database` 的 usage 写入。

### 为什么是问题
没有动作记录，usage 表即使新增也不会有数据。打开成功/失败也没有被区分，后续无法安全累加 `open_count`。

### 用户影响
- 用户真实使用不会沉淀成排序信号。
- 常用文件不会因为高频打开而更容易再次出现。

### 推荐优先级
高

### 建议解决阶段
`H1`

## 4. 搜索排序缺少 usage tie-break

### 当前现状
- `SearchEngine.rank` 只用文本相关性 score 排序。
- `SearchEngine.sort` 支持 `score` / `name` / `path` / `mtime` / `size`。
- 同 score 下 tie-break 是更短路径和字母序路径。
- `SearchResult` 没有 `open_count` 或 `last_opened_at` 字段。

### 为什么是问题
Everything / launcher 混合体验里，用户重复打开的目标通常应该在同等相关性下更稳定靠前。当前 SwiftSeek 不能利用这一信号。

### 用户影响
- 高频文件和低频文件在同等文本相关性下没有使用习惯差异。
- 用户会感觉“搜得到，但不够懂我”。

### 推荐优先级
高

### 建议解决阶段
`H2`

## 5. 结果视图缺少 usage 列

### 当前现状
- `SearchViewController` 结果表已有 `名称` / `路径` / `修改时间` / `大小` 四列。
- 列头排序支持 name / path / mtime / size。
- 没有 Run Count、打开次数、最近打开或 usage score 列。

### 为什么是问题
即使后续记录了 usage，用户也需要看到这些信息，才能理解为什么某些结果靠前，或按打开次数/最近打开主动排序。

### 用户影响
- 使用历史不可见。
- Everything-like 的 Run Count 体验缺失。

### 推荐优先级
中

### 建议解决阶段
`H2`

## 6. macOS 全局启动次数不可承诺

### 当前现状
- 代码没有读取系统全局启动次数。
- SwiftSeek 当前只掌握自己的 DB 和通过自身 UI/CLI 触发的行为。

### 为什么是问题
macOS 没有适合作为普通 App 稳定读取“任意文件/应用全局启动次数”的公开、低风险接口。强行读取系统隐私数据或依赖 private API 会带来权限、隐私、稳定性和维护风险。

### 用户影响
- SwiftSeek 的 Run Count 语义必须限定为“通过 SwiftSeek 打开的次数”。
- 不能把它写成 Everything 在 Windows 上可能看到的系统级启动历史。

### 推荐优先级
高

### 建议解决阶段
`H1` 到 `H5` 全程约束。

## 7. 缺少使用历史清理 / 重置能力

### 当前现状
- `SettingsTypes` 没有 usage history 开关。
- 设置页没有清空使用历史入口。
- DB stats 没有 usage 表大小。

### 为什么是问题
使用历史属于隐私数据。即使它只记录 SwiftSeek 内部行为，也必须可关闭、可清空、可解释。

### 用户影响
- 用户无法控制行为记录。
- 后续如果直接引入 ranking，会缺少隐私和可恢复控制。

### 推荐优先级
中

### 建议解决阶段
`H4`

## 为什么新轨道叫 `everything-usage`

`everything-footprint` 解决的是大库体积和维护成本。当前新反馈集中在 Everything-like 工具的使用习惯能力：Run Count、最近打开、常用项、usage-based tie-break。`everything-usage` 明确把范围限定为“SwiftSeek 内部使用行为数据及其体验应用”，避免误导成系统级监控或泛 UI 重写。
