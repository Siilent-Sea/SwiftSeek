# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-menubar-agent`
- 当前阶段：`L2`
- 上一阶段验收结论：`L1 PASS`
- 当前正式验收 session：`019dc5fc-318e-7d31-bb00-2810eaf6642c`
- 日期：2026-04-26

## L1 验收结论

L1 round 1 基于提交 `d5cad2b` 验收，结论为 `PASS`。

本轮确认成立的事实：

- `Sources/SwiftSeek/App/AppDelegate.swift` 在 build identity 三条 `NSLog` 之后立即调用 `NSApp.setActivationPolicy(.accessory)`，早于 `installStatusItem()`、`installSearchWindow()` 与 `installGlobalHotkey()`；注释解释了 runtime activation policy 与 plist `LSUIElement` 的取舍。
- `applicationDidFinishLaunching` 末尾不再自动 `showSettings(nil)`；菜单栏 status item 成为默认 discovery 入口。
- `applicationShouldHandleReopen` 保留为双击已运行 bundle 的 fallback，仍会在无可见窗口时打开设置窗口。
- `scripts/package-app.sh` 继续写入 `LSUIElement=false`，并注释说明 menubar-agent 行为由 runtime `.accessory` 控制；如果未来改 plist，需要同步撤掉 runtime 调用并更新 L1/L2 文档。
- `docs/release_checklist.md`、`docs/install.md`、`docs/known_issues.md`、`docs/manual_test.md` 已同步 L1 no Dock / 菜单栏主入口 / 退出路径 / 手测矩阵。
- L1 没有提前实现 Dock 显示开关、菜单栏复杂状态增强或单实例防护；这些仍分别属于 L2、L3、L4。

自动化验证：

- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox` 通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest` 通过，结果 `209/209`。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox` 通过，并生成 `dist/SwiftSeek.app`。
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 显示 `LSUIElement => false`、`GitCommit => d5cad2b`、`CFBundleIdentifier => com.local.swiftseek`。
- `plutil -lint dist/SwiftSeek.app/Contents/Info.plist` 通过。
- `codesign -dv --verbose=2 dist/SwiftSeek.app` 显示 `Identifier=com.local.swiftseek`、`Signature=adhoc`、`TeamIdentifier=not set`。
- `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns` 存在，大小 273908 bytes，`file` 显示 Mac OS X icon / `ic04` type。

未在本沙箱执行的验证：

- 真实 GUI Dock 可见性检查。
- 菜单栏图标点击、搜索/设置前置、菜单栏退出和全局热键手测。

这些 GUI 项已写入 `docs/manual_test.md` §33y 与 `docs/release_checklist.md` §5b，发布前仍必须在真实 macOS GUI 环境中手动执行。

## 当前验收要求

下一次 Codex 验收应检查 L2：Dock 显示开关与激活策略稳定化。

L2 验收时至少检查：

- 新安装默认仍是 no Dock 菜单栏 agent。
- 设置页能看到并修改 Dock 可见性选项。
- 设置值能持久化；若声明重启生效，则 UI 和文档都明确提示；若声明实时生效，则真实行为必须匹配。
- no Dock 与 Dock visible 两种模式下，菜单栏搜索、菜单栏设置、菜单栏退出、全局热键均可用。
- 设置窗口 / 搜索窗口在两种模式下都能前置。
- `docs/install.md`、`docs/manual_test.md`、`docs/release_checklist.md`、`docs/known_issues.md` 已同步 L2。
- 没有提前实现 L3 菜单栏复杂状态或 L4 单实例防护。

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
