# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J5`
- 当前轨道目标：补齐 SwiftSeek 作为长期使用 macOS 桌面工具时仍欠缺的窗口生命周期、Run Count 可见性、查询表达、搜索历史、上下文菜单、首次使用与权限引导体验，让实际使用更接近 Everything-like 工具，而不是只停留在搜索性能和数据层能力。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`

## 当前阶段：J5

### 阶段目标
让结果右键菜单更接近成熟文件搜索器，减少用户跳回 Finder 的次数。

### 当前代码审计依据
- 当前窗口生命周期、Run Count 可见性、查询表达和查询复用都已收口，剩余主要缺口转向“文件操作是否足够顺手”。
- 当前结果交互仍偏基础：用户常要跳回 Finder 才能做 Copy Name / Copy Parent Folder / Open With / Trash 等操作。
- J5 必须保证 usage 统计只对 Open 生效，Reveal / Copy / Trash 都不能污染 Run Count。
- 若做多选，必须明确 keyboard selection 与 table selection 的一致性；不能只堆菜单项不收口行为。

### 当前阶段禁止事项
- 不做首次使用向导、Launch at Login 或签名 / 公证方案，留给 J6。
- 不做完整文件管理器。
- 不做权限绕过。
- 不做批量重命名器。
- 不做云同步。
- 不做遥测。
- 不读取系统搜索历史。
- 不把 Reveal / Copy 计入 Run Count。

### 当前阶段完成判定标准
J5 只有同时满足以下条件才可验收通过：
1. 右键菜单包含新增动作且目标正确。
2. Copy Name / Full Path / Parent Folder 写入剪贴板内容准确。
3. Open With 使用公开 AppKit API。
4. Rename 成功后索引和 UI 状态可恢复；若不做 Rename，必须明确写出推迟原因。
5. Move to Trash 有确认和失败反馈。
6. 只有 Open 增加 Run Count。
7. `docs/manual_test.md` 或等价手测文档补齐 J5 GUI 验证步骤；能自动化的字符串动作补 smoke。
8. 构建和现有 smoke 测试仍通过，若环境限制导致不能运行，必须记录具体原因。

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
