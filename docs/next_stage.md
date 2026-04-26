# 下一阶段任务书：M3

当前活跃轨道：`everything-filemanager-integration`

当前阶段：`M3`

任务性质：交给 Claude 执行的实现任务书。M3 只做 Reveal target 的动态文案、诊断信息、fallback 展示打磨和手测 / release gate 同步。M2 的实际执行路由已经通过，不要重写执行核心。

## 背景

M1 已完成 Reveal Target 数据模型与设置 UI。

M2 已完成实际 reveal 路由：

- Finder 模式继续用 `NSWorkspace.shared.activateFileViewerSelecting([url])`。
- 自定义 App 模式使用公开 `NSWorkspace.open([targetURL], withApplicationAt: appURL, configuration:)`。
- `.item` / `.parentFolder` 目标 URL 解析已由 `RevealResolver` 覆盖。
- app path 空、失效、非 `.app`、打开失败都会 fallback 到 Finder。
- custom app 打开失败 fallback 已修正为回到原始 target URL，而不是 parentFolder resolved URL。
- reveal 不增加 Run Count。

当前剩余问题是用户可见层仍不完整：

- 搜索窗口按钮仍写“在 Finder 中显示”。
- 右键菜单仍写“在 Finder 中显示”。
- hint / diagnostics / manual test / release checklist 还不能完整表达当前 reveal target。

## M3 目标

让用户选择 Finder / QSpace / 自定义 App 后，搜索窗口文案、右键菜单、hint、diagnostics、fallback 提示和手测 / release gate 都能反映当前 reveal target。

## 必须做

1. 动态显示名称 helper
   - 增加可纯测 helper，用于把 `RevealTarget` + custom app path 显示成用户可读名称。
   - Finder：`Finder`
   - 文件名包含 `qspace`（大小写不敏感）：`QSpace`
   - 其它 `.app`：去掉 `.app` 后显示 app 名称，例如 `Path Finder.app` → `Path Finder`
   - 空 / 失效 custom app path：显示“自定义 App”或等价清晰文案，不能崩。

2. 搜索窗口按钮动态文案
   - Finder：`在 Finder 中显示`
   - QSpace：`在 QSpace 中显示`
   - 其它自定义 App：`在 <AppName> 中显示`
   - 配置变化后，搜索窗口重新出现或刷新时应反映最新设置。

3. 右键菜单动态文案
   - 与按钮文案同源，避免按钮和菜单不一致。

4. hint 文案同步
   - 不能继续只表达 Finder-only 语义。
   - 可以保留快捷键提示，但 reveal action 名称要跟随当前 target 或使用中性“显示位置”。

5. fallback 提示打磨
   - 保留 M2 的 toast，但让文案更贴近实际目标，例如：
     - `无法用 QSpace 显示，已回退到 Finder：<reason>`
     - `无法用 <AppName> 显示，已回退到 Finder：<reason>`
   - 不允许 silent fail。

6. diagnostics / About 信息
   - Diagnostics 增加 reveal target 字段：
     - target type
     - custom app path
     - app display name
     - external open mode
   - About / 复制诊断信息中能看出当前 reveal target。

7. 文档与 release gate
   - 更新 `docs/manual_test.md`：
     - Finder 模式
     - QSpace / custom app 模式
     - app path 失效 fallback
     - `.item` / `.parentFolder` 差异
     - reveal 不增加 Run Count
   - 更新 `docs/release_checklist.md`，把上述场景变成发布前必须确认项。
   - 更新 `docs/known_issues.md`，去掉已经落地的限制，保留真实边界：外部 app 不保证选中文件、不使用私有 API。

## 明确不做

- 不做 QSpace 私有 API。
- 不硬编码未知 QSpace bundle id。
- 不假设 QSpace URL scheme。
- 不做 AppleScript。
- 不改变 macOS 系统默认文件管理器。
- 不让 reveal 计入 Run Count。
- 不做 M4 最终 PROJECT COMPLETE 收口；M3 通过后再进入 M4。

## 关键文件

- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeekCore/RevealResolver.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/release_checklist.md`
- `docs/known_issues.md`
- `docs/codex_acceptance.md`
- `docs/stage_status.md`

## 验收标准

- Finder 模式按钮 / 右键菜单仍显示“在 Finder 中显示”。
- 选择 QSpace 后按钮 / 右键菜单显示“在 QSpace 中显示”。
- 选择其它 app 后显示 app 名称。
- fallback toast 能说清楚“哪个 app 失败，已回退 Finder”。
- diagnostics 可判断当前 reveal target。
- manual test / release checklist 覆盖真实 GUI 场景。
- reveal 仍不增加 Run Count。
- 不出现 QSpace 私有 API、bundle id、URL scheme、AppleScript。

## 必须运行的检查

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift build --disable-sandbox

HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekSmokeTest

HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/package-app.sh --sandbox
```

## 必须手测

1. Finder 模式：按钮和右键菜单显示“在 Finder 中显示”，点击后 Finder 选中目标。
2. QSpace/custom app 模式：按钮和右键菜单显示目标 app 名称，点击后外部 app 收到目标 URL。
3. app path 失效：点击后出现 fallback 提示，并回退 Finder。
4. `.item` / `.parentFolder`：分别验证目标 URL 语义。
5. reveal 前后 Run Count 不变；“打开”动作仍增加 Run Count。
6. About / 复制诊断信息包含 reveal target 状态。
