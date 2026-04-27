# Everything Dockless Hardening Taskbook

轨道名：`everything-dockless-hardening`

目标：不再把历史 `everything-menubar-agent` 的“默认 no Dock”文档结论当成事实，而是围绕真实用户反馈把 SwiftSeek 的 Dock 隐藏、Dock 设置污染、包体策略、诊断和 `.app` 验收硬化到可长期交付。

## N1：Dock 常驻根因审计与诊断暴露

### 阶段目标

先让用户和开发者明确知道当前为什么会显示 Dock。N1 只做根因审计、日志和 Diagnostics 暴露，不提前改变 package 默认策略。

### 明确做什么

- 审计并记录当前 Dock 相关路径：
  - `NSApp.setActivationPolicy`
  - `dock_icon_visible`
  - `LSUIElement`
  - package `Info.plist`
  - Settings UI
  - About / Diagnostics
- 在 About / Diagnostics 增加 Dock 状态块：
  - persisted `dock_icon_visible`
  - intended mode：menu bar agent / Dock app
  - effective activation policy：`.accessory` / `.regular` / 其他
  - Info.plist `LSUIElement`
  - bundle path
  - executable path
- 启动日志打印 Dock mode 判断：
  - `dock_icon_visible` 的读取结果
  - 最终选择的 activation policy
  - Info.plist `LSUIElement`
  - bundle path / executable path
- 如果 `dock_icon_visible=1`，日志必须明确写出 Dock 出现是用户设置导致。
- 如果读取设置失败，日志必须说明 fallback 到 no-Dock / `.accessory`。
- smoke 覆盖：
  - fresh DB 默认 `dock_icon_visible=false`
  - set true / false round-trip
  - Diagnostics 字符串包含 Dock mode 关键字段
  - malformed / missing setting fallback 到隐藏 Dock 的文字可见

### 明确不做什么

- 不改 package 默认策略。
- 不把 `LSUIElement` 改成 `true`。
- 不移除 Dock 显示设置。
- 不强制重写用户 DB。
- 不做一键恢复 UI。
- 不声称 Dock 已经最终稳定隐藏。

### 涉及关键文件

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `scripts/package-app.sh`
- `docs/known_issues.md`
- `docs/release_checklist.md`
- `docs/install.md`
- `docs/codex_acceptance.md`
- `docs/next_stage.md`

### 验收标准

- About / Diagnostics 能直接解释 Dock 相关状态，不需要用户先手工查 SQLite。
- Console 启动日志能区分：
  - fresh/missing setting
  - `dock_icon_visible=0`
  - `dock_icon_visible=1`
  - Info.plist `LSUIElement=false`
  - 当前 bundle / executable path
- 用户反馈“Dock 仍常驻”时，诊断信息足以判断是旧设置、旧 bundle、plist 策略还是 runtime policy。
- `swift build --disable-sandbox` 通过。
- `swift run --disable-sandbox SwiftSeekSmokeTest` 通过，且新增 smoke 不少于当前基准。
- 文档明确 N1 不是最终修复，只是让根因可见。

### 必须补的测试 / 手测 / release checklist

- Smoke：
  - `getDockIconVisible` 默认 false。
  - `setDockIconVisible(true/false)` round-trip。
  - Diagnostics 包含 `Dock mode` / `dock_icon_visible` / `LSUIElement` / activation policy 等关键字。
- 手测：
  - 用 fresh DB 启动，复制 Diagnostics。
  - 设置 `dock_icon_visible=1` 后重启，复制 Diagnostics。
  - 对比两份 Diagnostics 能明确解释 Dock 差异。
- release checklist：
  - 增加 N1 诊断字段检查项，但不要求此阶段改 package 策略。

## N2：默认无 Dock 的打包与启动策略硬化

### 阶段目标

让默认 `.app` 产物真正偏向 no-Dock / menu bar agent，不再只依赖历史 L1 的文档声明。

### 明确做什么

- 重新设计 `scripts/package-app.sh` 的 Dock 模式参数：
  - 默认生成 no-Dock / agent 包。
  - 可选参数生成 Dock App 包，例如 `--dock-app`。
- 必须决定并实现一种主策略：
  - 推荐方案 A：默认 `LSUIElement=true`，`--dock-app` 时写 `false`。
  - 可选方案 B：继续 `LSUIElement=false`，但 runtime 强制 `.accessory`，并用 N1 Diagnostics 证明；若选 B，必须在文档说明为什么不改 plist。
- package 输出日志必须打印：
  - LSUIElement 值
  - intended Dock mode
  - GitCommit
  - bundle id
  - 输出 app path
- `plutil -p dist/SwiftSeek.app/Contents/Info.plist` 必须能看到预期 `LSUIElement`。
- 更新 `docs/install.md` 和 `docs/release_checklist.md`。

### 明确不做什么

- 不做正式 Apple Developer ID 签名。
- 不做 notarization。
- 不做 DMG。
- 不做 auto updater。
- 不移除用户 Dock 设置，除非有明确迁移说明。

### 涉及关键文件

- `scripts/package-app.sh`
- `scripts/build.sh`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `docs/install.md`
- `docs/release_checklist.md`
- `docs/known_issues.md`

### 验收标准

- 默认 `./scripts/package-app.sh --sandbox` 生成 no-Dock agent 包。
- 可选 `--dock-app` 生成 Dock App 包。
- package 日志清楚打印 Dock mode 和 `LSUIElement`。
- `plutil` 输出与 package 参数一致。
- no-Dock 包启动后 Dock 不出现；Dock App 包启动后 Dock 出现。
- 两种包下菜单栏搜索、设置、退出、热键均可用。

### 必须补的测试 / 手测 / release checklist

- 自动化：
  - package 参数解析测试或脚本自检。
  - plist key 检查。
- 手测：
  1. package 默认包。
  2. 启动后 Dock 不出现。
  3. 菜单栏入口可用。
  4. package `--dock-app` 包。
  5. 启动后 Dock 出现。
  6. 菜单栏入口仍可用。
- release checklist：
  - 明确两个 package 模式的独立 gate。

## N3：设置页 Dock 模式修复与用户自救路径

### 阶段目标

如果用户 DB 已经被 `dock_icon_visible=1` 或旧状态污染，用户可以在 UI 中恢复菜单栏模式，不需要手工 `sqlite3`。

### 明确做什么

- 设置页 Dock 区域明确显示：
  - 当前意图：显示 Dock / 隐藏 Dock
  - 当前有效状态：`.regular` / `.accessory`
  - package plist 状态：`LSUIElement=true/false`
  - 生效时机：立即 / 重启后
- 提供“一键恢复菜单栏模式 / 隐藏 Dock”能力。
- 如果需要重启生效，提示必须可操作：
  - 菜单栏 → 退出 SwiftSeek
  - 重新打开当前 Diagnostics 显示的 bundle path
  - 如运行旧 `/Applications` bundle，提示用户替换或打开正确 bundle
- 诊断信息和设置页文案保持一致。
- malformed / missing setting fallback 到隐藏 Dock，并显示保守默认。

### 明确不做什么

- 不要求用户手工编辑 SQLite。
- 不删除 Dock App 模式。
- 不把旧 DB 静默改写为隐藏 Dock。
- 不做 installer / updater。

### 涉及关键文件

- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/install.md`
- `docs/known_issues.md`
- `docs/manual_test.md`

### 验收标准

- 用户能在设置页直接看懂为什么当前 Dock 出现。
- 用户能一键把意图恢复为菜单栏模式。
- 需要重启时，UI 说清楚下一步。
- N1 Diagnostics 与设置页显示一致。
- 不存在“设置改了但用户不知道是否生效”的状态。

### 必须补的测试 / 手测 / release checklist

- Smoke：
  - reset helper 把 `dock_icon_visible` 设回 false。
  - malformed setting fallback 到隐藏 Dock。
  - Diagnostics 与 setting 一致。
- 手测：
  - 旧 DB `dock_icon_visible=1` 启动。
  - 设置页点击恢复菜单栏模式。
  - 退出重启。
  - Dock 不再出现。

## N4：真实 `.app` 手测 gate 与最终收口

### 阶段目标

把 Dock 是否隐藏变成 release gate，确保当前轨道可被 Codex 判定 `PROJECT COMPLETE`。

### 明确做什么

- release checklist 增加 Dock hardening gate：
  - fresh DB。
  - existing DB with `dock_icon_visible=1`。
  - existing DB with `dock_icon_visible=0`。
  - no-Dock package。
  - Dock App package。
  - stale bundle check。
  - menu bar search / settings / quit。
  - hotkey。
  - Info.plist `LSUIElement`。
  - Diagnostics Dock block。
- `docs/install.md` 写清：
  - 如何确认自己运行的是 no-Dock 包。
  - 如何确认 `LSUIElement`。
  - 如何恢复 Dock 包。
  - 如何隐藏 Dock。
  - 如何处理旧 bundle。
- README / known_issues / manual_test / architecture 同步到最终状态。
- `docs/codex_acceptance.md` 记录 N1-N4 验收链路。

### 明确不做什么

- 不做正式签名 / 公证。
- 不做 DMG。
- 不做 auto updater。
- 不承诺绕过 macOS LaunchServices 缓存。

### 涉及关键文件

- `docs/release_checklist.md`
- `docs/install.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/architecture.md`
- `docs/codex_acceptance.md`
- `docs/stage_status.md`
- `README.md`
- `scripts/package-app.sh`

### 验收标准

- 真实 `dist/SwiftSeek.app` 验证 no-Dock 默认路径。
- 真实 Dock App 包验证可选显示 Dock 路径。
- fresh DB 和旧 DB 两类状态都被验证。
- `dock_icon_visible=1` 的场景不再被误判为实现失败，Diagnostics 能说明。
- 用户能从 README / install / Diagnostics 判断自己运行的包是否正确。
- Codex 可据此判断 `everything-dockless-hardening` 为 `PROJECT COMPLETE`。

### 必须补的测试 / 手测 / release checklist

- 构建：`swift build --disable-sandbox`
- Smoke：`swift run --disable-sandbox SwiftSeekSmokeTest`
- Package：
  - `./scripts/package-app.sh --sandbox`
  - `./scripts/package-app.sh --sandbox --dock-app` 或最终实现的等价参数
- Plist：
  - `plutil -p dist/SwiftSeek.app/Contents/Info.plist`
- 手测：
  1. no-Dock 包启动后 Dock 不出现。
  2. 菜单栏图标出现。
  3. 菜单栏搜索成功。
  4. 菜单栏设置成功。
  5. 全局热键成功。
  6. 菜单栏退出成功。
  7. `dock_icon_visible=1` 旧 DB 能被诊断并可恢复。
