# Everything File Manager Integration Gap

本文基于当前代码审计 SwiftSeek 在 Reveal target / Finder hardcode / QSpace / 自定义文件管理器集成上的差距。它不是实现说明，而是 M 轨道立项依据。

## 审计依据

- `Sources/SwiftSeekCore/ResultAction.swift`：`ResultAction` 仍是 `open` / `revealInFinder` / `copyPath`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`：`.revealInFinder` 直接调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`
- `Sources/SwiftSeek/UI/SearchViewController.swift`：按钮和右键菜单标题为“在 Finder 中显示”
- `Sources/SwiftSeekCore/SettingsTypes.swift`：没有 reveal target / custom app / external open mode 设置键
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`：常规设置页没有“显示位置 / Reveal Target”配置
- `docs/release_checklist.md` 与 `docs/manual_test.md`：仍只覆盖 Finder reveal，未覆盖 QSpace/custom app/fallback

## Gap 1：Reveal 行为硬编码 Finder

- 当前现状：`ResultActionRunner.perform(.revealInFinder)` 直接调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`，这是 Finder 专用的“选中并显示”路径。
- 为什么是问题：用户不能把“显示位置”改成 QSpace、Path Finder、ForkLift 或任意自定义文件管理器。
- 用户影响：SwiftSeek 作为文件搜索入口时，用户仍被迫回到 Finder，无法接入自己的文件管理器工作流。
- 推荐优先级：高。
- 建议解决阶段：M2。

## Gap 2：QSpace / 自定义 App 不可配置

- 当前现状：`SettingsTypes.swift` 没有 `reveal_target_type`、`reveal_custom_app_path`、`reveal_external_open_mode`；设置页也没有选择 `.app` 的 UI。
- 为什么是问题：即使底层能调用外部 app，也没有持久化配置入口。
- 用户影响：用户无法指定 `/Applications/QSpace.app` 或其它文件管理器，体验仍停在 Finder-only。
- 推荐优先级：高。
- 建议解决阶段：M1。

## Gap 3：UI 文案硬编码 Finder

- 当前现状：搜索窗口 action button 写“在 Finder 中显示”；右键菜单也写“在 Finder 中显示”；hint 仍是通用 `Reveal`，没有跟随目标 app。
- 为什么是问题：一旦用户选了 QSpace 或自定义 app，底层行为和 UI 文案会不一致，用户不知道当前会打开哪里。
- 用户影响：配置可信度下降；用户可能误以为仍会进入 Finder。
- 推荐优先级：高。
- 建议解决阶段：M3。

## Gap 4：外部 App 不存在 / 被移动 / 不能打开时缺少 fallback

- 当前现状：因为还没有 custom app 模式，所以也没有 app path 校验、打开失败反馈、fallback 到 Finder、NSLog 记录等路径。
- 为什么是问题：用户选择 `/Applications/QSpace.app` 后，QSpace 可能被移动、删除、重命名或无法处理目标 URL。
- 用户影响：如果实现成 silent fail，用户点击“显示”会没有任何反馈；如果没有 fallback，会破坏关键文件定位动作。
- 推荐优先级：高。
- 建议解决阶段：M2-M3。

## Gap 5：Finder 的“选中文件”和外部 App 的“打开 URL”语义不等价

- 当前现状：Finder 模式可以通过 `activateFileViewerSelecting` 选中文件。通用外部 app 模式只能稳妥地调用公开 API 打开文件 URL 或父目录 URL，是否选中具体文件由外部 app 决定。
- 为什么是问题：如果文档继续承诺“选中文件”，自定义 app 模式会过度承诺。
- 用户影响：用户可能期望 QSpace 中也一定高亮选中文件，但实际可能只是打开父目录或文件本身。
- 推荐优先级：高。
- 建议解决阶段：M1-M3。

## Gap 6：不应硬接未知 QSpace 私有协议

- 当前现状：当前代码未接 QSpace；这反而避免了错误硬编码。但新需求如果直接写死未知 bundle id 或 URL scheme，会制造维护风险。
- 为什么是问题：QSpace 的 bundle id、URL scheme、AppleScript 支持不应在未验证前写成事实；私有协议或脚本接口可能版本漂移。
- 用户影响：用户装的是不同版本或不同发行渠道的 QSpace 时，功能可能失效。
- 推荐优先级：高。
- 建议解决阶段：M1-M2。

## Gap 7：手测与 release gate 缺失

- 当前现状：release checklist 只覆盖 Finder 场景；manual test 中 J5 仍要求“在 Finder 中显示”弹出并选中文件。
- 为什么是问题：外部文件管理器集成属于 GUI + 外部 app 行为，无法完全靠 smoke 覆盖，必须进入 release gate。
- 用户影响：后续容易出现 Finder 模式可用、QSpace/custom app 模式回归却没人发现。
- 推荐优先级：中。
- 建议解决阶段：M3-M4。

## Gap 8：Diagnostics 未暴露 reveal target

- 当前现状：About / diagnostics 已暴露 build、DB、settings、root health、Launch at Login 等状态，但没有 reveal target。
- 为什么是问题：用户反馈“为什么还是打开 Finder”时，协作者无法从诊断信息判断当前选择的是 Finder、QSpace 还是失效的 custom app path。
- 用户影响：排查成本高，容易误判为代码没更新或 stale bundle。
- 推荐优先级：中。
- 建议解决阶段：M3。
