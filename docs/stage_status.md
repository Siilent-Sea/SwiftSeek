# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J3`
- 当前轨道目标：补齐 SwiftSeek 作为长期使用 macOS 桌面工具时仍欠缺的窗口生命周期、Run Count 可见性、查询表达、搜索历史、上下文菜单、首次使用与权限引导体验，让实际使用更接近 Everything-like 工具，而不是只停留在搜索性能和数据层能力。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`

## 当前阶段：J3

### 阶段目标
补齐 Everything 风格常用查询表达能力，让用户可以更精确地表达文件名匹配、短语、二选一和排除。

### 当前代码审计依据
- 当前已支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:` / `recent:` / `frequent:`，但 plain query 仍主要是空白分词 AND。
- 当前还缺 `*` / `?` wildcard、quoted phrase、OR、NOT，这些是 Everything-like 查询体验的核心缺口。
- J2 已证明 usage 列默认可见性问题主要是窗口宽度和列宽恢复，不应在 J3 顺手重做 J2。
- J3 需要同时考虑 GUI 搜索窗和 CLI `SwiftSeekSearch` 的语义一致性。

### 当前阶段禁止事项
- 不做搜索历史、Saved Filters 或快速过滤器，留给 J4。
- 不做上下文菜单动作扩展，留给 J5。
- 不做首次使用向导、Launch at Login 或签名 / 公证方案，留给 J6。
- 不做完整括号表达式。
- 不做 regex。
- 不做全文搜索或 AI 语义搜索。
- 不把 usage tie-break、J2 列宽恢复和 J1 生命周期修复一起重写。

### 当前阶段完成判定标准
J3 只有同时满足以下条件才可验收通过：
1. `foo*` / `f?o` 等 wildcard 按预期匹配。
2. `"foo bar"` 作为短语匹配，不被空格拆成两个独立 AND token。
3. `foo|bar` 返回包含 foo 或 bar 的结果。
4. `foo !bar` 或 `foo -bar` 排除 bar。
5. 与 `ext:` / `path:` / `recent:` / `frequent:` 组合时语义明确。
6. 非法语法不崩溃，能容错为字面量或空结果。
7. GUI 与 CLI 对同一 query 结果一致。
8. `docs/manual_test.md` 或等价手测文档补齐 J3 GUI/CLI 验证步骤；能自动化的 parser / search 逻辑补 smoke。
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
