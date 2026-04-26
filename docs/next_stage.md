# 下一阶段任务书：M2

当前活跃轨道：`everything-filemanager-integration`

当前阶段：`M2`

任务性质：交给 Claude 执行的实现任务书。M2 只把 M1 的 Reveal Target 配置接入实际“显示位置”动作，并补对应 helper / smoke / 文档。动态按钮文案、diagnostics、完整 release gate 留到 M3。

## 背景

M1 已通过 Codex 验收：

- `RevealTargetType` / `ExternalRevealOpenMode` / `RevealTarget` 已落地。
- DB settings 已有 `reveal_target_type` / `reveal_custom_app_path` / `reveal_external_open_mode`。
- 设置页已经能选择 Finder / 自定义 App、选择 `.app`、保存 `item` / `parentFolder`。
- 保存失败三条路径都会弹 `NSAlert`，不会只写日志。

当前真实 reveal 路径仍是 Finder-only：

- `ResultActionRunner.perform(.revealInFinder)` 仍直接调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`。
- 搜索窗口按钮和右键菜单仍写“在 Finder 中显示”。

## M2 目标

让“显示位置”动作真正读取 M1 的配置：

- Finder 模式继续保持现有 Finder 选中文件行为。
- 自定义 App 模式用公开 macOS API 打开目标 URL。
- 外部 App 配置失效时给用户可见反馈，并 fallback 到 Finder。
- reveal / show 不增加 Run Count。

## 必须做

1. 接入配置读取
   - 从 `Database.getRevealTarget()` 读取当前 reveal target。
   - 现有调用链如果拿不到 `Database`，可以新增最小必要参数或 helper，但不要做大范围架构重写。

2. 保留 Finder 行为
   - `RevealTarget.type == .finder` 时继续调用：
     `NSWorkspace.shared.activateFileViewerSelecting([url])`
   - Finder 模式必须仍能在 Finder 中选中文件。

3. 实现自定义 App 模式
   - `RevealTarget.type == .customApp` 时读取 `customAppPath`。
   - 校验 path：
     - 非空
     - 路径存在
     - 是 `.app` bundle
   - 根据 `openMode` 解析目标：
     - `.item`：目标文件 / 目录本身
     - `.parentFolder`：如果目标是文件，打开父目录；如果目标本身是目录，可打开该目录或按 helper 明确处理，必须有测试说明
   - 使用公开 API，例如：
     `NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: ..., completionHandler: ...)`

4. 失败处理与 fallback
   - custom app path 空、缺失、不是 `.app`、不存在、打开失败时：
     - 给用户可见反馈（alert / status label /现有 UI 可承载的错误提示均可，但不能 silent fail）
     - `NSLog` 记录 app path、target path、open mode、错误原因
     - fallback 到 Finder 的 `activateFileViewerSelecting`
   - fallback 后用户仍能定位文件。

5. 不影响 Run Count
   - 只有 `.open` 成功才记录 `file_usage.open_count`。
   - reveal / show 无论 Finder、custom app、fallback，都不能增加 Run Count。

6. 补 smoke / helper 测试
   - 抽出可纯测的 helper，覆盖：
     - `.item` 目标 URL 解析
     - `.parentFolder` 目标 URL 解析
     - custom app path 空 / 不存在 / 非 `.app` 的验证结果
     - fallback decision
     - reveal 不触发 `recordOpen`
   - GUI / 外部 app 真实打开可以留给手测，但纯逻辑必须进 smoke。

## 明确不做

- 不做 QSpace 私有 API。
- 不硬编码未知 QSpace bundle id。
- 不假设 QSpace URL scheme。
- 不做 AppleScript。
- 不改变系统默认文件管理器。
- 不把 reveal 计入 Run Count。
- 不把 M3 动态文案、diagnostics、release checklist 全量收口提前做完；如需加最小错误提示可以做，但不要扩大成 M3。

## 关键文件

- `Sources/SwiftSeekCore/ResultAction.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/PathHelpers.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/manual_test.md`
- `docs/codex_acceptance.md`
- `docs/stage_status.md`

## 验收标准

- Finder 模式行为不回退：仍调用 Finder 专用 reveal，能选中文件。
- custom app 模式能按 `.item` / `.parentFolder` 选择正确 URL 并交给用户选择的 `.app`。
- app path 空、失效、非 `.app`、打开失败时有可见反馈、NSLog，并 fallback 到 Finder。
- reveal / show 不增加 `open_count`。
- 不出现 QSpace bundle id / URL scheme / AppleScript / private API。
- SmokeTest 覆盖 M2 纯逻辑，且总数增加。

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

1. Finder 模式：搜索结果点击“在 Finder 中显示”，Finder 打开并选中目标。
2. 自定义 App + `parentFolder`：选择 `/Applications/QSpace.app` 或任意 `.app`，点击显示，外部 app 收到父目录 URL。
3. 自定义 App + `item`：点击显示，外部 app 收到文件 / 目录本身 URL。
4. 失效 app path：移动 / 删除 / 手动写坏 path 后点击显示，有可见错误提示，并 fallback 到 Finder。
5. reveal 前后同一文件的 Run Count 不变化；只有“打开”动作增加 Run Count。
