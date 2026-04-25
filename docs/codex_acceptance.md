# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K2`
- 当前阶段验收结论：K1 已 `PASS`，等待 K2 实现
- 当前正式验收 session：尚未创建
- 日期：2026-04-25

### 当前审计结论
K1 round 1 已通过。结论基于当前源码、当前文档和提交 `d890c81` 的实际核对，而不是沿用旧轨道结论。

本轮确认成立的事实：
- `Sources/SwiftSeekCore/BuildInfo.swift` 新增运行时 build identity surface：`CFBundleShortVersionString` / `GitCommit` / `BuildDate`，并提供 `summary`、`multilineSummary`、bundle path、binary path 和 fallback。
- `Sources/SwiftSeek/App/AppDelegate.swift` 在 `applicationDidFinishLaunching` 的最前面打印三行 build identity，再继续 menu / DB 初始化。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 保持 J1/J6 生命周期修复不变：
  - `windowShouldClose(_:)` 仍是 hide-only close
  - `applicationShouldHandleReopen` 路径未回退
  - tab 记忆仍是 KVO `selectedTabViewItemIndex`，没有回退到非法 `tabView.delegate`
- About 面板顶部现在显示 `BuildInfo.summary`；诊断块前置 build identity；新增“复制诊断信息”按钮。
- `docs/manual_test.md` 已把设置窗口 reopen / Dock reopen / 10x close-show / 20x tab switch 和 stale bundle 自检写成 release gate。
- `scripts/build.sh` 已移除过期的 “schema v3” 文案，并诚实声明 `.app` packaging 属于 K2。

本轮未能在当前 Codex 沙箱内直接复跑 `swift build --disable-sandbox` 与 `swift run --disable-sandbox SwiftSeekSmokeTest`，但阻塞原因为环境：
- `~/.cache/clang/ModuleCache` 在当前沙箱不可写
- 当前 CLT/SDK 存在版本不匹配：SDK 为 `Swift 6.3.0`，编译器为 `Swift 6.3.1`

这两个问题阻止本地复编译，不构成 K1 代码本身的 blocker；K1 任务书也允许在命令不可运行时明确记录环境阻塞原因。

## 当前验收要求
K2 完成后，Codex 才能给出下一轮 `PASS` 或 `REJECT`。当前不允许因为 K1 已通过就把后续产品化阶段视为自动完成。

验收时必须检查：
- `.app` package 脚本能从 fresh clone 稳定生成 bundle。
- `Info.plist` / `AppIcon.icns` / ad-hoc codesign 进入可重复流程，而不是依赖手工注入。
- `dist/SwiftSeek.app` 或等价输出路径明确。
- `open` 启动、`codesign -dv`、`plutil`、bundle 结构检查都可验证。
- K1 的 build identity 和 settings release gate 不回退。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`

## 轨道切换说明
`everything-productization` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
