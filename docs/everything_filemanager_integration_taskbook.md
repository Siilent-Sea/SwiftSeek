# Everything File Manager Integration Taskbook

轨道名：`everything-filemanager-integration`

目标：让 SwiftSeek 的“显示位置 / Reveal”动作从 Finder-only 扩展为可配置 Finder / QSpace / 自定义文件管理器，同时保持稳健 fallback、清晰 UI 文案和可验收 release gate。

边界：不使用 QSpace 私有 API，不假设未知 bundle id 或 URL scheme，不做系统默认文件管理器替换，不做 AppleScript 自动化，不改变 `.open` 的 Run Count 语义。

## M1：Reveal Target 数据模型与设置 UI

### 阶段目标

先把“显示位置”配置落到 settings 数据模型和设置页。默认仍为 Finder，保证向后兼容。M1 不替换实际 reveal 动作。

### 明确做什么

- 新增设置键：
  - `reveal_target_type`
  - `reveal_custom_app_path`
  - `reveal_external_open_mode`
- 新增推荐类型：
  - `RevealTarget`
  - `RevealTargetType`
  - `ExternalRevealOpenMode`
- 默认行为：
  - `RevealTargetType.finder`
  - `ExternalRevealOpenMode.parentFolder` 或 `.item`，由实现说明解释取舍
- `Database` extension 增加 get/set 方法，missing/malformed fallback 到 Finder。
- 设置页增加 UI：
  - “显示位置”
  - Finder
  - 自定义 App…
  - 选择 App 按钮
  - 当前已选 app 名称和路径
  - 打开目标：文件本身 / 父目录
- 选择 app 时用公开 `NSOpenPanel` 选择 `.app`。
- QSpace 支持方式：
  - 用户选择 `/Applications/QSpace.app`
  - 不硬编码未知 bundle id
  - 不假设 URL scheme
  - 如果 app display name 或 bundle name 包含 QSpace，可在 UI 显示为 QSpace

### 明确不做什么

- 不改 `ResultActionRunner`。
- 不做实际外部 app 打开。
- 不改变 Finder reveal 的当前行为。
- 不做 QSpace 私有协议、URL scheme 或 AppleScript。
- 不改 Run Count、搜索、索引、DB schema、menu bar agent 或 single-instance 逻辑。

### 涉及关键文件

- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/next_stage.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`

### 验收标准

- fresh DB 读取 reveal target 返回 Finder 默认。
- custom app path 能持久化并 round-trip。
- external open mode 能持久化并 round-trip。
- malformed target type / open mode fallback 到 Finder 默认，不崩。
- 设置页能选择 Finder / 自定义 App，并展示当前选择。
- UI 明确说明 QSpace 通过用户选择 app 支持，不依赖私有协议。
- `ResultActionRunner` 仍未接 custom app；M1 不冒充已完成 QSpace 打开。

### 必须补的测试 / 手测 / release checklist

- Smoke：
  - 默认 Finder
  - target type round-trip
  - custom app path round-trip
  - open mode round-trip
  - malformed setting fallback
- 手测：
  - 设置页默认显示 Finder
  - 选择 `/Applications/QSpace.app` 或任意 `.app`
  - 当前 app 名称/路径显示正确
  - 切回 Finder 后 custom app 不再是当前目标
- release checklist 暂不要求外部 app 打开，因为 M1 不实现执行路径。

## M2：ResultActionRunner 接入 Finder / QSpace / 自定义 App

### 阶段目标

让“显示”动作真正走用户配置，同时保留 Finder 模式的原有能力。

### 明确做什么

- 重新审视命名：
  - 可以保留 `revealInFinder` 作为兼容枚举，但新增中性 helper；
  - 或迁移到更准确的 `showInFileManager` / `reveal` 语义。
- Finder 模式继续调用：
  - `NSWorkspace.shared.activateFileViewerSelecting([url])`
- custom app 模式：
  - 读取 `reveal_custom_app_path`
  - 校验 app path 是否存在且是 `.app`
  - 按 `reveal_external_open_mode` 解析目标 URL：
    - `item`：传文件 / 目录本身
    - `parentFolder`：传父目录
  - 使用 macOS 公开 API 打开，例如：
    - `NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: ..., completionHandler: ...)`
- 外部 app 不存在或打不开：
  - 显示 toast / alert / status label 错误
  - NSLog 记录 app path、target path、error
  - fallback 到 Finder
- `.reveal` / `.show` 不增加 open_count；只有 `.open` 增加 Run Count。

### 明确不做什么

- 不做 AppleScript。
- 不做 QSpace 私有 URL scheme。
- 不做系统全局文件管理器替换。
- 不让 reveal 计入 Run Count。

### 涉及关键文件

- `Sources/SwiftSeekCore/ResultAction.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/PathHelpers.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准

- Finder 模式行为不回退：仍能在 Finder 中选中文件。
- custom app 模式按 `item` / `parentFolder` 打开正确 URL。
- app path 不存在、不是 app、打不开时有可见反馈并 fallback 到 Finder。
- reveal/show 不改变 `file_usage.open_count`。
- helper 逻辑可 smoke 测试；真实外部 app 打开写入 manual test。

### 必须补的测试 / 手测 / release checklist

- Smoke：
  - resolve target URL for item / parentFolder
  - validate custom app path
  - fallback decision
  - Finder mode unchanged
- 手测：
  - Finder 模式
  - QSpace/custom app 模式
  - app 被移动后的 fallback
  - reveal 不增加 Run Count

## M3：动态文案、fallback、诊断与手测

### 阶段目标

让用户选 QSpace / 自定义 app 后，UI、诊断和 release gate 都能明确反映当前 Reveal target。

### 明确做什么

- 搜索窗口按钮动态文案：
  - Finder：在 Finder 中显示
  - QSpace：在 QSpace 中显示
  - 自定义 App：在 `<AppName>` 中显示
- 右键菜单动态文案。
- hint 文案同步，避免只写 `Reveal` 或 Finder-only。
- fallback 时给可见反馈：例如“无法用 QSpace 显示，已改用 Finder”。
- About / diagnostics 显示：
  - reveal target type
  - custom app path
  - app display name
  - external open mode
- 文档说明：
  - Finder 是唯一保证“选中文件”的模式
  - 外部 app 模式是“用该 app 打开目标 URL”
  - 是否选中文件由外部 app 决定
- release checklist 增加 Finder / QSpace/custom app / fallback / item vs parentFolder 四类验证。

### 明确不做什么

- 不承诺 QSpace 一定能选中文件。
- 不承诺所有第三方文件管理器都有同样语义。
- 不做私有 API 或脚本桥。

### 涉及关键文件

- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `docs/manual_test.md`
- `docs/release_checklist.md`
- `docs/install.md`
- `docs/known_issues.md`

### 验收标准

- 选择 QSpace 后按钮 / 右键菜单显示“在 QSpace 中显示”。
- 选择其它 app 后显示 app 名称。
- fallback 有可见反馈。
- diagnostics 可判断当前 reveal target。
- release checklist 覆盖真实 GUI 场景。

### 必须补的测试 / 手测 / release checklist

- Smoke：
  - app display name formatter
  - diagnostics field rendering
  - fallback message formatter
- 手测：
  - Finder mode 文案
  - QSpace/custom app 文案
  - app 被移动 fallback
  - item / parentFolder 差异

## M4：最终收口与 release gate

### 阶段目标

让 `everything-filemanager-integration` 达到可验收完成状态。

### 明确做什么

- README / known_issues / manual_test / release_checklist / architecture 同步。
- Smoke 全绿。
- `package-app.sh --sandbox` 仍通过。
- 确认不回退：
  - menubar-agent no Dock / Dock setting / menu status / single-instance
  - productization build identity / package / diagnostics
  - Run Count
  - search hotkey
  - context menu
- Codex 可据此判断 `PROJECT COMPLETE`。

### 明确不做什么

- 不做 QSpace 私有协议。
- 不做正式签名 / notarization / DMG / auto updater。
- 不做完整文件管理器。
- 不改变 macOS 系统默认文件管理器。

### 涉及关键文件

- `README.md`
- `docs/known_issues.md`
- `docs/manual_test.md`
- `docs/release_checklist.md`
- `docs/architecture.md`
- `docs/codex_acceptance.md`
- `docs/stage_status.md`
- `docs/agent-state/README.md`

### 验收标准

- M1-M3 全部通过。
- Finder / QSpace / custom app / fallback / item / parentFolder 均有测试或手测覆盖。
- 文档不再写成 Finder-only。
- 已知边界清楚：不保证外部 app 选中文件，不使用私有接口。
- Codex 可输出 `PROJECT COMPLETE`。

### 必须补的测试 / 手测 / release checklist

- 自动化：
  - `swift build --disable-sandbox`
  - `swift run --disable-sandbox SwiftSeekSmokeTest`
  - `./scripts/package-app.sh --sandbox`
- 手测：
  - Finder 模式
  - QSpace/custom app 模式
  - app path 失效 fallback
  - item vs parentFolder
  - reveal 不影响 Run Count
  - no Dock / menu bar agent 不回退
