# SwiftSeek Everything-ux-parity Gap

本文件基于当前代码审计，记录 SwiftSeek 与更成熟 Everything-like 桌面体验之间仍存在的差距。`everything-usage` 已完成 usage 数据链路，但这不等于用户已经稳定感知到 Run Count，也不等于 macOS App 生命周期已经成熟。

## 1. 设置窗口关闭后不可重新打开

- 当前现状：用户已复现：点击设置窗口左上角关闭后，再次无法正常打开设置，只能 Dock 右键退出后重启。静态代码上，`AppDelegate.showSettings(_:)` 会复用 `settingsWindowController` 并调用 `showWindow`；`SettingsWindowController` 设置了 `window.isReleasedWhenClosed = false`。但当前没有 `windowShouldClose` hide-only 策略，也没有 `applicationShouldHandleReopen(_:hasVisibleWindows:)` 兜底。
- 为什么是问题：这属于桌面 App 基础生命周期 bug。设置页承载 roots、exclude、hotkey、DB 维护、usage history 等核心入口，一旦关闭后不可恢复，用户会认为 App 卡死或功能丢失。
- 用户影响：用户必须退出重开才能继续改设置；会直接破坏长期工具信任度。
- 推荐优先级：高。
- 建议解决阶段：J1。

## 2. Dock / Menu Bar / 主菜单 reopen 行为不完整

- 当前现状：`MainMenu` 和 status item 都有“设置…”和“搜索…”入口；`applicationShouldTerminateAfterLastWindowClosed` 返回 false；search panel 用 `orderOut` 隐藏。但 `AppDelegate` 没有实现 `applicationShouldHandleReopen`，Dock 点击在无可见窗口时没有明确产品行为。
- 为什么是问题：macOS 工具类 App 应该允许所有窗口关闭后继续运行，并能通过 Dock、菜单栏或主菜单重新唤起。当前代码更像“有入口”，但 reopen 生命周期没有形成完整闭环。
- 用户影响：用户关闭窗口后不知道怎么恢复，或者不同入口行为不一致。
- 推荐优先级：高。
- 建议解决阶段：J1。

## 3. Run Count 可见性不足

- 当前现状：代码层已经存在 usage 数据模型和 UI 字段：`Schema` v6 有 `file_usage`；`Database.recordOpen(path:)` 写入 `open_count` / `last_opened_at`；`SearchEngine` 通过 `LEFT JOIN file_usage` 填充 `SearchResult.openCount` / `lastOpenedAt`；`SearchViewController` 创建了“打开次数”和“最近打开”两列。但用户反馈“启动次数 / Run Count”没看到，说明当前可见性仍需复核。
- 为什么是问题：Everything-like 的 Run Count 是用户能直接感知的行为信息，不只是 DB 里有字段。若列太靠右、宽度太窄、默认不可见、文案不符合用户预期、打开动作未命中当前索引路径，或用户运行的是旧二进制，实际体验仍等同于没有。
- 用户影响：用户无法确认高频文件是否被记录，也无法理解 `recent:` / `frequent:` 的来源。
- 推荐优先级：高。
- 建议解决阶段：J2。

## 4. 搜索历史和 Saved Filters 缺失

- 当前现状：当前代码支持 `recent:` / `frequent:`，但没有查询历史模型、最近查询列表、保存当前查询、Saved Filters 或快速过滤器入口。
- 为什么是问题：Everything-like 工具常见的高频体验不是只靠“文件打开历史”，还包括复用查询表达式、快速切换常用筛选、回到最近查询。
- 用户影响：用户需要重复输入同样的 `ext:` / `path:` / `root:` 组合，使用成本偏高。
- 推荐优先级：中。
- 建议解决阶段：J4。

## 5. wildcard / quote / OR / NOT 查询语法缺失

- 当前现状：`SearchEngine.parseQuery` 支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:`，以及裸 `recent:` / `frequent:`。plain query 仍按空白分词 AND。当前没有 `*` / `?` wildcard，没有 quoted phrase，没有 `foo|bar` OR，也没有 `!foo` / `-foo` NOT。
- 为什么是问题：Everything-like 文件搜索的核心体验之一是更强的查询表达能力。当前 DSL 能做基础过滤，但还不能表达常见的模糊模式、短语、排除和二选一。
- 用户影响：复杂搜索需要多次尝试，无法一次表达“包含 A 或 B、排除 C、匹配短语或模式”。
- 推荐优先级：中。
- 建议解决阶段：J3。

## 6. 结果上下文菜单动作不足

- 当前现状：`SearchViewController.buildRowContextMenu()` 只有 Open、Reveal in Finder、Copy Path、Move to Trash。没有 Open With、Copy Name、Copy Parent Folder、Copy Full Path 的清晰区分、多选 Copy Multiple Paths、Rename 等成熟文件搜索器常见动作。
- 为什么是问题：Everything-like 工具常被当作文件操作入口，而不仅是“打开文件”的 launcher。右键菜单贫弱会让用户频繁跳回 Finder。
- 用户影响：复制文件名、复制父目录、选择打开方式、重命名等常见动作不顺手。
- 推荐优先级：中。
- 建议解决阶段：J5。

## 7. Full Disk Access / 首次使用引导不足

- 当前现状：`SettingsWindowController` 有 roots 为空时的顶部引导条，提示添加索引目录和热键；但没有完整首次使用流程，没有集中解释 Full Disk Access、无法访问 root 的修复路径、compact/fullpath 模式取舍、Run Count 语义。
- 为什么是问题：文件搜索器第一次使用高度依赖权限、root、索引模式和后台索引状态。缺少引导会让用户把“没搜到”误解为搜索坏了。
- 用户影响：用户可能不知道为什么某些目录不可搜索，也不知道 Run Count 只统计 SwiftSeek 内部 open。
- 推荐优先级：中。
- 建议解决阶段：J6。

## 8. 窗口状态与用户偏好记忆不足

- 当前现状：结果表排序和列宽已持久化；设置窗口位置、大小、当前 tab，搜索窗口位置、大小、最近输入、列可见性 / 默认列重置等桌面习惯状态还没有系统化。
- 为什么是问题：长期使用工具需要“记住我怎么用”。当前已经保存了部分结果表状态，但窗口级别和查询级别还不完整。
- 用户影响：用户重复调整窗口和列布局；Run Count 列即使存在，也可能因历史列宽状态而不明显。
- 推荐优先级：低到中。
- 建议解决阶段：J2 / J4 / J6。

## 9. macOS 语义边界仍需在 UX 中明确

- 当前现状：代码和文档已明确 Run Count 只来自 SwiftSeek 内部 `.open`，不读取 macOS 全局启动次数。当前交付仍是 SwiftPM / release executable 路径，没有正式 `.app` bundle + signing + notarization。
- 为什么是问题：用户说“启动次数”时可能以为是系统全局统计。Launch at Login、权限引导、Dock 行为也会受到 app bundle、签名和登录项 API 约束。
- 用户影响：如果 UI 文案不清楚，用户会把 SwiftSeek 内部打开次数误认为系统级 Run Count，或期待未签名 SwiftPM 产物具备完整 macOS 登录项体验。
- 推荐优先级：中。
- 建议解决阶段：J2 / J6。
