# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-menubar-agent`
- 当前阶段：`L3`
- 上一阶段验收结论：`L2 PASS`
- 当前正式验收 session：`019dc5fc-318e-7d31-bb00-2810eaf6642c`
- 日期：2026-04-26

## L2 验收结论

L2 round 1 基于提交 `5ff1334` 验收，结论为 `PASS`。

本轮确认成立的事实：

- `SettingsKey.dockIconVisible` 已加入，DB key 为 `dock_icon_visible`；`Database.getDockIconVisible()` 在缺失或非 `"1"` 时返回 `false`，保持 L1 no Dock 默认；`setDockIconVisible(_:)` 按 `"1"` / `"0"` 持久化。
- `AppDelegate.applicationDidFinishLaunching` 先在 build identity 三条 `NSLog` 后立即设置 `.accessory`，再打开 / migrate DB，随后读取 `getDockIconVisible()`；为 `true` 时切 `.regular` 并记录 `Dock icon visible (user preference); activation policy = .regular`，否则记录 L1 默认隐藏 Dock。读取失败只 NSLog 并保留 `.accessory`。
- `SettingsWindowController.GeneralPane` 已增加 Dock 图标复选框和 note，root view 高度从 360 调整为 440；`reflectDockIconState()` 会比较用户 intent 与当前 `NSApp.activationPolicy()` 并显示 `⚠️` pending-relaunch 或 `✓` 已对齐文案；保存失败会弹 `NSAlert` 并复位 checkbox。
- `SwiftSeekSmokeTest` 新增 3 个 L2 用例：默认 false、round-trip、reopen 持久化；总数从 209 提升到 212。
- `docs/install.md`、`docs/release_checklist.md`、`docs/known_issues.md`、`docs/manual_test.md` 已同步 L2 Dock 显示开关、重启生效策略和手测矩阵。
- L2 没有提前实现 L3 菜单栏状态增强或 L4 单实例 / 多 bundle 防护。

自动化验证：

- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox` 通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest` 通过，结果 `212/212`，3 个 L2 用例均通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox` 通过，并生成 `dist/SwiftSeek.app`。
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 显示 `LSUIElement => false`、`GitCommit => 5ff1334`、`CFBundleIdentifier => com.local.swiftseek`。
- `plutil -lint dist/SwiftSeek.app/Contents/Info.plist` 通过。
- `codesign -dv --verbose=2 dist/SwiftSeek.app` 显示 `Identifier=com.local.swiftseek`、`Signature=adhoc`、`TeamIdentifier=not set`。
- `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns` 存在，大小 273908 bytes，`file` 显示 Mac OS X icon / `ic04` type。

验收侧文档收口：

- `docs/release_checklist.md` §5c 补足第 10 个必跑 checkbox，覆盖 Dock visible -> no Dock 重复循环与重复菜单栏图标风险。
- `docs/known_issues.md` 把 L2 相关残留表述改为已落地，并把后续未完成范围收窄为 L3-L4。

未在本沙箱执行的验证：

- 真实 GUI Dock visible / no Dock 跨启动切换。
- 菜单栏点击、Dock visible 模式下入口验证、设置 note 文案实际显示。
- 跨模式菜单栏搜索 / 设置 / 退出 / 全局热键手测。

这些 GUI 项已写入 `docs/manual_test.md` §33z 与 `docs/release_checklist.md` §5c，发布前仍必须在真实 macOS GUI 环境中手动执行。

## 当前验收要求

下一次 Codex 验收应检查 L3：菜单栏菜单增强与状态可见性。

L3 验收时至少检查：

- 菜单栏搜索、设置、退出仍可用，L1/L2 行为不回归。
- status item tooltip 能显示 build identity、索引状态、索引模式和 root 简况。
- 菜单中能看到 build identity、index mode、root/DB 简况。
- 索引中 / 空闲状态变化能反映到菜单或 tooltip。
- 状态读取失败时有降级文案，不 crash、不隐藏主入口。
- 如实现最近打开 / 常用，数据来源必须是 SwiftSeek 内部 usage history，且隐私开关 / 清空 history 后行为正确。
- `docs/install.md`、`docs/manual_test.md`、`docs/release_checklist.md`、`docs/known_issues.md` 已同步 L3。
- 没有提前实现 L4 单实例 / 多 bundle 防护。

## 历史归档轨道

- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`
- `everything-productization`：K1-K6 / PROJECT COMPLETE 2026-04-26，session `019dc54e-017d-7de3-a24f-35c23f09ce08`

## 轨道切换说明

`everything-menubar-agent` 使用新的 Codex 验收 session `019dc5fc-318e-7d31-bb00-2810eaf6642c`；不得复用 `everything-productization` session `019dc54e-017d-7de3-a24f-35c23f09ce08`，也不得复用更早归档轨道 session。
