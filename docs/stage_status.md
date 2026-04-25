# SwiftSeek Stage Status

本文件是当前活跃轨道的权威状态。历史轨道的 `PROJECT COMPLETE` 只代表对应轨道完成，不会传递到新轨道。

## 当前活跃轨道

- 当前活跃轨道：`everything-menubar-agent`
- 当前阶段：`L3`
- 当前状态：L2 已通过 Codex 验收；L3 待 Claude 执行
- 状态日期：2026-04-26

## 历史归档轨道

- `v1-baseline`：P0-P6，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-alignment`：E1-E5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-performance`：F1-F5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-footprint`：G1-G5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-usage`：H1-H5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-ux-parity`：J1-J6，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-productization`：K1-K6，已归档，历史上已拿到 `PROJECT COMPLETE`

## 新轨道立项依据

`everything-productization` 已补齐可重复 `.app` 打包、build identity、安装/升级/回滚文档、诊断与 release gate。但当前真实代码和脚本仍显示 SwiftSeek 的产品形态是普通 Dock App：

- `scripts/package-app.sh` 写入 `LSUIElement=false`，打包出的 `SwiftSeek.app` 会常驻 Dock。
- `AppDelegate.installStatusItem()` 已安装 `NSStatusItem`，菜单栏已有"搜索…"、"设置…"、"索引状态"、"退出 SwiftSeek"，但它仍是辅助入口，不是主入口。
- `AppDelegate.applicationShouldHandleReopen` 与 `docs/release_checklist.md` 仍依赖 Dock reopen 路径；隐藏 Dock 后这条路径不再存在。
- `SearchWindowController.show()` 与 `AppDelegate.showSettings()` 都依赖 `NSApp.activate(ignoringOtherApps:)` 前置窗口，必须在 `LSUIElement` / `.accessory` 模式下重新验证。
- 隐藏 Dock 后，退出路径必须从 Dock 右键迁移到菜单栏 Quit / 热键 / 文档化 fallback。
- 当前没有单实例保护；菜单栏 agent 形态下，多 bundle / stale bundle / 多实例更容易造成用户混淆。

因此新轨道命名为 `everything-menubar-agent`：目标是把 SwiftSeek 从"带 Dock 的普通 App"推进到"菜单栏常驻工具 / tray-like agent"，而不是继续扩展搜索功能。

## 当前轨道目标

`everything-menubar-agent` 要在不做正式签名 / 公证、不使用 private API、不重写窗口系统的前提下，完成：

- 默认隐藏 Dock 图标
- 菜单栏 status item 成为主入口
- 搜索、设置、退出和全局热键在无 Dock 模式下可靠
- Dock 显示可恢复或至少有清晰的恢复策略
- 菜单栏状态足够表达当前索引 / 构建 / DB 简况
- 菜单栏 agent 形态下的多实例 / stale bundle 风险可检测、可解释、可收口

## 已通过阶段：L1

### 阶段目标

让 SwiftSeek 默认以菜单栏工具方式运行，不常驻 Dock，并确保最小可用入口链路成立。

### L1 必须完成

- 选择并落地默认隐藏 Dock 的实现方案：
  - 优先评估 `NSApp.setActivationPolicy(.accessory)`；
  - 或在 package 时把 `LSUIElement` 改为 `true`；
  - 必须说明取舍。
- 菜单栏 status item 必须成为主入口。
- 以下入口必须可用：
  - 菜单栏"搜索…"
  - 菜单栏"设置…"
  - 菜单栏"退出 SwiftSeek"
  - 全局热键搜索
- 设置窗口和搜索窗口打开时必须能前置。
- 更新 package / Info.plist / activation policy 相关文档与 release checklist。
- 增加 L1 手测记录：
  1. package app
  2. 启动后 Dock 不出现 SwiftSeek 图标
  3. 菜单栏图标存在
  4. 菜单栏打开搜索成功
  5. 菜单栏打开设置成功
  6. 全局热键打开搜索成功
  7. 菜单栏退出可正常退出

### L1 禁止事项

- 不做 Dock 显示开关
- 不做单实例保护
- 不做正式 Apple Developer ID 签名 / notarization / DMG
- 不重写搜索窗口或设置窗口系统
- 不提前扩展菜单栏复杂功能
- 不修改搜索、索引、DB schema 或业务逻辑

### L1 完成判定标准

只有同时满足以下条件，L1 才能提交 Codex 验收：

- 打包后的 `SwiftSeek.app` 默认不显示 Dock 图标。
- 菜单栏 status item 存在且是可发现的主入口。
- 菜单栏搜索、菜单栏设置、菜单栏退出和全局热键均能在隐藏 Dock 模式下工作。
- 设置窗口 / 搜索窗口能前置，不出现打开但不可见或在后台的问题。
- release checklist / install / known issues / manual test 中不再把 Dock reopen 当作默认必备入口。
- 文档明确隐藏 Dock 后的退出路径和限制。
- 没有修改超出 L1 的业务能力。

### L1 Codex 验收结论：PASS

- `Sources/SwiftSeek/App/AppDelegate.swift`：`applicationDidFinishLaunching` 在 NSLog build identity 三连之后立即调 `NSApp.setActivationPolicy(.accessory)`，再做 mainMenu / DB / status item / search window / hotkey 安装；删除原 `showSettings(nil)` 自动调用，让菜单栏成为 discovery 入口。`applicationShouldHandleReopen` comment 更新，说明 menubar-agent 形态下仅作为双击 fallback。
- `scripts/package-app.sh`：`LSUIElement` 保留 `false`，附 12 行注释说明 L1 选择运行时 activation policy 而非 plist；改 plist 之前必须先撤运行时调用 + 更新 docs。
- `docs/release_checklist.md`：开头改写为 K6 + L1 双阶段说明；新增 §5b "L1 menubar-agent 形态验证"（必跑 8 项）；§6 把 Dock reopen 改成菜单栏 + applicationShouldHandleReopen fallback；§12 App Icon 不再期望 Dock 显示。
- `docs/install.md`：新增"默认形态：菜单栏常驻工具（L1）"段，写清启动后看到什么、退出路径、找不到菜单栏图标的排查矩阵、双击已运行的 fallback 与 L4 单实例边界。升级流程的 "Dock 右键退出" 改为菜单栏退出。
- `docs/known_issues.md` §1-§3 改写为 L1 已落地；§7-§8 仍标 L2/L3 待做；归档段说明 productization 已完成、L1 在其上切默认形态。
- `docs/manual_test.md` §33y：L1 8 节手测矩阵（Dock 不显示、菜单栏图标、入口三连、热键独立、reopen fallback、反复起停、swift run 路径、Dock 出现 = ❌）。
- Codex 在受限沙箱下完成代码/文档级验收：`swift build --disable-sandbox` 通过，`SwiftSeekSmokeTest` 209/209 通过，`./scripts/package-app.sh --sandbox` 通过，`Info.plist` 显示 `LSUIElement=false` 且 `GitCommit=d5cad2b`，`codesign` 显示 ad-hoc 签名。
- 受限沙箱不能执行真实 GUI Dock 可见性和菜单栏点击模拟；这些仍按 `docs/manual_test.md` §33y 作为每次发布必跑手测。

## 已通过阶段：L2

### 阶段目标

给用户恢复 Dock 图标的能力，并让隐藏 Dock / 显示 Dock 两种模式下的激活、前置、重启提示和设置持久化稳定。

### L2 必须完成

- 新增 Dock 可见性或菜单栏模式设置，默认仍保持 L1 no Dock。
- 设置页增加清晰开关，并说明是否需要重启生效。
- 启动早期根据设置应用 `.accessory` 或 `.regular` activation policy。
- 验证 no Dock 与 Dock visible 两种模式下，菜单栏搜索、菜单栏设置、菜单栏退出、全局热键和窗口前置均可用。
- 更新 install / manual test / release checklist / known issues。

### L2 禁止事项

- 不做单实例 / 多 bundle 防护
- 不做菜单栏复杂状态增强
- 不做正式签名 / notarization / DMG / auto updater
- 不重写搜索窗口或设置窗口系统
- 不修改搜索、索引、DB schema 或业务逻辑

### L2 完成判定标准

只有同时满足以下条件，L2 才能提交 Codex 验收：

- 新安装默认仍是菜单栏 agent / no Dock。
- 用户能在设置页看到并修改 Dock 可见性选项。
- 设置持久化且重启后生效；如果实时切换被声明支持，真实行为必须匹配。
- no Dock 与 Dock visible 两种模式下的搜索、设置、退出、热键和窗口前置均通过。
- 文档同步，不再把 Dock 显示开关写成未完成项。
- 没有提前实现 L3/L4。

### L2 Codex 验收结论：PASS

- `Sources/SwiftSeekCore/SettingsTypes.swift`：新增 `SettingsKey.dockIconVisible`（DB key `dock_icon_visible`），值 `"1"` = 显示 Dock，`"0"` / 缺失 = L1 默认 no Dock；`Database` extension 加 `getDockIconVisible() throws -> Bool` / `setDockIconVisible(_ visible: Bool) throws`，与 hidden / launch-at-login 等已有 settings 同模式。
- `Sources/SwiftSeek/App/AppDelegate.swift`：`applicationDidFinishLaunching` 顺序固定为 — 先 `.accessory` 兜底 → DB 打开 → 读 `getDockIconVisible()` → 若为 true 切 `.regular` 并 NSLog `Dock icon visible (user preference)`，否则 NSLog `Dock icon hidden (L1 default)`；读失败保持 L1 默认 + NSLog 错误。声明实时切换不可靠：runtime `.regular` ↔ `.accessory` transition 在 ad-hoc 包上不稳定，因此 L2 是"持久化设置 + 重启生效"路径。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `GeneralPane`：新增 "在 Dock 显示 SwiftSeek 图标（菜单栏入口仍保留）" 复选框 + 多行 note；`reflectDockIconState()` 比较 intent 与 `NSApp.activationPolicy()`，未重启时显示 `⚠️` 警告，已对齐时显示 `✓` 确认；`onDockIconToggle(_:)` 持久化失败时弹 NSAlert + 复位复选框。GeneralPane root view 高度从 360 提到 440 容纳新行。
- `Sources/SwiftSeekSmokeTest/main.swift`：3 个 L2 用例（默认 false / setter+getter round-trip / DB reopen 后 persist）。SmokeTest 总数 209 → 212。
- `docs/install.md`：默认形态段补 "L2 让 Dock 图标重新显示" 子段，4 步流程 + "为什么需要重启而不是实时切" 解释。
- `docs/release_checklist.md`：新增 §5c "L2 Dock 显示开关验证"（10 项必跑）。
- `docs/known_issues.md` §7 改写为 L2 已落地，写明持久化 key、应用时机、为什么不做 live transition、release_checklist §5c 强制手测。
- `docs/manual_test.md` §33z：8 节 L2 手测矩阵（全新 DB 默认 / 切到 Dock visible / Dock visible 入口 / 切回 no Dock / 反复切换稳定性 / DB 异常值 fallback / 与其他设置无干扰 / 边界）。
- Codex 在受限沙箱下完成代码/文档级验收：`swift build --disable-sandbox` 通过，`SwiftSeekSmokeTest` 212/212 通过，`./scripts/package-app.sh --sandbox` 通过，`Info.plist` 显示 `LSUIElement=false` 且 `GitCommit=5ff1334`，`codesign` 显示 ad-hoc 签名。
- 受限沙箱不能执行真实 GUI Dock visible/hidden 跨启动切换、菜单栏点击、设置 note 文本和跨模式入口验证；这些仍按 `docs/manual_test.md` §33z 与 `docs/release_checklist.md` §5c 作为每次发布必跑手测。

## 当前阶段：L3

### 阶段目标

让菜单栏成为真正主入口：用户不用先打开设置窗口，也能快速确认当前构建、索引状态、索引模式、root 健康和 DB 简况，并能直达现有最近 / 常用能力。

### L3 必须完成

- 增强菜单栏菜单结构，保留搜索 / 设置 / 索引状态 / 退出，同时新增 build identity、index mode、root 简况、DB 大小等只读状态。
- 增强 status item tooltip，短文本展示版本 / commit、索引状态、索引模式和 root 简况。
- 菜单打开前或状态变化时刷新菜单状态；读取失败时显示可理解的降级文案，不 crash。
- 如接入最近打开 / 常用，只能基于 SwiftSeek 内部 `file_usage` 表，不读系统全局历史。
- 更新 install / manual test / release checklist / known issues。

### L3 禁止事项

- 不做单实例 / 多 bundle 防护
- 不做正式签名 / notarization / DMG / auto updater
- 不做完整菜单栏 dashboard 或复杂弹窗控制台
- 不新增全文搜索、AI、OCR、云盘一致性、Finder 插件或系统全局历史读取
- 不提前实现 L4

### L3 完成判定标准

只有同时满足以下条件，L3 才能提交 Codex 验收：

- 菜单栏搜索、设置、退出和 L1/L2 行为不回归。
- tooltip 与菜单能展示 build identity、索引状态、索引模式、root/DB 简况。
- 索引状态变化能更新到菜单或 tooltip。
- 状态读取失败有降级文案，不破坏主入口。
- 最近 / 常用若实现，必须受 usage history 数据和隐私设置约束。
- 文档同步，且没有提前实现 L4。

## 后续阶段索引

- L1：默认隐藏 Dock + 菜单栏主入口
- L2：Dock 显示开关与激活策略稳定化
- L3：菜单栏菜单增强与状态可见性
- L4：单实例 / 多 bundle 防护与最终收口

完整任务书见：`docs/everything_menubar_agent_taskbook.md`。
