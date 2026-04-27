# SwiftSeek Stage Status

更新时间：2026-04-27

## 当前活跃轨道

- 当前活跃轨道：`everything-dockless-hardening`
- 当前阶段：`N4`
- 当前状态：N4 实现已就位，待 Codex 最终验收（PROJECT COMPLETE 候选）
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

- `scripts/package-app.sh` N2 起默认生成 agent 包并写 `LSUIElement=true`；显式 `--dock-app` 生成普通 Dock App 包并写 `LSUIElement=false`。
- `Sources/SwiftSeek/App/AppDelegate.swift` 启动时先调用 `NSApp.setActivationPolicy(.accessory)`，但 DB 打开后读取 `dock_icon_visible`；如果该设置为 `1`，会调用 `NSApp.setActivationPolicy(.regular)` 并让 Dock 出现。
- `Sources/SwiftSeekCore/SettingsTypes.swift` 已有 `SettingsKey.dockIconVisible = "dock_icon_visible"`，默认缺失/`0` 为隐藏 Dock，`1` 为显示 Dock。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 已有“在 Dock 显示 SwiftSeek 图标”复选框，并明确切换需重启；N1 已让 About / Diagnostics 暴露完整 Dock 状态，但当前还没有一键恢复菜单栏模式。
- `Sources/SwiftSeekCore/Diagnostics.swift` 已显示 build identity、bundle、binary、DB、Launch at Login、Reveal target，并已在 N1 增加 Dock 状态块：persisted `dock_icon_visible`、intended mode、effective activation policy、Info.plist `LSUIElement`、bundle path、executable path。
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

### N1 验收结论：PASS

- `Sources/SwiftSeekCore/Diagnostics.swift`：新增 `DockStatusReport { activationPolicyLabel, lsUIElement: Bool? }` 与 `DockStatusProbe` typealias；`snapshot(...)` 增加 `dockStatus: DockStatusProbe? = nil` 可选参数；输出新增 "Dock 状态（N1）：" 块，含 persisted `dock_icon_visible`、intended mode、effective activation policy、Info.plist LSUIElement、bundle path、executable path；headless 路径渲染 `—（headless ...）` 占位，不会假装有真值。
- `Sources/SwiftSeek/App/AppDelegate.swift`：新增 4 个静态 helper：`lsUIElementValueLabel()`（log 友好字符串）、`lsUIElementBool()`（Bool? for probe）、`activationPolicyLabel()`、`currentDockStatusReport()`；`applicationDidFinishLaunching` 启动日志改为统一 `Dock — Info.plist LSUIElement=...; persisted dock_icon_visible=...; chosen activation policy=...` 一行；`dock_icon_visible=1` 时多打一行明确说明 Dock 是用户设置导致并给出关闭路径；DB 读失败 / 无 DB 时也保留对应分支日志，不静默。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `AboutPane.buildDiagnostics()` 把 `dockStatus: { AppDelegate.currentDockStatusReport() }` 传入，让"复制诊断信息"包含 live activation policy + Info.plist LSUIElement。
- `Sources/SwiftSeekSmokeTest/main.swift`：6 个 N1 用例（fresh DB headless / `dock_icon_visible=1` 翻转 / 带 probe accessory+false / 带 probe regular+true / probe LSUIElement=nil → "—（Info.plist 未声明该 key）" / `DockStatusReport` 值语义）。SmokeTest 总数 256 → 262。
- N1 严格不改 `scripts/package-app.sh`（`LSUIElement=false` 不变）、不删 `dock_icon_visible` 设置、不强改用户 DB；只是诊断暴露阶段。
- Codex 验收确认：build OK；SmokeTest 262/262；package-app OK；打包产物 `GitCommit=9741d52`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`；`plutil -lint` OK；`codesign -dv` 显示 `Signature=adhoc`。
- 受限沙箱不能做 GUI 启动 Console 手测；该项保留到 N4 release-time gate。

## N2：默认无 Dock 的打包与启动策略硬化

### N2 round 1 验收结论：REJECT

- `scripts/package-app.sh`:
  - 新增 `--dock-app` flag（与 `--no-dock` / `--agent` 别名同义切换）。默认未带 flag → `package_mode=agent`；带 `--dock-app` → `package_mode=dock_app`。
  - 把 `LSUIElement` 写入 plist 时使用 `$LS_UI_ELEMENT_VALUE`（`<true/>` for agent, `<false/>` for dock_app）。
  - 启动时打印 banner 三行：`N2 mode=...`、`LSUIElement=...`、`version=... commit=... build=... bundle_id=...`。
  - plist 写完后做断言：`plutil -p` grep `"LSUIElement" => $LS_UI_ELEMENT_HUMAN`，不一致 exit 4。
  - `=== done ===` 段额外打印：`mode`、`LSUIElement`、`commit`、`bundle id`、`bundle path`、`launch` 命令；并按 mode 给出对应 Dock 期望文案（agent 提醒"如果 dock_icon_visible=1 仍会出 Dock，是用户设置导致"，dock_app 提醒 Dock 应出现）。
  - 帮助文本（`-h`/`--help`）已更新。
  - `--sandbox` / `--no-sign` 与 mode flag 可组合。
- AppDelegate / Diagnostics：N1 行为不变；启动日志 `Dock — Info.plist LSUIElement=...` 现在会读到 N2 写入的真实值（agent 包打 `LSUIElement=true`，dock_app 包打 `LSUIElement=false`）。
- `docs/install.md`：默认形态段 + 一条命令打包段 + 实现方式段 同步 N2；解释 plist 与 runtime 双层来源以及"runtime 仍是真正控制源"。
- `docs/release_checklist.md` §3：覆盖默认 agent 包断言 + `--dock-app` 包断言；§4 加 `LSUIElement` 字段对应预期 mode。
- `docs/known_issues.md` §2 改写为 N2 已硬化默认包；§3 收尾改为指向 N3/N4。
- 严格不改 `dock_icon_visible` 设置语义；不强改用户 DB；不做 N3 一键自救 UI；不动 release gate header（留给 N4）。
- 验证：受限沙箱下 `swift build` OK；SmokeTest 262/262 不变；默认 `./scripts/package-app.sh --sandbox` → `LSUIElement=true` 断言通过；`./scripts/package-app.sh --sandbox --dock-app` → `LSUIElement=false` 断言通过；`plutil -lint` OK；`codesign -dv` 显示 `Signature=adhoc`。
- GUI 真实启动 Dock 可见性 / 菜单栏入口 / 设置 / 全局热键 / 退出 仍为 N4 release-time 手测，本阶段不假装已验证。
- 阻塞项：`./scripts/package-app.sh --help` 未列出 N2 alias `--no-dock` / `--agent`，不满足 N2 help text 交付要求。
- 必须修复：补齐 help 文本中的 `--no-dock` / `--agent` 说明；同步把 `docs/release_checklist.md` §2 smoke 基准从 `256` 改为当前 `262`。

### N2 round 2 验收结论：PASS

- `scripts/package-app.sh --help` 已列出 `--dock-app`、`--no-dock`、`--agent`、`--sandbox`、`--no-sign`，并显示 mode flag 说明。
- `docs/release_checklist.md` §2 smoke 基准已更新为 `262`。
- 默认 `./scripts/package-app.sh --sandbox`：`N2 mode=agent`、`LSUIElement=true`、`GitCommit=a74df5a`、`LSUIElement assertion OK (=true, mode=agent)`。
- `./scripts/package-app.sh --sandbox --dock-app`：`N2 mode=dock_app`、`LSUIElement=false`、`LSUIElement assertion OK (=false, mode=dock_app)`。
- `swift build` 通过；`SwiftSeekSmokeTest` 262/262；`plutil -lint` OK；`codesign -dv` 显示 `Signature=adhoc`。
- HEAD `a74df5a` 未修改 `Sources/`，没有改 `dock_icon_visible` 默认语义，没有强制 DB rewrite，没有实现 N3 一键恢复 UI。

## N3：设置页 Dock 模式修复与用户自救路径

### N3 round 1 验收结论：PASS

- 新增 `Sources/SwiftSeekCore/DockSettingsState.swift`（纯函数 / AppKit-free）：`Status` 结构（intent / effectivePolicy / plist / bundle / executable / divergenceWarning / summaryLine）+ `compose(...)` + `detailText(...)`。字段名与 `Diagnostics.snapshot` 的 N1 "Dock 状态（N1）：" 块同源词汇。
- 偏离判定：`activationPolicyLabel == "regular" && !dock_icon_visible` → 多打 ⚠️ 解释 "已是 0，下次启动回 agent，可点恢复按钮"；`activationPolicyLabel == "accessory" && dock_icon_visible` → ⚠️ "重启后生效"。两端匹配时无 warning。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `GeneralPane`：在 dockIconNote 之后新增 `dockDetailLabel`（等宽多行）+ `dockRestoreBtn`（"恢复菜单栏模式（隐藏 Dock）"）；`reflectDockIconState()` 调 `DockSettingsState.compose(...)` + `.detailText(...)` 写入 label，并按是否需要自救显示/隐藏按钮（`intent == true || policy == .regular`）；`onDockRestoreMenuBarMode(_:)` 写 `dock_icon_visible=false`，写失败弹 NSAlert，写成功弹"已恢复"提示并指引退出 + 重新打开。Pane 高度 580 → 720。
- `Sources/SwiftSeekSmokeTest/main.swift`：8 个 N3 用例（默认 happy path / `dock_icon_visible=1` 与 accessory 偏离 / `dock_icon_visible=0` 与 regular 偏离 / 双 Dock-visible 一致 / nil policy headless / lsUIElement=nil + live policy 标 "Info.plist 未声明" / `detailText` 多行格式 / `setDockIconVisible(false)` round-trip 自救路径）。SmokeTest 总数 262 → 270。
- `docs/install.md`：默认形态段补 "N3 一键恢复菜单栏模式（隐藏 Dock）" 子段，给完整恢复流程 + `--dock-app` 包识别提示。
- `docs/known_issues.md` §4 改写为 N3 已落地，列字段词汇 / 按钮契约 / 不做 live policy 切换的诚实说明。
- N3 严格不改 N2 包模式策略；不删 `dock_icon_visible`；不静默改用户 DB（按钮的显式 false 写入除外）；不实施 N4 release gate header；不引入 Finder 插件、QSpace 私有 API、URL scheme 猜测或新文件管理器集成 scope。
- 验证：受限沙箱下 `swift build` OK；SmokeTest 270/270；package-app 默认 agent 模式 `LSUIElement=true` OK；`--dock-app` 模式 `LSUIElement=false` OK；`plutil -lint` OK；`codesign -dv` 显示 `Signature=adhoc`。
- GUI 真实点击恢复按钮 / Settings detail 块 / 重启后行为留为 N4 release-time 手测。

## N4：真实 `.app` 手测 gate 与最终收口

### N4 实现已落地（待 Codex 最终验收）

- `docs/release_checklist.md`：
  - header 升级为 "K6 + L1-L4 + M1-M4 + N1-N4 单页"，描述段重写指向 N1-N4 实际行为而非历史声明。
  - 新增 §5g "N1-N4 Dockless hardening 硬 gate"，包含自动化前置 + 6 个 scenario A-F：fresh DB + agent / `dock_icon_visible=1` 旧 DB / N3 一键恢复 / `--dock-app` 包 / stale bundle / 菜单栏 + 热键不回归。每条都有具体期望（Console 日志格式 / Diagnostics 块 / Settings detail 文案）。
- `docs/install.md`：
  - 顶部告示更新为 N1-N4 已落地，指向 "Dock 仍常驻 — 三步定位" 子段。
  - 新增 "Dock 仍常驻 — 三步定位" 子段：Step 1 看启动日志矩阵（4 行表格区分用户设置 / 包体 / stale bundle / 异常分支）、Step 2 用户设置导致 → N3 自救、Step 3 stale bundle 排查、Step 4 包体模式导致 → 重打 agent 包。
- `docs/known_issues.md`：
  - §1 改写为 "用户反馈 Dock 仍常驻（N1-N4 已硬化）"，列 N1-N4 各阶段交付。
  - "默认隐藏 Dock 图标" 子段同步 N2 默认 `LSUIElement=true` 事实，删去旧 "LSUIElement 一直是 false" 错误叙述。
- `docs/architecture.md`：尾部新增 "everything-dockless-hardening 收口（N1-N4）" 段，按 N1/N2/N3/N4 列每阶段交付 + 当前轨道明确不做。
- `README.md`：当前能力 "菜单栏 agent" 行更新为 L1-L4 历史 + N1-N4 已硬化；当前限制段同步 N1-N4 事实；当前进度 N1-N3 PASS + N4 等待 PROJECT COMPLETE。
- `docs/stage_status.md`（本文件）N4 实现已落地段 + 状态翻为"N4 实现已就位，待 Codex 最终验收（PROJECT COMPLETE 候选）"。
- 不引入新代码（Sources/ 不变）；smoke 总数仍为 270；package-app 行为不变；ResultAction / Diagnostics / DockSettingsState 全部保留 N1-N3 PASS 时的契约。
- 验证：受限沙箱下 `swift build` OK；SmokeTest 270/270；默认 `package-app.sh --sandbox` 与 `--dock-app` 包都通过；`plutil -lint` OK；`codesign -dv` 显示 `Signature=adhoc`。
- GUI 真实 .app Scenario A-F 手测仍按 release_checklist §5g 与 manual_test §33ad 作为每次发布手测；N4 不假装已自动验证 GUI。

如 Codex 接受 N4，本轨道 `everything-dockless-hardening` 满足 `PROJECT COMPLETE` 条件：N1 暴露根因 + N2 硬化默认包 + N3 设置页自救 + N4 release gate 收口；K1-K6 / L1-L4 / M1-M4 不回退。

## 后续阶段概览

（无；本轨道 N4 是最终阶段。）
