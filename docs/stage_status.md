# SwiftSeek Stage Status

本文件是当前活跃轨道的权威状态。历史轨道的 `PROJECT COMPLETE` 只代表对应轨道完成，不会传递到新轨道。

## 当前活跃轨道

- 当前活跃轨道：`everything-filemanager-integration`
- 当前阶段：`M4`
- 当前状态：M4 实现已就位，待 Codex 最终验收（PROJECT COMPLETE 候选）
- 状态日期：2026-04-26

## 历史归档轨道

- `v1-baseline`：P0-P6，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-alignment`：E1-E5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-performance`：F1-F5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-footprint`：G1-G5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-usage`：H1-H5，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-ux-parity`：J1-J6，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-productization`：K1-K6，已归档，历史上已拿到 `PROJECT COMPLETE`
- `everything-menubar-agent`：L1-L4，已归档，历史上已拿到 `PROJECT COMPLETE`

## 新轨道立项依据

`everything-menubar-agent` 已完成 no Dock 菜单栏工具形态、Dock 显示开关、菜单栏状态和单实例防护。但当前真实代码仍把“显示位置”能力固定在 Finder：

- `Sources/SwiftSeekCore/ResultAction.swift` 的动作仍命名为 `revealInFinder`。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift` 对 `.revealInFinder` 直接调用 Finder 专用 API：`NSWorkspace.shared.activateFileViewerSelecting([url])`。
- `Sources/SwiftSeek/UI/SearchViewController.swift` 的按钮和右键菜单仍写死“在 Finder 中显示”。
- `Sources/SwiftSeekCore/SettingsTypes.swift` 只有 hidden/search limit/hotkey/index mode/usage/query history/Dock 等设置，没有 `reveal_target_type`、`reveal_custom_app_path`、`reveal_external_open_mode`。
- `SettingsWindowController` 的常规设置页没有“显示位置 / Reveal Target”配置 UI。
- release checklist 和 manual test 仍只覆盖 Finder reveal，没有 QSpace / custom app / fallback / item vs parentFolder 语义验证。

因此新轨道命名为 `everything-filemanager-integration`：目标是把 SwiftSeek 的 Reveal / Show action 从 Finder-only 扩展为可配置 Finder / QSpace / 自定义文件管理器集成，同时保持稳健 fallback 和清晰语义。

## 当前轨道目标

`everything-filemanager-integration` 要在不使用 QSpace 私有 API、不假设未知 bundle id / URL scheme、不读取系统隐私数据的前提下，完成：

- 默认仍使用 Finder，保持向后兼容
- 设置页支持选择自定义 `.app`，例如 `/Applications/QSpace.app`
- 自定义 app 路径、打开模式可持久化
- Finder 模式继续支持选中文件
- 自定义 app 模式使用 macOS 公开 API 打开文件本身或父目录
- 外部 app 不存在 / 被移动 / 打不开时有可见反馈，并 fallback 到 Finder
- 搜索窗口按钮、右键菜单、hint、diagnostics、manual test 与 release gate 同步

## 当前阶段：M1

### 阶段目标

先建立 Reveal Target 数据模型与设置 UI，让用户能在设置里选择 Finder 或自定义文件管理器，并保存目标 app 与打开模式。M1 不替换实际 reveal 动作。

### M1 必须完成

- 新增设置项：
  - `reveal_target_type`
  - `reveal_custom_app_path`
  - `reveal_external_open_mode`
- 推荐类型：
  - `RevealTarget`
  - `RevealTargetType`
  - `ExternalRevealOpenMode`
- 默认：
  - target = Finder
  - open mode 按设计说明选择 `item` 或 `parentFolder`，但必须解释取舍
- 设置页增加 UI：
  - “显示位置” / “Reveal Target”
  - Finder
  - 自定义 App…
  - 选择 App 按钮
  - 当前已选 App 显示名称和路径
  - 打开目标：文件本身 / 父目录
- QSpace 支持方式：
  - 不硬编码未知 bundle id
  - 不假设 URL scheme
  - 支持用户选择 `/Applications/QSpace.app`
  - 若检测到 app 名称包含 QSpace，可在 UI 显示为 QSpace
- 补 smoke：
  - 默认 Finder
  - custom app path round-trip
  - open mode round-trip
  - malformed setting fallback to Finder

### M1 禁止事项

- 不改 `ResultActionRunner` 的实际执行路径
- 不做实际外部 app 打开
- 不用 QSpace 私有 API
- 不硬编码未经验证的 QSpace bundle id 或 URL scheme
- 不改变 Finder reveal 的现有行为
- 不改搜索、索引、DB schema、Run Count、菜单栏 agent 或单实例逻辑

### M1 完成判定标准

只有同时满足以下条件，M1 才能提交 Codex 验收：

- 新设置项和类型存在，默认 Finder 可安全读取。
- 自定义 app path 与 open mode 能通过 DB settings 持久化并 round-trip。
- malformed / missing 设置会 fallback 到 Finder，不会崩。
- 设置页能选择 Finder / 自定义 App，并显示当前选择。
- UI 文案明确：QSpace 通过用户选择 app 支持，不依赖私有协议。
- `ResultActionRunner` 行为仍未替换，M2 才做实际接入。
- SmokeTest 增加对应数据模型测试。

### M1 实现已落地（Codex 验收 PASS）

- `Sources/SwiftSeekCore/SettingsTypes.swift`：新增 `RevealTargetType { .finder, .customApp }`、`ExternalRevealOpenMode { .item, .parentFolder }`、`RevealTarget` 结构（含 `defaultTarget = (.finder, "", .parentFolder)`）；`SettingsKey.revealTargetType / revealCustomAppPath / revealExternalOpenMode`；`Database.getRevealTarget() throws -> RevealTarget` 与 `setRevealTarget(_:)` extension。每个字段独立 fallback：未知 type → `.finder`（保留 customAppPath 不被擦除），未知 openMode → `.parentFolder`，path missing → `""`。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `GeneralPane`：新增 "显示位置" 行（NSPopUpButton：Finder / 自定义 App…）+ "选择 App…" 按钮（NSOpenPanel 限定 `.app`，默认 `/Applications`）+ 当前 app 名称 + 路径 summary（QSpace 名称启发式识别）+ "打开目标" segmented（父目录 / 文件本身）+ 多行 note 解释 Finder 与外部 app 语义差异。Pane 高度 440 → 580 容纳新 4 行。`reflectRevealTargetState()` / `currentRevealTarget()` / `onRevealTargetTypeChanged` / `onRevealOpenModeChanged` / `onPickRevealApp` 处理读写；三条保存失败路径均会 `NSLog` + 弹 `NSAlert`，popup / segmented 失败后回滚到已持久化状态。
- `Sources/SwiftSeekSmokeTest/main.swift`：6 个 M1 用例（fresh DB → Finder/parentFolder/empty / customApp+path+item round-trip / DB reopen 后 persist / malformed type → Finder（保留 path）/ malformed openMode → parentFolder / `defaultTarget` 常量）。SmokeTest 总数 223 → 229。
- `docs/known_issues.md` §2 改写为 M1 已落地，列 key、UI 元素、QSpace 启发式识别、M2 才接入运行时。
- `ResultActionRunner` 与 UI 文案 / 实际 reveal 路径仍是 Finder-only，M2 接入。
- Round 2 受限沙箱下 build OK；SmokeTest 229/229；package-app OK；打包产物 `GitCommit=fdae471`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`、adhoc codesign OK。

## 当前阶段：M2

### 阶段目标

把 M1 的 Reveal Target 配置接入实际“显示位置”动作，让 Finder 模式继续保留选中文件行为，自定义 App 模式用公开 macOS API 打开目标 URL，并在外部 app 失效时给出可见反馈后 fallback 到 Finder。M2 不负责动态按钮文案、diagnostics 和完整 release gate 收口，这些留给 M3。

### M2 必须完成

- `ResultActionRunner` 或最小必要 helper 读取 `Database.getRevealTarget()`。
- Finder 模式继续调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`。
- custom app 模式校验 `customAppPath` 非空、存在且是 `.app`。
- 按 `ExternalRevealOpenMode.item` / `.parentFolder` 解析目标 URL。
- 使用公开 `NSWorkspace` API 将目标 URL 交给自定义 `.app`。
- app path 空、失效、非 `.app` 或打开失败时：用户可见反馈 + `NSLog` + fallback 到 Finder。
- reveal / show 不增加 `file_usage.open_count`。
- 补 M2 纯 helper smoke；真实外部 app 打开写入手测。

### M2 禁止事项

- 不使用 QSpace 私有 API。
- 不硬编码未知 QSpace bundle id。
- 不假设 QSpace URL scheme。
- 不做 AppleScript。
- 不改变 macOS 系统默认文件管理器。
- 不让 reveal 计入 Run Count。
- 不提前展开 M3 的动态文案、diagnostics、release checklist 全量收口。

### M2 实现已落地（Codex 验收 PASS）

- `Sources/SwiftSeekCore/RevealResolver.swift`（新文件，纯函数 / AppKit-free）：`Strategy { .finder(targetURL) / .customApp(appURL, targetURL) / .fallbackToFinder(targetURL, reason) }`、`CustomAppValidation { .ok(URL) / .empty / .notFound(path) / .notAnApp(path) }`、`resolveTargetURL(target:openMode:)`（`.item` 返回原 URL；`.parentFolder` 文件返回父目录、目录返回自己保持不掉级）、`validateCustomAppPath(_:fileExists:)`（trim 空 / 不存在 / 非 dir / 缺 .app 后缀都进对应失败 case）、`decideStrategy(target:revealTarget:fileExists:)`（组合验证 + URL 解析）、`defaultFileExists` FileManager 探针；round 2 新增 `finderFallbackURL(target:)`，确保 Finder fallback 永远回原始 target URL。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`：`.revealInFinder` 现支持可选 `database` + `onReveal` 回调；保留旧 2 参数 `perform(_:target:)` 入口（database=nil 路径 → Finder）。三分支路由 `.finder` → `activateFileViewerSelecting`、`.customApp` → `NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: ...)`（`config.activates = true`），完成 handler 里 `error != nil` → NSLog（记录 external targetURL 与 Finder fallbackURL）+ 使用原始 `fallbackURL` 做 Finder fallback + `onReveal(.fallback)`、`.fallbackToFinder` → NSLog + Finder + `onReveal(.fallback)`。`RevealOutcome { .finder, .customApp(appName), .fallback(reason) }` 暴露给 SearchViewController。
- `Sources/SwiftSeek/UI/SearchViewController.swift` `revealSelected()`：传 `database` 给 runner；`onReveal` 回调里 `.fallback` 触发 `showToast("⚠️ 已回退到 Finder：<reason>")`。
- `Sources/SwiftSeekSmokeTest/main.swift`：16 个 M2 用例（resolveTargetURL .item / .parentFolder file / .parentFolder dir / validateCustomAppPath empty / whitespace / notFound / regular file / non-.app dir / .app ok / decideStrategy Finder / customApp+parent / customApp missing→fallback / customApp empty path / customApp non-.app dir / finderFallbackURL file / finderFallbackURL directory）。SmokeTest 总数 229 → 245。
- `docs/known_issues.md` §1 改写为 M2 路由已落地；§2 已指向 M2 runtime 接入事实；§6 改写为 fallback 已落地。
- `ResultAction` case 名仍是 `.revealInFinder`（M3 与 UI 文案动态化一起处理 rename）；`recordOpen` 仍只在 `.open` 路径调用，reveal 不计 Run Count。
- Round 2 受限沙箱下 build OK；SmokeTest 245/245；package-app OK；打包产物 `GitCommit=4ef32c0`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`、adhoc codesign OK。GUI 真实 NSWorkspace.open + 外部 app 行为留为手测。

## 当前阶段：M3

### 阶段目标

让用户选 QSpace / 自定义 app 后，搜索窗口按钮、右键菜单、hint、diagnostics、fallback 提示和 release gate 都能明确反映当前 Reveal target。

### M3 必须完成

- 增加可纯测 display-name / action-title helper：Finder、QSpace、其它 `.app`、空 / 失效 path 都有清晰文案。
- 搜索窗口按钮动态文案：Finder → “在 Finder 中显示”；QSpace → “在 QSpace 中显示”；其它 app → “在 <AppName> 中显示”。
- 右键菜单与按钮同源动态文案。
- hint 文案跟随当前 target 或改为中性“显示位置”。
- fallback toast 表达具体 app 与回退 Finder。
- diagnostics / About / 复制诊断信息暴露 reveal target type、custom app path、display name、open mode。
- `docs/manual_test.md` 与 `docs/release_checklist.md` 覆盖 Finder、QSpace/custom app、fallback、`.item` / `.parentFolder`、Run Count 不变。

### M3 禁止事项

- 不使用 QSpace 私有 API。
- 不硬编码未知 QSpace bundle id。
- 不假设 QSpace URL scheme。
- 不做 AppleScript。
- 不改变 macOS 系统默认文件管理器。
- 不让 reveal 计入 Run Count。
- 不输出轨道 `PROJECT COMPLETE`；M3 通过后才进入 M4 最终收口。

### M3 实现已落地（Codex 验收 PASS）

- `Sources/SwiftSeekCore/RevealResolver.swift`：新增三个纯函数 `displayName(for:)` / `actionTitle(for:)` / `fallbackReason(_:for:)`。displayName 规则：`.finder`→"Finder"；customApp 空路径→"自定义 App"；filename 含 "qspace" (case-insensitive)→"QSpace"；其它 .app → 去 `.app` 后缀；其它路径 → 文件名原样。actionTitle = "在 \(displayName) 中显示"；fallbackReason = "无法用 \(displayName) 显示，已回退到 Finder：\(underlying)"。
- `Sources/SwiftSeek/UI/SearchViewController.swift`：把 reveal button 与右键菜单 reveal item 存为 `revealBtn` / `revealMenuItem` 属性；新增 `currentRevealTargetSafe()`（DB 读失败 → defaultTarget）+ `hintTextForReveal(target:)` + `refreshRevealLabels()`；button / 右键菜单 / hint 三个表面同源刷新。短 displayName（≤10 chars）在 hint 里显示“在 <displayName> 中显示”，长 displayName 降级为中性“显示位置”以避免底部单行 hint 溢出。revealSelected 现使用 RevealResolver-composed reason 文案。
- `Sources/SwiftSeek/UI/SearchWindowController.swift`：`show()` 在 `makeKeyAndOrderFront` 之后调 `viewController.refreshRevealLabels()`，确保 Settings 改动隔次生效。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`：customApp 成功路径 `RevealOutcome.customApp(appName:)` 用 displayName；failure / .fallbackToFinder 路径用 `RevealResolver.fallbackReason` 包装文案，toast 看到 "无法用 QSpace 显示，已回退到 Finder：…"。
- `Sources/SwiftSeekCore/Diagnostics.swift`：snapshot 新增 `Reveal target（M3）：` 块，含 type / 显示名称 / 按钮文案 / 打开模式 / 自定义 App 路径（Finder 模式标 "—（Finder 模式）"）。
- `Sources/SwiftSeekSmokeTest/main.swift`：11 个 M3 用例（displayName Finder / 空 / qspace 大小写 / Path Finder.app strip / 非 .app 文件名 / 仅空白；actionTitle Finder / QSpace / Path Finder；fallbackReason 组装；Diagnostics 块在 Finder 与 QSpace 两态下格式正确）。SmokeTest 总数 245 → 256。
- `docs/manual_test.md` §33ac：7 节 M3 手测矩阵（Finder 默认 / 切 QSpace / 切 Path Finder / fallback toast 文案 + Finder 选中原文件 / Diagnostics 块 / Run Count 不变 / 不实现项边界）。
- `docs/release_checklist.md`：smoke 基线 223 → 256；新增 §5f 必跑项；header 仍是 K6 + L1-L4，M3 / M4 完成后 M4 改 header 到 "K6 + L1-L4 + M1-M4"。
- `docs/known_issues.md` §3 改写为 M3 已落地（含三纯函数 / refreshRevealLabels / Diagnostics 块）；§7 改写为 M3 release gate 已就位、M4 仍待最终收口。
- `ResultAction` case 名仍保留 `.revealInFinder`（rename 涉及历史 smoke 与 ResultActionRunner 公共契约，M4 视情况处理；M3 验收明确不依赖 rename）；`recordOpen` 仍只在 `.open` 成功路径调用。
- `docs/known_issues.md` §1 / §6 已同步 M3 toast 真实口径：SearchViewController 弹 `⚠️ \(reason)`，其中 `reason` 由 `RevealResolver.fallbackReason(...)` 组成。
- 受限沙箱下 build OK；SmokeTest 256/256；package-app 仍可重复跑通；打包产物 `GitCommit=666c184`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`、adhoc codesign OK。GUI 真实 reveal / fallback toast / 切外部 app 留为手测（§33ac + release_checklist §5f）。

## 当前阶段：M4

### 阶段目标

最终收口 `everything-filemanager-integration`：把 README、known issues、architecture、manual test、release checklist 与 M1-M3 真实能力对齐，确认 release gate 可执行，并让 Codex 能据此判断是否输出本轨道 `PROJECT COMPLETE`。

### M4 必须完成

- README 不再把 reveal 能力描述成 Finder-only；应说明 Finder 默认、可选择 QSpace / 自定义 `.app`、外部 app 语义与真实边界。
- `docs/known_issues.md` 清理 M1/M2/M3 阶段性旧句子，只保留当前真实限制：外部 app 不保证选中文件、不用私有 API、不保证所有文件管理器语义一致。
- `docs/architecture.md` 增补 filemanager integration 结构：SettingsTypes / RevealResolver / ResultActionRunner / SearchViewController / Diagnostics 的职责边界。
- `docs/manual_test.md` 与 `docs/release_checklist.md` 保留 M3 GUI 项，并把 release gate header / baseline 改到 `K6 + L1-L4 + M1-M4`。
- 重新跑 build / smoke / package / plist / codesign，确认 L1-L4、K1-K6、M1-M3 不回退。
- `docs/codex_acceptance.md`、`docs/stage_status.md`、`docs/agent-state/README.md` 与本轮最终状态保持一致。

### M4 禁止事项

- 不做 QSpace 私有 API、bundle id、URL scheme、AppleScript。
- 不做正式签名、notarization、DMG、auto updater。
- 不改变 `.open` Run Count 语义。
- 不改变 macOS 系统默认文件管理器。
- 不扩展到全文搜索、OCR、AI 搜索、跨平台或 Finder 插件。

### M4 完成判定标准

- M1-M3 已通过且 M4 文档 / release gate 收口完成。
- 自动化验证全绿：build、SmokeTest、package-app、Info.plist、codesign。
- release checklist 能直接指导 Finder / QSpace / custom app / fallback / item vs parentFolder / Run Count 不变 / no Dock / menu bar / single-instance 验证。
- 文档不再互相矛盾，不再残留 Finder-only 旧口径。
- 无阻塞级回归或越界实现，Codex 可输出 `PROJECT COMPLETE`。

### M4 实现已落地（待 Codex 最终验收）

- `README.md`：Features 段新增 "文件管理器集成（M1-M3）" 行；当前限制段改写为 M1-M3 已落地、M4 收口中；当前进度 / Roadmap 加入 filemanager-integration gap / taskbook 链接。
- `docs/architecture.md`：在 productization 收口段之后新增 "everything-filemanager-integration 收口（M1-M4）" 段，按 M1/M2/M3/M4 列每阶段交付 + "当前轨道明确不做" 列表（QSpace 私有 API / 硬编码 bundle id / URL scheme 假设 / AppleScript / 改变系统默认文件管理器 / reveal 计入 Run Count / 跨用户多实例 / 承诺所有第三方文件管理器都能选中具体文件）。
- `docs/known_issues.md` 归档段从 "Productization 已完成；L1-L4 已收口" 扩展为同时涵盖 productization + menubar-agent + filemanager-integration M1-M3-M4，列保留边界（外部文件管理器选中文件由该 app 决定 / 不调私有 API / 不假设 bundle id 与 URL scheme）。
- `docs/release_checklist.md` header 升到 "K6 + L1-L4 + M1-M4 单页"；smoke baseline 仍为 256；§5b/§5c/§5d/§5e/§5f 共同覆盖菜单栏 + Dock 切换 + 状态可见性 + 单实例 + reveal 动态行为。
- `docs/stage_status.md`（本文件）M4 实现已落地段 + 状态翻为"M4 实现已就位，待 Codex 最终验收（PROJECT COMPLETE 候选）"。
- 不引入任何新代码，不改 ResultAction case 名（`.revealInFinder` 保留以稳定历史 smoke 与 ABI）；M1-M3 真实代码 / smoke 不变，确保不回退。
- 受限沙箱下 build OK；SmokeTest 256/256；package-app 仍可重复跑通；GUI 真实 reveal / fallback toast / 菜单栏 / 单实例 / Dock 切换都按 §33ac §33ab §33aa §33z §33y §5b-§5f 作为每次发布手测。

## 后续阶段索引

- M1：Reveal Target 数据模型与设置 UI
- M2：ResultActionRunner 接入 Finder / QSpace / 自定义 App
- M3：动态文案、fallback、诊断与手测
- M4：最终收口与 release gate

完整任务书见：`docs/everything_filemanager_integration_taskbook.md`。
