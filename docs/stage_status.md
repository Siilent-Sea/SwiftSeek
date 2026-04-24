# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-ux-parity`
- 当前阶段：`J1`
- 当前轨道目标：补齐 SwiftSeek 作为长期使用 macOS 桌面工具时仍欠缺的窗口生命周期、Run Count 可见性、查询表达、搜索历史、上下文菜单、首次使用与权限引导体验，让实际使用更接近 Everything-like 工具，而不是只停留在搜索性能和数据层能力。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`

## 当前阶段：J1

### 阶段目标
修复用户当前复现的高优先级 UX bug：设置窗口点左上角关闭后，必须能从菜单栏图标、主菜单和 Dock 行为重新打开或重新唤起可操作窗口。

J1 还要把 SwiftSeek 的基础 App 生命周期补到可信状态：
- 关闭所有窗口后 App 不退出
- 设置窗口关闭不应导致 controller / window 进入不可恢复状态
- Dock 点击在无可见窗口时能重新唤起搜索或设置入口
- 主菜单和菜单栏的“设置…”入口必须稳定可用

### 当前代码审计依据
- `AppDelegate.showSettings(_:)` 只在 `settingsWindowController == nil` 时创建 controller，之后调用 `showWindow` / `makeKeyAndOrderFront`。
- `SettingsWindowController` 创建的 `NSWindow` 已设置 `window.isReleasedWhenClosed = false`，但没有 `windowShouldClose` / delegate hide-only 策略。
- `AppDelegate` 当前没有实现 `applicationShouldHandleReopen(_:hasVisibleWindows:)`。
- `SearchWindowController` 的 search panel 也设置了 `isReleasedWhenClosed = false`，但只在 resign key 时隐藏；Dock reopen 与设置窗口重开不在这里闭环。
- 主菜单和菜单栏都有“设置…”入口，但用户已经复现关闭后不可重新打开，说明需要以真实 GUI 手测为准，而不是仅凭静态代码放过。

### 当前阶段禁止事项
- 不做 Run Count UI 改版，留给 J2。
- 不做 wildcard / quote / OR / NOT 查询语法，留给 J3。
- 不做搜索历史、Saved Filters 或快速过滤器，留给 J4。
- 不做上下文菜单动作扩展，留给 J5。
- 不做首次使用向导、Launch at Login 或签名 / 公证方案，留给 J6。
- 不重写整个 UI，不把设置窗口 bug 扩大成大规模架构重构。

### 当前阶段完成判定标准
J1 只有同时满足以下条件才可验收通过：
1. 设置窗口点左上角关闭后，可从菜单栏图标“设置…”再次打开。
2. 设置窗口点左上角关闭后，可从主菜单 `SwiftSeek -> 设置…` 再次打开。
3. 无可见窗口时点击 Dock 图标，能重新唤起一个可操作窗口或明确的搜索 / 设置入口。
4. 设置窗口关闭 / 打开循环 10 次，不崩溃、不丢 controller、不出现菜单入口失效。
5. 搜索窗口的呼出 / 隐藏行为没有回归。
6. 不引入 `Sources/` 以外无关改动，也不提前实现 J2-J6。
7. `docs/manual_test.md` 或等价手测文档补齐 J1 GUI 验证步骤；能自动化的生命周期逻辑补 smoke / headless 测试，不能自动化的明确写手测。
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
