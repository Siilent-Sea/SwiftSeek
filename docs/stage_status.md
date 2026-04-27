# SwiftSeek Stage Status

更新时间：2026-04-27

## 当前活跃轨道

- 当前活跃轨道：`everything-dockless-hardening`
- 当前阶段：`N1`
- 当前状态：N1 实现已就位，待 Codex 验收
- 触发原因：用户真实反馈 `everything-menubar-agent` 完成后，打包运行的 SwiftSeek 仍然常驻 Dock。历史文档中的“默认 no Dock”不能再作为事实依据，必须按当前代码和真实 `.app` 验收。

## 历史归档轨道

- `v1-baseline`：已归档，历史 `PROJECT COMPLETE`
- `everything-alignment`：已归档，历史 `PROJECT COMPLETE`
- `everything-performance`：已归档，历史 `PROJECT COMPLETE`
- `everything-footprint`：已归档，历史 `PROJECT COMPLETE`
- `everything-usage`：已归档，历史 `PROJECT COMPLETE`
- `everything-ux-parity`：已归档，历史 `PROJECT COMPLETE`
- `everything-productization`：已归档，历史 `PROJECT COMPLETE`
- `everything-menubar-agent`：已归档，历史 `PROJECT COMPLETE`
- `everything-filemanager-integration`：已归档，历史 `PROJECT COMPLETE`

这些归档结论只说明对应历史轨道完成，不会自动传递给 `everything-dockless-hardening`。

## 新轨道目标

`everything-dockless-hardening` 只处理 Dock 仍常驻这一类产品形态硬化问题：

- 让默认交付的 `.app` 真正偏向 no-Dock / menu bar agent。
- 解释并暴露当前 Dock 可见性的真实来源：`LSUIElement`、runtime activation policy、`dock_icon_visible`、bundle path、stale bundle。
- 让用户在被旧设置污染时有可见自救路径，不需要手工改 SQLite。
- 把 Dock 是否隐藏从“文档声明”升级为真实 `.app` release gate。

## 当前代码审计结论

- `scripts/package-app.sh` 当前仍生成 `LSUIElement=false` 的 `Info.plist`，包体层面仍是普通 App。
- `Sources/SwiftSeek/App/AppDelegate.swift` 启动时先调用 `NSApp.setActivationPolicy(.accessory)`，但 DB 打开后读取 `dock_icon_visible`；如果该设置为 `1`，会调用 `NSApp.setActivationPolicy(.regular)` 并让 Dock 出现。
- `Sources/SwiftSeekCore/SettingsTypes.swift` 已有 `SettingsKey.dockIconVisible = "dock_icon_visible"`，默认缺失/`0` 为隐藏 Dock，`1` 为显示 Dock。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 已有“在 Dock 显示 SwiftSeek 图标”复选框，并明确切换需重启；但当前没有一键恢复菜单栏模式、没有完整 Dock 状态诊断，也不足以解释旧 DB / 测试状态污染。
- `Sources/SwiftSeekCore/Diagnostics.swift` 已显示 build identity、bundle、binary、DB、Launch at Login、Reveal target 等，但还没有专门的 Dock 状态块：persisted `dock_icon_visible`、effective activation policy、Info.plist `LSUIElement`。
- `docs/release_checklist.md` 已有 no-Dock 手测，但它仍基于 L1/L2 的历史实现，不足以覆盖 fresh DB、`dock_icon_visible=1` 旧 DB、package plist 和 stale bundle 的硬验收组合。

## N1：Dock 常驻根因审计与诊断暴露

### 阶段目标

先让用户和开发者能明确看到“为什么当前会显示 Dock”，而不是直接重做 package 策略。N1 是诊断和证据阶段，不负责最终改造默认包体。

### 必须做

- 审计并记录所有 Dock 相关路径：
  - `NSApp.setActivationPolicy`
  - `dock_icon_visible`
  - `LSUIElement`
  - package `Info.plist`
  - Settings UI
  - Diagnostics / About
- About / Diagnostics 增加 Dock 状态块，至少包含：
  - persisted `dock_icon_visible`
  - intended mode
  - effective activation policy
  - Info.plist `LSUIElement`
  - bundle path
  - executable path
- 启动日志打印 Dock mode 判断：
  - persisted setting
  - chosen activation policy
  - Info.plist `LSUIElement`
- 如果 `dock_icon_visible=1`，日志必须明确说明 Dock 出现是用户设置导致。
- smoke 覆盖：
  - settings default false
  - set true / false round-trip
  - diagnostics 字符串包含 Dock mode 关键字段

### 当前阶段禁止事项

- 不改 package 默认策略。
- 不把 `LSUIElement` 直接改成 `true`。
- 不移除 Dock 设置。
- 不强制改用户 DB。
- 不提前做 N2/N3/N4。
- 不声称 Dock 已经稳定隐藏。

### 完成判定标准

- `docs/codex_acceptance.md` 能记录 N1 的真实验收结果。
- About / Diagnostics 和启动日志能解释 Dock 是由 plist、runtime policy 还是 `dock_icon_visible` 引起。
- fresh DB 和 `dock_icon_visible=1` DB 的差异可被诊断文字明确区分。
- smoke / 可自动化测试覆盖新增诊断字段。
- 文档同步说明 N1 只是诊断暴露，不是假装最终修复。

### N1 实现已落地（待 Codex 验收）

- `Sources/SwiftSeekCore/Diagnostics.swift`：新增 `DockStatusReport { activationPolicyLabel, lsUIElement: Bool? }` 与 `DockStatusProbe` typealias；`snapshot(...)` 增加 `dockStatus: DockStatusProbe? = nil` 可选参数；输出新增 "Dock 状态（N1）：" 块，含 persisted `dock_icon_visible`、intended mode、effective activation policy、Info.plist LSUIElement、bundle path、executable path；headless 路径渲染 `—（headless ...）` 占位，不会假装有真值。
- `Sources/SwiftSeek/App/AppDelegate.swift`：新增 4 个静态 helper：`lsUIElementValueLabel()`（log 友好字符串）、`lsUIElementBool()`（Bool? for probe）、`activationPolicyLabel()`、`currentDockStatusReport()`；`applicationDidFinishLaunching` 启动日志改为统一 `Dock — Info.plist LSUIElement=...; persisted dock_icon_visible=...; chosen activation policy=...` 一行；`dock_icon_visible=1` 时多打一行明确说明 Dock 是用户设置导致并给出关闭路径；DB 读失败 / 无 DB 时也保留对应分支日志，不静默。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `AboutPane.buildDiagnostics()` 把 `dockStatus: { AppDelegate.currentDockStatusReport() }` 传入，让"复制诊断信息"包含 live activation policy + Info.plist LSUIElement。
- `Sources/SwiftSeekSmokeTest/main.swift`：6 个 N1 用例（fresh DB headless / `dock_icon_visible=1` 翻转 / 带 probe accessory+false / 带 probe regular+true / probe LSUIElement=nil → "—（Info.plist 未声明该 key）" / `DockStatusReport` 值语义）。SmokeTest 总数 256 → 262。
- N1 严格不改 `scripts/package-app.sh`（`LSUIElement=false` 不变）、不删 `dock_icon_visible` 设置、不强改用户 DB；只是诊断暴露阶段。
- 受限沙箱下 build OK；SmokeTest 262/262；package-app 仍可重复跑通。

## 后续阶段概览

- `N2`：默认无 Dock 的打包与启动策略硬化。
- `N3`：设置页 Dock 模式修复与用户自救路径。
- `N4`：真实 `.app` 手测 gate 与最终收口。
