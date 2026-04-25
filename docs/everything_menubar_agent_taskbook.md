# Everything Menubar Agent Taskbook

轨道名：`everything-menubar-agent`

目标：把 SwiftSeek 从普通 Dock App 推进为默认菜单栏常驻工具。该轨道只处理 Dock 隐藏、菜单栏主入口、激活策略、退出路径、单实例与发布收口，不扩展搜索、索引、DB schema 或正式签名/公证。

## L1：默认隐藏 Dock + 菜单栏主入口

### 阶段目标

让打包后的 SwiftSeek 默认不常驻 Dock，并确认菜单栏 status item、全局热键、搜索窗口、设置窗口和退出路径构成最小可靠闭环。

### 明确做什么

- 审计并选择实现方式：
  - 方案 A：运行时调用 `NSApp.setActivationPolicy(.accessory)` 或等价方式；
  - 方案 B：打包时把 `Info.plist` 的 `LSUIElement` 设置为 `true`；
  - 必须在代码注释或文档里写清取舍。
- 默认隐藏 Dock 图标。
- 确认 `NSStatusItem` 是主入口，不是辅助入口。
- 保证菜单栏"搜索…"、"设置…"、"退出 SwiftSeek"可用。
- 保证全局热键仍可唤出搜索窗。
- 保证设置窗口和搜索窗口能前置。
- 更新 `docs/release_checklist.md`，把 L1 的 no Dock 手测加入 release gate。
- 更新 `docs/install.md`，说明隐藏 Dock 后的启动、退出和排查方式。
- 更新 `docs/known_issues.md`，诚实保留 LSUIElement / ad-hoc / macOS 行为差异边界。

### 明确不做什么

- 不做 Dock 显示开关。
- 不做单实例保护。
- 不做正式签名、公证、DMG、auto updater。
- 不重写窗口系统。
- 不扩展菜单栏状态项。
- 不改搜索、索引、DB schema、usage、Run Count 等业务能力。

### 涉及关键文件

- `scripts/package-app.sh`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/App/MainMenu.swift`
- `Sources/SwiftSeek/App/GlobalHotkey.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `docs/release_checklist.md`
- `docs/install.md`
- `docs/known_issues.md`
- `docs/manual_test.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/next_stage.md`

### 验收标准

- `./scripts/package-app.sh --sandbox` 生成的 `dist/SwiftSeek.app` 默认不显示 Dock 图标。
- 启动后菜单栏 SwiftSeek 图标可见。
- 菜单栏"搜索…"能打开搜索窗，且窗口前置、输入框可直接输入。
- 菜单栏"设置…"能打开设置窗，且窗口前置。
- 全局热键能打开 / 隐藏搜索窗。
- 菜单栏"退出 SwiftSeek"能退出进程。
- release checklist 不再把 Dock reopen 当作默认入口；no Dock 验证成为 L1 gate。
- 文档明确无 Dock 模式下的退出与排查路径。

### 必须补的测试 / 手测 / release checklist

- 构建：`swift build --disable-sandbox`
- Smoke：`swift run --disable-sandbox SwiftSeekSmokeTest`
- Package：`./scripts/package-app.sh --sandbox`
- Plist：`plutil -p dist/SwiftSeek.app/Contents/Info.plist | grep LSUIElement`
- 手测：
  1. `open dist/SwiftSeek.app`
  2. Dock 中不出现 SwiftSeek 图标
  3. 菜单栏图标出现
  4. 菜单栏搜索成功
  5. 菜单栏设置成功
  6. 全局热键成功
  7. 菜单栏退出成功

## L2：Dock 显示开关与激活策略稳定化

### 阶段目标

给用户恢复 Dock 图标的能力，并让隐藏 Dock / 显示 Dock 两种模式下的激活、前置、重启提示和设置持久化稳定。

### 明确做什么

- 增加设置项，例如 `dock_icon_visible` 或 `menubar_agent_mode`。
- 设置页增加"显示 Dock 图标"或"菜单栏模式"开关。
- 明确切换是否实时生效：
  - 若 `NSApp.setActivationPolicy` 在当前实现中稳定，则实时切换；
  - 若不稳定，则保存设置并提示重启生效。
- 两种模式下验证搜索窗、设置窗、主菜单、菜单栏入口、全局热键。
- 更新 install / manual test / known issues。

### 明确不做什么

- 不做正式 installer。
- 不做单实例。
- 不做菜单栏复杂状态面板。

### 涉及关键文件

- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `scripts/package-app.sh`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准

- 默认隐藏 Dock。
- 用户能在设置里看到清楚的 Dock / 菜单栏模式选项。
- 如果需要重启生效，UI 必须明确提示，不能假装实时成功。
- 切换后重启，Dock 可见性符合设置。
- 两种模式下搜索、设置、退出、热键都可用。

### 必须补的测试 / 手测 / release checklist

- Smoke 覆盖设置默认值、读写和边界。
- 手测覆盖隐藏 Dock → 显示 Dock → 重启 → 再隐藏 Dock。
- release checklist 增加两种模式的最小入口验证。

## L3：菜单栏菜单增强与状态可见性

### 阶段目标

让菜单栏成为真正主入口，而不是只放搜索和设置的兜底菜单。

### 明确做什么

- 菜单栏菜单增强：
  - 搜索…
  - 最近打开
  - 常用
  - 设置…
  - 索引状态
  - 当前索引模式
  - DB 大小简况
  - root 数量 / 不健康 root 简况
  - 暂停 / 恢复索引（如已有能力则接入，否则不要假实现）
  - 退出
- 菜单项显示快捷键提示。
- status item tooltip 显示 build version、index mode、root count、indexing state。
- 复杂操作跳转设置页，不把菜单做成臃肿控制台。

### 明确不做什么

- 不做完整菜单栏弹窗 dashboard。
- 不做遥测。
- 不做需要 private API 的系统状态读取。

### 涉及关键文件

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `docs/manual_test.md`
- `docs/release_checklist.md`

### 验收标准

- 菜单栏可直接进入搜索、最近打开、常用、设置、退出。
- 菜单栏能展示简要索引状态、索引模式、DB 大小或 root 简况。
- tooltip 能帮助用户确认当前运行构建和基本状态。
- 菜单结构不影响搜索/设置主路径。

### 必须补的测试 / 手测 / release checklist

- Smoke 覆盖菜单所需的纯函数格式化逻辑。
- 手测覆盖菜单项状态更新、tooltip 更新、索引中状态变化。
- release checklist 增加菜单栏状态验证。

## L4：单实例 / 多 bundle 防护与最终收口

### 阶段目标

菜单栏 agent 形态下，减少多开、旧 bundle、登录项和手动启动并存造成的混乱，并完成本轨道最终验收准备。

### 明确做什么

- 检查同 bundle id / 同 DB path 是否已有 SwiftSeek 实例。
- 至少实现一种公开 API 或普通文件系统方案：
  - lock file
  - distributed notification
  - `NSRunningApplication` 检测
  - 或其他公开 macOS 方案
- 检测到已有实例时：
  - 新实例不应继续常驻；
  - 尽量通知旧实例显示搜索或设置；
  - 如果无法通知，写明确日志并退出。
- release checklist 增加：
  - 双击 app 两次；
  - Launch at Login + 手动启动；
  - `dist` bundle 和 `/Applications` bundle 并存；
  - 菜单栏是否出现重复图标；
  - hotkey 是否冲突。
- 文档最终收口。

### 明确不做什么

- 不做 auto updater。
- 不做正式签名 / 公证。
- 不做跨用户多实例支持。
- 不绕过 macOS 权限。

### 涉及关键文件

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeekCore/AppPaths.swift`
- `Sources/SwiftSeek/App/LaunchAtLogin.swift`
- `docs/install.md`
- `docs/release_checklist.md`
- `docs/known_issues.md`
- `docs/manual_test.md`
- `docs/codex_acceptance.md`
- `docs/stage_status.md`

### 验收标准

- 常见多开路径不会产生两个长期常驻菜单栏实例。
- 旧 bundle / 新 bundle 并存时，有日志或诊断能解释当前运行实例。
- Launch at Login 与手动启动并发不造成重复常驻。
- 文档说明清楚：当前仍是 ad-hoc / 未公证，不承诺正式发行机制。
- Codex 可据此判断 `everything-menubar-agent` 是否 `PROJECT COMPLETE`。

### 必须补的测试 / 手测 / release checklist

- Smoke 覆盖可自动化的 single-instance 辅助逻辑。
- 手测覆盖双击两次、登录项 + 手动启动、旧 bundle + 新 bundle 并存。
- release checklist 最终同步 L1-L4。
