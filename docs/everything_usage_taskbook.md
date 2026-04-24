# SwiftSeek Everything-usage 任务书

目标：在不读取 macOS 全局隐私数据的前提下，让 SwiftSeek 记录并利用“通过 SwiftSeek 打开”的使用行为，使结果排序、结果视图、最近打开和常用项体验更接近 Everything / launcher 混合型工具。

硬约束：
- 当前轨道固定为 `everything-usage`
- 阶段固定为 `H1` 到 `H5`
- Run Count 只表示 SwiftSeek 内部记录的打开次数
- 不读取 macOS 全局启动次数
- 不使用 private API
- 不扫描系统隐私数据
- 不上传、不遥测、不跨设备同步
- 每次只做当前阶段，不允许提前实现后续阶段

---

## H1：Usage 数据模型与动作记录

### 阶段目标
先让 SwiftSeek 能可靠记录“通过 SwiftSeek 打开的次数”。

### 明确做什么
- 设计并落盘数据模型，推荐表：`file_usage`。
- 字段至少包括：
  - `file_id`
  - `open_count`
  - `last_opened_at`
  - `updated_at`
  - `reveal_count`（可选）
  - `copy_path_count`（可选）
- 如果选择把 usage 字段放入 `files` 表，必须说明取舍：
  - 优点：join 简单
  - 缺点：行为数据和文件索引生命周期耦合更强
- 记录 `ResultAction.open`。
- 优先只记录 `.open`，不要把 reveal / copy 混进 Run Count。
- 打开失败时不增加 `open_count`。
- 目标路径已不在 DB 时必须有明确 fallback：
  - 不记录并输出可诊断日志
  - 或按 path 查找 `file_id`
  - 不允许 silent fail

### 明确不做什么
- 不做 usage-based ranking。
- 不做结果列。
- 不做最近打开 UI。
- 不做常用项入口。
- 不读取 macOS 全局使用历史。
- 不记录 reveal / copy 为 Run Count。

### 涉及关键文件
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. 新 schema / migration 创建 usage 数据结构。
2. fresh DB 中 usage count 语义为 0，而不是缺失导致崩溃。
3. `.open` 成功后 `open_count` +1。
4. repeated open 会累加。
5. `last_opened_at` 更新且可稳定读取。
6. 打开失败时不增加 `open_count`。
7. 删除 `files` 行后 usage 级联删除，或有明确清理方法。
8. 文档明确 SwiftSeek 只记录内部打开行为，不承诺系统级 Run Count。

### 必须补的测试 / benchmark / 手测
- smoke：fresh DB 有 usage 表或等价字段。
- smoke：`recordOpen(file_id:)` 初始 0 → 1。
- smoke：repeated open 计数累加。
- smoke：`last_opened_at` 更新。
- smoke：不存在 file_id / path fallback 行为可验证。
- smoke：删除 file 后 usage 级联或清理。
- 手测：通过搜索窗口打开文件后 DB 中 usage 变化。

---

## H2：Usage-based ranking 与结果列

### 阶段目标
让常用项更容易浮上来，但不能破坏基础文本相关性。

### 明确做什么
- `SearchResult` 增加 usage 字段：
  - `open_count`
  - `last_opened_at`
- `SearchEngine` 查询 join usage 数据。
- ranking tie-break 引入 usage：
  - 只作为同等相关性下的 tie-break
  - 不允许低相关结果压过高相关结果
- 结果视图增加列：
  - 打开次数
  - 最近打开
- 排序入口支持：
  - usage / open count
  - last opened
- 列宽和排序持久化接入 settings。

### 明确不做什么
- 不做最近打开独立页面。
- 不做复杂机器学习排序。
- 不做跨设备同步。
- 不把 usage 权重加到基础 score 里压过文本相关性。

### 涉及关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. 搜索结果包含 `open_count` 和 `last_opened_at`。
2. 同 score 结果中高 usage 项靠前。
3. 不同 score 结果中高相关项仍优先。
4. 结果表展示打开次数和最近打开。
5. 用户可按 usage / last opened 排序。
6. 现有 name / path / mtime / size 排序不回退。

### 必须补的测试 / benchmark / 手测
- ranking regression：同 score 下 usage tie-break 生效。
- ranking regression：低 score 高 usage 不压过高 score。
- result sort round-trip：usage / last opened。
- 手测：结果列展示并可排序。

---

## H3：最近打开 / 常用项体验

### 阶段目标
补齐 Everything / launcher 式高频使用体验，让用户能快速回到最近或常用目标。

### 明确做什么
- 支持特殊查询或入口：
  - `recent:` 或 UI 菜单项“最近打开”
  - `frequent:` 或 UI 菜单项“常用”
- 支持空查询下可选展示最近打开 / 常用项。
- 搜索窗口可通过快捷键进入最近 / 常用模式。
- 文档写清：
  - recent 只来自 SwiftSeek 内部打开历史
  - frequent 只来自 SwiftSeek 内部 `open_count`
  - 不读取系统最近项目

### 明确不做什么
- 不读取系统最近项目。
- 不做云同步。
- 不把最近/常用模式做成复杂仪表盘。
- 不改变普通 query 的基础语义。

### 涉及关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. `recent:` 或等价入口返回最近打开项。
2. `frequent:` 或等价入口返回打开次数最高项。
3. 空查询展示最近/常用项必须是可配置或可解释行为。
4. 普通搜索不受 recent/frequent 模式污染。
5. 文档明确 macOS 全局历史不在范围内。

### 必须补的测试 / benchmark / 手测
- recent 查询排序测试。
- frequent 查询排序测试。
- 空查询行为测试或手测。
- 快捷键 / 菜单入口手测。

---

## H4：使用历史管理与隐私控制

### 阶段目标
使用历史属于隐私数据，必须可控、可清理、可解释。

### 明确做什么
- 设置页增加：
  - 开启 / 关闭使用历史记录
  - 清空使用历史
  - 仅保留最近 N 天（可选）
- 默认记录可以开启，但必须文档说明。
- 关闭记录后不再写新 usage。
- 清空后结果列与 ranking 立刻反映。
- DB stats 显示 usage 表大小和行数。

### 明确不做什么
- 不上传。
- 不导出个人行为数据。
- 不做遥测。
- 不绕过用户关闭记录的设置。

### 涉及关键文件
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/DBStats.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekDBStats/main.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准
1. 使用历史记录开关持久化。
2. 关闭后 `.open` 不写入 usage。
3. 清空使用历史后 result usage 字段归零 / 为空。
4. ranking 立刻回到无 usage tie-break 行为。
5. DB stats 展示 usage 表大小和行数。
6. 文档说明隐私边界。

### 必须补的测试 / benchmark / 手测
- settings round-trip：history enabled。
- recordOpen disabled 不写入。
- clear history 清空所有 usage。
- DBStats usage row count。
- 手测：设置页开关和清空入口。

---

## H5：Everything-like 体验收口与 benchmark

### 阶段目标
对 `everything-usage` 轨道做最终验收，证明 usage join、recordOpen 和最近/常用入口不会破坏大库体验。

### 明确做什么
- benchmark：
  - 100k / 500k 下 join usage 后搜索延迟
  - usage 表 10k / 100k 记录下查询延迟
  - `recordOpen` 写入耗时
  - recent / frequent 查询耗时
- 文档收口：
  - `README.md`
  - `docs/known_issues.md`
  - `docs/manual_test.md`
  - `docs/everything_usage_gap.md`
- Codex 可据此判断 `PROJECT COMPLETE`。

### 明确不做什么
- 不做系统级 usage 导入。
- 不读取其他 App 历史。
- 不为了 benchmark 引入真实用户路径扫描。
- 不扩展到 AI/全文搜索。

### 涉及关键文件
- `Sources/SwiftSeekBench/main.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/everything_usage_gap.md`
- `docs/everything_usage_taskbook.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `README.md`

### 验收标准
1. benchmark 能输出 usage join search latency。
2. benchmark 能输出 `recordOpen` 写入耗时。
3. 500k + usage 表规模下搜索延迟没有不可接受回退。
4. recent / frequent 查询有明确耗时指标。
5. 文档、known issues、manual test 全部对齐最终代码。

### 必须补的测试 / benchmark / 手测
- usage benchmark 参数解析和输出格式测试。
- 100k / 500k usage join 对比报告。
- recordOpen 写入延迟报告。
- recent / frequent 手测。
- 最终回归：build、smoke、bench、manual_test 全部对齐。
