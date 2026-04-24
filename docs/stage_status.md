# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J2`
- 当前轨道目标：补齐 SwiftSeek 作为长期使用 macOS 桌面工具时仍欠缺的窗口生命周期、Run Count 可见性、查询表达、搜索历史、上下文菜单、首次使用与权限引导体验，让实际使用更接近 Everything-like 工具，而不是只停留在搜索性能和数据层能力。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`

## 当前阶段：J2

### 阶段目标
解决用户“没看到启动次数 / Run Count”的实际体验问题。J2 不是证明 usage 数据库字段存在，而是证明用户在当前 GUI 里能看见、理解并恢复相关列。

### 当前代码审计依据
- `Schema` v6、`Database.recordOpen(path:)`、`SearchEngine LEFT JOIN file_usage`、`SearchResult.openCount/lastOpenedAt` 与结果表两列都已存在，这是 H1-H5 的既有基础。
- 用户仍反馈“没看到启动次数”，说明问题可能落在列默认可见性、列宽持久化、文案、旧构建或 GUI 呈现层，而不是纯数据层。
- `SearchViewController` 目前持久化结果列宽；J2 必须确认这不会让“打开次数 / 最近打开”列在真实使用中等于不可见。
- `recent:` / `frequent:` 已存在，因此 J2 验收必须检查“结果列显示”和“查询入口”对同一 usage 数据是否一致。

### 当前阶段禁止事项
- 不做 wildcard / quote / OR / NOT 查询语法，留给 J3。
- 不做搜索历史、Saved Filters 或快速过滤器，留给 J4。
- 不做上下文菜单动作扩展，留给 J5。
- 不做首次使用向导、Launch at Login 或签名 / 公证方案，留给 J6。
- 不读取 macOS 全局启动次数，不扫描系统隐私数据，不使用 private API。
- 不把 usage tie-break 改成压过文本相关性的主排序。

### 当前阶段完成判定标准
J2 只有同时满足以下条件才可验收通过：
1. 通过 SwiftSeek 打开某文件 3 次后，搜索该文件可见“打开次数”为 3。
2. “最近打开”时间随成功 `.open` 更新。
3. fresh DB / 从未打开文件显示清晰空值，如 `—`。
4. 默认列宽下“打开次数 / 最近打开”无需横向滚动或极端拉宽即可看见。
5. 历史列宽异常时有恢复默认列宽的路径。
6. 文档和 UI 都明确 Run Count 不是 macOS 全局启动次数。
7. `recent:` / `frequent:` 结果与显示列一致。
8. `docs/manual_test.md` 或等价手测文档补齐 J2 GUI 验证步骤；能自动化的列配置 / usage 可见性逻辑补 smoke，不能自动化的明确写手测。
9. 构建和现有 smoke 测试仍通过，若环境限制导致不能运行，必须记录具体原因。

## 已归档轨道

### `v1-baseline`
- `PROJECT COMPLETE` 2026-04-23，P0-P6，SwiftSeek v1 基线能力完成。

### `everything-alignment`
- `PROJECT COMPLETE` 2026-04-24，E1-E5，Everything-like 体验第一轮对齐完成。

### `everything-performance`
- `PROJECT COMPLETE` 2026-04-24，F1-F5，搜索热路径 / ranking / 结果视图 / DSL / RootHealth / 索引自动化一轮性能与落地收口。

### `everything-footprint`
- `PROJECT COMPLETE` 2026-04-24，G1-G5，session `019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`。
- 范围：DB 体积观测、compact index、Schema v5、分批回填、索引模式 UI、500k benchmark 与最终收口。
- 500k 实测亮点：compact 1.07 GB vs fullpath 3.46 GB（3.2× 更小），首次索引 44.87s vs 197.62s（4.4× 更快），reopen/migrate ms 级。

### `everything-usage`
- `PROJECT COMPLETE` 2026-04-24，H1-H5，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`。
- 范围：Schema v6 `file_usage`、`.open` 记录、usage JOIN、同 score tie-break、结果表“打开次数 / 最近打开”、`recent:` / `frequent:`、隐私开关、500k usage benchmark。
- 结论边界：usage 轨道证明了数据层和基础 UI 已落地，但不覆盖设置窗口生命周期、Dock/Menu Bar 行为、Run Count 用户可见性复核、搜索历史、Saved Filters、更多 Everything-style 查询语法和上下文菜单。

## 当前文档入口
- UX 差距清单：`docs/everything_ux_parity_gap.md`
- J1-J6 阶段任务书：`docs/everything_ux_parity_taskbook.md`
- 当前阶段给 Claude 的任务摘要：`docs/next_stage.md`
