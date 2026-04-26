# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。历史轨道 `v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`、`everything-productization`、`everything-menubar-agent`、`everything-filemanager-integration` 均已归档。

## 当前活跃轨道相关限制

### 1. Reveal 路由（M2 已落地）

- `Sources/SwiftSeekCore/RevealResolver.swift` 提供纯函数 `resolveTargetURL(target:openMode:)`、`validateCustomAppPath(_:fileExists:)`、`decideStrategy(target:revealTarget:fileExists:)`，三种结果：`.finder(targetURL)` / `.customApp(appURL, targetURL)` / `.fallbackToFinder(targetURL, reason)`。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift` `.revealInFinder` 现在接受可选 `database` + `onReveal` 回调；有 DB 时读取 `getRevealTarget()` → `RevealResolver.decideStrategy` → 三个分支：
  - `.finder` → 仍调 `NSWorkspace.shared.activateFileViewerSelecting([url])`，行为不回退
  - `.customApp` → `NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: ...)` （`config.activates = true`）；completion handler 里如果有 error → NSLog + Finder fallback + `onReveal(.fallback)`
  - `.fallbackToFinder` → NSLog + Finder + `onReveal(.fallback)`
- DB 读取失败 / 无 DB 句柄 → 自动 Finder fallback。
- `Sources/SwiftSeek/UI/SearchViewController.swift` `revealSelected()` 把 `database` 传给 runner，fallback 路径触发 `showToast("⚠️ \(reason)")`，其中 `reason` 由 M3 `RevealResolver.fallbackReason(...)` 组成（典型："无法用 QSpace 显示，已回退到 Finder：自定义 App 不存在：…"）。
- `ResultAction` case 名仍是 `.revealInFinder`（M3 才考虑重命名 / 文案动态化；rename 牵动 SmokeTest 与外部契约，M3 与 UI 文案一起处理）。
- `.revealInFinder` 不调 `recordOpen` / 不增加 `file_usage.open_count`（H1 起就由 `.open` 路径独占，M2 不变）。

### 2. QSpace / 自定义文件管理器配置已就位（M1 已落地，M2 接入运行时）

- `Sources/SwiftSeekCore/SettingsTypes.swift` 新增 `RevealTargetType { .finder, .customApp }` / `ExternalRevealOpenMode { .item, .parentFolder }` / `RevealTarget` 结构体；DB key `reveal_target_type` / `reveal_custom_app_path` / `reveal_external_open_mode`；`Database.getRevealTarget() / setRevealTarget(_:)` 任一字段 malformed 单独 fallback 到 `RevealTarget.defaultTarget`（Finder + 空路径 + parentFolder）。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 设置 → 常规 → 最下方"显示位置"行：popup（Finder / 自定义 App…）+ "选择 App…" 按钮（NSOpenPanel 限定 `.app`，默认目录 `/Applications`）+ 当前 app 名称 / 路径 summary（含 QSpace 名称启发式识别）+ "打开目标" segmented（父目录 / 文件本身）+ 多行 note 解释 Finder vs 自定义 App 与两种 open mode 的语义。
- 默认仍是 Finder + 空路径 + parentFolder；用户切到自定义 App 但未选 .app 时 summary 显示 `⚠️` 提示，UI 不会让用户进入"自定义但路径空"的迷惑状态。
- M2 已把这套配置接到 `ResultActionRunner` 运行时（详见 §1 "Reveal 路由（M2 已落地）"）；动态按钮 / 右键菜单 / hint、diagnostics 与 release gate 已在 M3-M4 收口。

### 3. UI 文案 / Diagnostics（M3 已落地）

- `Sources/SwiftSeekCore/RevealResolver.swift` 提供 `displayName(for:)`、`actionTitle(for:)`、`fallbackReason(_:for:)` 三个纯函数：Finder → "Finder"；customApp 空路径 → "自定义 App"；filename case-insensitive 含 "qspace" → "QSpace"；其他 .app → 去掉 `.app` 后的文件名；其他路径 → 文件名原样。
- `Sources/SwiftSeek/UI/SearchViewController.swift` 把 reveal button 与右键菜单 reveal item 存为属性；`refreshRevealLabels()` 在 `SearchWindowController.show()` 每次 pop 时调用，确保 Settings 改动隔次生效。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift` 的 fallback toast 改用 `RevealResolver.fallbackReason` 包装，底层错误前缀变 "无法用 <AppName> 显示，已回退到 Finder：…"；customApp 成功路径 `RevealOutcome.customApp` 用 displayName 而非裸文件名。
- `Sources/SwiftSeekCore/Diagnostics.swift` 新增 `Reveal target（M3）：` 块，含 type / 显示名称 / 按钮文案 / 打开模式 / 自定义 App 路径，便于 bug-report 复制。
- 仍保留的真实边界：外部 app 是否能"选中"具体文件由该 app 自身实现决定；M3 只用 `NSWorkspace.open(...withApplicationAt:configuration:)` 公开 API 把目标 URL 交给 app，不调私有 API、不假设 bundle id / URL scheme。

### 4. 外部 App 的“显示文件”语义不等同于 Finder 选中文件

- Finder 模式可保证“打开 Finder 并选中目标文件”。
- 自定义 App 模式最稳妥的公开 API 语义是“用该 app 打开目标 URL”。
- 外部 app 是否选中文件、打开文件本身、打开父目录，取决于该 app 自己的行为。
- 因此 SwiftSeek 提供 `item` / `parentFolder` open mode，并在 UI / 文档里讲清楚。

### 5. 不使用 QSpace 私有 API，也不假设 bundle id / URL scheme

- 当前不会硬编码 QSpace bundle id。
- 当前不会假设 QSpace 有稳定 URL scheme。
- 当前路径是让用户通过设置选择 `/Applications/QSpace.app` 或任意 `.app`，再用 macOS 公开 API 打开文件或父目录。
- 这意味着 SwiftSeek 可以支持 QSpace，但不承诺 QSpace 私有级别的“选中文件”能力。

### 6. 外部 App 失效 fallback（M2 已落地）

- 失效路径覆盖：path 空 / 仅空白 / 不存在 / 不是 .app bundle / NSWorkspace.open 异步报错。
- 失效时统一处理：`NSLog` 一行（含 app path / target path / open mode / error）+ Finder `activateFileViewerSelecting` fallback + `onReveal(.fallback(reason:))` 回调让 SearchViewController 弹 toast `⚠️ \(reason)`。M3 起 `reason` 由 `RevealResolver.fallbackReason(...)` 组成，典型形式："无法用 QSpace 显示，已回退到 Finder：…"。
- 不允许 silent fail；fallback 后用户仍能在 Finder 中看到目标文件。
- M3 已把 reveal target 信息写入 diagnostics，让 bug-report 模板能复制当前配置。

### 7. 手测与 release gate（M3-M4 已收口）

- `docs/manual_test.md` §33ac 写了 M3 完整手测矩阵：默认 Finder / 切 QSpace / 切 Path Finder / fallback toast 文案 / Diagnostics 块 / Run Count 不变 / 不实现项边界。
- `docs/release_checklist.md` §5f 把上述项变成发布前必须确认项；smoke 基线已升到 256。
- M4 已把 README / known_issues / architecture / release checklist 与 M1-M3 实际代码对齐；最终验收 smoke 256/256、package-app 可重复、L1-L4 / K1-K6 不回退。

## 已归档能力与仍保留边界

### 默认隐藏 Dock 图标（L1 已落地）

- `AppDelegate.applicationDidFinishLaunching` 在最早期（NSLog build identity 三连之后）调用 `NSApp.setActivationPolicy(.accessory)`，使 Dock 不显示 SwiftSeek 图标。
- `Info.plist` 仍保留 `LSUIElement=false`：选择运行时 activation policy 而非 plist `LSUIElement=true` 的取舍写在 `scripts/package-app.sh` 注释和 `docs/install.md` 默认形态段。
- L2 已基于 runtime activation policy 加 "显示 Dock 图标" 设置开关；plist 路径保留，用户不需要重打包就能切换下次启动的 Dock 可见性。
- 在 ad-hoc / 未签名 bundle 上，不同 macOS 版本对 activation policy 的稳定性仍需手测；release checklist §5b 强制每次发布手动确认。

### 菜单栏 status item 是默认主入口（L1 已落地）

- `AppDelegate.installStatusItem()` 安装的 `NSStatusItem` 是 L1 之后用户与 SwiftSeek 交互的主入口。
- 当前菜单栏菜单包含：
  - 搜索…（⌥Space）
  - 设置…（⌘,）
  - 索引：空闲 / 索引中（只显示）
  - build / 模式 / roots / DB 大小（只读状态行）
  - 退出 SwiftSeek（⌘Q）
- L3 已补 build identity、索引模式、DB 大小和 root 简况；最近 / 常用子菜单未在 round 1 实现，保留为可选后续。
- L1 不再依赖 Dock reopen 作为默认入口；`applicationShouldHandleReopen` 仅作为 fallback（`open` 第二次时弹设置窗口）。

### 无 Dock 模式下的入口与退出（L1 已落地）

- J1/J6 之前依赖 Dock click 唤回设置窗口；L1 改为依赖菜单栏图标 + 全局热键。
- 退出路径优先级：菜单栏 → "退出 SwiftSeek"（⌘Q） > `pkill -f "SwiftSeek.app"` > Activity Monitor 强制退出。
- `applicationShouldHandleReopen` 仍保留：双击已运行的 SwiftSeek.app 第二次会弹设置窗口作为 fallback，避免"双击没反应"的迷惑感。
- 菜单栏图标在某些极端场景（屏幕过窄被挤掉、stale bundle 在跑、Gatekeeper 拦截）可能不出现；`docs/install.md` 默认形态段写了排查矩阵。

### LSUIElement / activationPolicy 在 ad-hoc App 下需要实测

- 当前 SwiftSeek 仍是 ad-hoc codesign，不是 Developer ID 签名，不做 notarization。
- `LSUIElement=true` 与 `NSApp.setActivationPolicy(.accessory)` 都会影响 Dock、Command+Tab、主菜单可见性和窗口前置行为。
- macOS 不同版本、LaunchServices 缓存、未签名 / ad-hoc bundle 可能表现有差异。
- L1/L2 必须用真实 `dist/SwiftSeek.app` 手测，不能只看源码推断。

### 退出路径必须明确

- 隐藏 Dock 后，用户不能靠 Dock 右键退出。
- 当前 status item 的"退出 SwiftSeek"是关键路径，必须纳入 release gate。
- 如果 status item 异常，文档需要保留备用路径，例如 Activity Monitor、`pkill -f SwiftSeek` 或重新打开 app 后退出。

### 多开 / 旧 bundle 防护（L4 已落地）

- `Sources/SwiftSeekCore/SingleInstance.swift` 提供纯函数 `chooseSibling(myPid:candidates:)` 与 `conflictLogLine(...)`；AppDelegate 在 `applicationDidFinishLaunching` 用 `NSRunningApplication.runningApplications(withBundleIdentifier:)` 拉同 bundle id 实例列表，过滤掉自己 pid，挑最低 pid 作为 canonical owner。
- 检测维度：
  - 同一 `dist/SwiftSeek.app` 重复打开
  - `dist/SwiftSeek.app` 与 `/Applications/SwiftSeek.app` 并存（两份默认共享 `com.local.swiftseek` bundle id）
  - Launch at Login 与手动启动并发
- 检测到旧实例时：
  - NSLog 一行冲突信息：`SwiftSeek: another instance detected — sibling pid=... bundle=... exec=...; our pid=... bundle=... exec=...; deferring to sibling and exiting`
  - 直接调 `NSRunningApplication.activate(options: [.activateAllWindows])` 把旧实例前置
  - 同时 `DistributedNotificationCenter` 广播 `com.local.swiftseek.menubar-agent.show-settings`，旧实例收到后调 `showSettings(nil)` 弹设置窗口给用户视觉反馈
  - 新实例 `NSApp.terminate(nil)` 退出，不长期常驻、不抢菜单栏图标、不抢 hotkey、不写 DB
- 边界（仍需保留）：
  - 用户在打包时用 `SWIFTSEEK_BUNDLE_ID=...` 自定义不同 bundle id 的两个 build：会被视为不同 app，单实例检查不跨它们触发（这是 macOS 行为，也是设计预期）
  - 跨用户 / 跨登录会话：`NSRunningApplication.runningApplications(withBundleIdentifier:)` 仅返回当前用户会话的进程；跨用户多实例不在本轨道范围
  - `swift run SwiftSeek`（直接源码跑，不打包）：`Bundle.main.bundleIdentifier` 为 nil，单实例检查跳过 + NSLog 提示；这是 dev 路径已知降级
- 排查路径：Console.app 过滤 SwiftSeek，第一行有 K1 build identity 三连，紧接着如果检测到冲突会有上述 NSLog；用户根据两个 bundle path 决定退掉哪一个（菜单栏 → 退出 SwiftSeek 或 `pkill`）。

### Dock 显示开关（L2 已落地）

- 设置 → 常规 → 最下方 "在 Dock 显示 SwiftSeek 图标（菜单栏入口仍保留）" 复选框。
- 持久化字段：`SettingsKey.dockIconVisible`（DB key `dock_icon_visible`），默认 `"0"` = L1 menubar-agent / no Dock。
- `AppDelegate.applicationDidFinishLaunching` 顺序：先调 `.accessory`（兜底），DB 打开后读设置；为 `true` 切到 `.regular`。读失败时保持 L1 默认。
- **生效时机：重启 SwiftSeek 后生效**。UI note 在用户切换后会立即显示 "⚠️ 已勾选/已取消勾选，但当前进程仍是 ..."，提示菜单栏退出 + 重新打开。原因：runtime `.regular` ↔ `.accessory` 在 ad-hoc / 未签名 bundle 上的 transition 不稳定（主菜单 / key window / Dock 状态可能不一致）。
- 切换时不会丢失菜单栏入口；两种模式下菜单栏 status item 都常驻。
- macOS activation policy 在不同版本和 LaunchServices 缓存下表现可能有差异；release_checklist §5c 保留为每次发布必跑手测。

### 菜单栏状态可见性（L3 已落地）

- `Sources/SwiftSeekCore/MenubarStatus.swift` 提供纯函数 `MenubarStatus.snapshot(database:indexingDescription:)` + `tooltipText(snapshot:)`，组合 BuildInfo + IndexMode + listRoots + RootHealth + DatabaseStats 得到 5 行 tooltip 与 5 行只读菜单状态。
- AppDelegate 菜单结构：搜索 / 设置 / ─── / 索引 / build / 模式 / roots / DB 大小 / ─── / 退出。新增 4 个 disabled NSMenuItem（build / 模式 / roots / DB 大小）只读状态行。
- 刷新时机：installStatusItem 初始填充 + `NSMenuDelegate.menuNeedsUpdate(_:)` 每次菜单打开 + `reflectRebuildState(_:)` 索引中/空闲切换。
- tooltip 与菜单状态文本同源；不重复 K3 `Diagnostics.snapshot` 的全文（仍走"复制诊断信息"按钮）。
- 不读取 macOS 全局最近项目 / Finder 历史 / private API；roots 健康判定使用 K5 `computeRootHealthReport`。
- 不做完整菜单栏 dashboard 或弹窗控制台；当前 L3 只做只读状态，最近 / 常用入口未在 round 1 实现（taskbook 标"如果实现"）。
- 读取失败的降级文案：indexMode 读不到 → "—"；listRoots 失败 → "读取 roots 失败"；mainFileBytes < 0 → "DB 大小：—"；DB 不可用（未初始化）→ tooltip 回退为"SwiftSeek 搜索"，菜单状态行保持初始 placeholder。

### Productization / 菜单栏 agent / 文件管理器集成 已完成形态收口

- `everything-productization` 已完成可重复 `.app` 打包、Info.plist / icon / ad-hoc codesign、build identity、diagnostics、install / rollback 文档、Full Disk Access / root 覆盖引导和 release checklist。
- `everything-menubar-agent` L1 把默认 activation policy 切成 `.accessory`，Dock 不再常驻；菜单栏 status item 是主入口；L2 Dock 显示开关；L3 菜单栏只读状态可见性；L4 单实例防护。
- `everything-filemanager-integration` M1 Reveal Target 数据模型 + 设置 UI；M2 ResultActionRunner 接入 RevealResolver + customApp NSWorkspace.open + Finder fallback；M3 动态 button / 右键菜单 / hint + Diagnostics 块 + fallback toast；M4 文档收口（README / known_issues / architecture / release_checklist / manual_test 全对齐）。
- 仍保留的真实边界：ad-hoc / 未公证 / 无 DMG / 无 auto updater；外部文件管理器是否能"选中具体文件"取决于该 app 自身实现；不调任何文件管理器私有 API；不假设 QSpace bundle id / URL scheme。

### Run Count 统计范围

- `Run Count` / `打开次数` 只表示通过 SwiftSeek 成功触发 `.open` 的次数。
- 不读取 macOS 全局启动次数。
- 不读取系统最近项目。
- 不扫描系统隐私数据。
- 不使用 private API。

### 查询和搜索边界

- 已支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:` / `recent:` / `frequent:`。
- 已支持 wildcard / quote / OR / NOT。
- 仍不做全文内容搜索、OCR、AI 语义搜索、regex、括号表达式。

### DB footprint

- Compact 模式已将 500k 实测 main DB 从 fullpath 3.46 GB 降到 1.07 GB。
- Full path substring 模式仍可选，但体积更大。
- VACUUM / checkpoint 是维护入口，不是替代 compact 的根治方案。

## 环境约束

- macOS 13+。
- SwiftPM 工程，无 `.xcodeproj` / `.xcworkspace`。
- 当前本地交付仍是 ad-hoc bundle；正式 Developer ID 签名、notarization、DMG、auto updater 不在当前默认范围。

## 明确不做

- 全文内容搜索
- OCR
- AI 语义搜索
- 云盘 / 网络盘实时一致性承诺
- 跨平台
- Electron / Tauri / Web UI 替代原生
- APFS 原始解析
- Finder 插件
- App Store 沙盒适配
- macOS 全局启动次数读取
- 系统隐私数据扫描
- private API
- 在没有证书与明确要求时承诺正式签名 / 公证
