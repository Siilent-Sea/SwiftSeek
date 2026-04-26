# 下一阶段任务书：M1

当前活跃轨道：`everything-filemanager-integration`

当前阶段：`M1`

任务性质：交给 Claude 执行的实现任务书。M1 只做 Reveal Target 数据模型与设置 UI，不提前替换 `ResultActionRunner` 的实际执行路径。

## 背景

当前 SwiftSeek 的“显示”动作仍是 Finder-only：

- `ResultAction` 枚举 case 是 `revealInFinder`
- `ResultActionRunner.perform(.revealInFinder)` 直接调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`
- 搜索窗口按钮和右键菜单都写“在 Finder 中显示”
- 设置模型里没有 reveal target / custom app / external open mode

用户希望能在设置里选择“在 QSpace 中显示”，同时支持更通用的自定义文件管理器 App。M1 先建立配置模型和 UI，默认仍为 Finder，保证向后兼容。

## M1 目标

在设置里增加“显示位置 / Reveal Target”配置，支持 Finder 与自定义 App 的持久化选择，并定义外部 App 打开目标模式。M1 不做实际外部 app 打开。

## 必须做

1. 新增设置项
   - `reveal_target_type`
   - `reveal_custom_app_path`
   - `reveal_external_open_mode`

2. 新增推荐类型
   - `RevealTarget`
   - `RevealTargetType`
   - `ExternalRevealOpenMode`

3. 默认行为
   - target = Finder
   - open mode = `parentFolder` 或 `item`，必须写清取舍
   - missing / malformed settings fallback 到 Finder

4. 设置页 UI
   - 添加“显示位置”区域
   - 提供 Finder / 自定义 App 选择
   - 提供“选择 App…”按钮，使用公开 `NSOpenPanel` 选择 `.app`
   - 显示当前已选 app 名称和路径
   - 提供打开目标选项：文件本身 / 父目录

5. QSpace 支持方式
   - 不硬编码未知 bundle id
   - 不假设 URL scheme
   - 支持用户选择 `/Applications/QSpace.app`
   - 如果 app 名称包含 QSpace，可以在 UI 中显示为 QSpace

6. 补 smoke
   - 默认 Finder
   - custom app path round-trip
   - open mode round-trip
   - malformed target/open mode fallback

## 明确不做

- 不改 `ResultActionRunner`
- 不做实际外部 app 打开
- 不用 QSpace 私有 API
- 不硬编码未经验证的 QSpace bundle id / URL scheme
- 不改变 Finder reveal 当前行为
- 不改搜索、索引、DB schema、Run Count、menu bar agent、single-instance

## 关键文件

- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/known_issues.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/next_stage.md`

## 验收标准

- fresh DB 读取 reveal target 返回 Finder 默认
- target type / custom app path / open mode 可以 round-trip
- malformed settings fallback 到 Finder，不崩
- 设置页能选择 Finder / 自定义 App
- 设置页能显示当前 app 名称和路径
- 文案明确 QSpace 是通过用户选择 `.app` 支持，不依赖私有协议
- `ResultActionRunner` 仍未接 custom app，不假装已经支持 QSpace 打开

## 必须运行的检查

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift build --disable-sandbox

HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekSmokeTest
```

## 必须手测

1. 打开设置 → 常规
2. 默认“显示位置”为 Finder
3. 切到“自定义 App…”
4. 选择 `/Applications/QSpace.app` 或任意 `.app`
5. UI 显示 app 名称和完整路径
6. 切换“文件本身 / 父目录”并重开设置，值保持
7. 切回 Finder，重开设置后仍是 Finder
8. 不要求点击搜索结果后真的打开 QSpace；这是 M2 范围
