# SwiftSeek Everything-ux-parity 任务书

目标：在 `everything-usage` 已完成的基础上，继续补齐 SwiftSeek 作为 macOS 桌面工具的 Everything-like 使用体验。当前轨道不再证明“能搜得快 / DB 可维护 / usage 数据存在”，而是解决用户实际可感知的窗口生命周期、Run Count 可见性、查询表达、搜索历史、上下文菜单和首次使用问题。

硬约束：
- 当前轨道固定为 `everything-ux-parity`
- 阶段固定为 `J1` 到 `J6`
- Run Count 只表示通过 SwiftSeek 成功 `.open` 的次数
- 不读取 macOS 全局启动次数
- 不使用 private API
- 不扫描系统隐私数据
- 不把 SwiftPM 未签名可执行文件伪装成完整签名 `.app` 交付
- 每次只做当前阶段，不允许提前实现后续阶段

---

## J1：设置窗口与 App 生命周期修复

### 阶段目标
修复用户当前复现的高优先级 bug：设置窗口点左上角关闭后无法重新打开。让 SwiftSeek 的 Dock、Menu Bar、主菜单和窗口关闭行为达到可信的 macOS 工具 App 基线。

### 明确做什么
- 复现并修复设置窗口点左上角关闭后无法重新打开的问题。
- 重点审查并修复：
  - `AppDelegate.showSettings(_:)`
  - `SettingsWindowController`
  - `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)`
  - `NSWindow.isReleasedWhenClosed`
  - `windowShouldClose`
  - 主菜单“设置…”入口
  - 菜单栏“设置…”入口
  - Dock 图标点击行为
- 推荐实现方向：
  - 设置窗口关闭按钮只隐藏窗口，不销毁 controller。
  - 或关闭后 `AppDelegate` 能安全重新创建 `SettingsWindowController`。
  - 实现 Dock reopen：无可见窗口时重新显示设置或搜索入口。
- 确认搜索窗口 `toggle` / `hide` / `show` 行为没有被设置窗口修复带出回归。
- 补充 `docs/manual_test.md` 的 J1 手测流程。
- 能 headless 覆盖的生命周期判断补到 smoke；不能自动化的 GUI 行为必须写手测。

### 明确不做什么
- 不做 Run Count UI 改版。
- 不做查询语法。
- 不做搜索历史 / Saved Filters。
- 不做上下文菜单扩展。
- 不做首次使用完整向导。
- 不做大规模 UI 重写。

### 涉及关键文件
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/App/MainMenu.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/next_stage.md`

### 验收标准
1. 启动 App 后设置窗口可正常出现。
2. 点设置窗口左上角关闭后，从菜单栏图标“设置…”可以再次打开。
3. 点设置窗口左上角关闭后，从主菜单 `SwiftSeek -> 设置…` 可以再次打开。
4. 所有窗口都不可见时，点击 Dock 图标可以重新唤起可操作窗口或明确的搜索 / 设置入口。
5. 重复 10 次关闭 / 打开设置窗口，不崩溃、不丢 controller、不出现菜单入口失效。
6. 搜索窗口通过热键、主菜单、菜单栏呼出仍正常；ESC / 失焦隐藏行为没有回归。
7. `swift build` 和 `swift run SwiftSeekSmokeTest` 通过，或记录环境阻塞原因。
8. `docs/manual_test.md` 明确记录 J1 GUI 手测步骤。

### 必须补的测试 / benchmark / 手测
- smoke：若能抽象出 controller 生命周期逻辑，覆盖关闭后可重新 show 的路径。
- smoke：MainMenu / status item selector 不失效的轻量检查，如当前架构可行。
- 手测：启动 App，设置窗口出现。
- 手测：点 × 关闭设置窗口。
- 手测：从菜单栏图标打开设置，必须成功。
- 手测：从主菜单打开设置，必须成功。
- 手测：点击 Dock 图标，必须能重新唤起可操作窗口。
- 手测：重复 10 次关闭 / 打开，不崩溃、不失效。

---

## J2：Run Count 可见性与结果列体验复核

### 阶段目标
解决用户“没看到启动次数 / Run Count”的体验问题。即使 H1-H5 已经落地数据链路，也要以用户可见性为准重新验收。

### 明确做什么
- 审计 H1-H5 usage 实现是否在当前 GUI 中真实可见：
  - `file_usage.open_count` 是否写入
  - `file_usage.last_opened_at` 是否写入
  - `SearchEngine` 是否 join usage 数据
  - `SearchResult.openCount` / `lastOpenedAt` 是否进入 UI
  - 结果表是否有“打开次数 / 最近打开”列
  - 列宽是否默认可见
  - 列是否可能被历史持久化宽度压到太窄
  - 文案是否需要同时标注 “Run Count / 打开次数”
  - 用户运行的 release 二进制是否可能不是最新构建
- 若已经实现但默认不可见 / 太窄 / 文案不清，修正 UI。
- 增加“恢复默认列宽”或等价恢复入口，解决持久化列宽导致用户看不到列的问题。
- 明确 Run Count 语义：只统计 SwiftSeek 内部成功 `.open`，不统计 Reveal / Copy / 系统全局打开。

### 明确不做什么
- 不读取 macOS 全局历史。
- 不做 ML 排序。
- 不改变 H2 的相关性边界：usage 只能做同 score tie-break，不能压过高相关结果。
- 不做最近打开独立页面，留给 J4 或后续。

### 涉及关键文件
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/UsageTypes.swift`
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. 通过 SwiftSeek 打开某文件 3 次后，搜索该文件可见“打开次数”为 3。
2. “最近打开”时间随成功 open 更新。
3. fresh DB / 从未打开文件显示为清晰的空值，如 `—`。
4. 默认列宽下“打开次数 / 最近打开”无需横向滚动或极端拉宽即可看见。
5. 历史列宽异常时有恢复默认列宽的路径。
6. 文档和 UI 都明确 Run Count 不是 macOS 全局启动次数。
7. `recent:` / `frequent:` 结果与显示列一致。

### 必须补的测试 / benchmark / 手测
- smoke：`recordOpen` 后 `SearchResult.openCount` / `lastOpenedAt` 更新。
- smoke：列宽设置 round-trip 和默认值恢复，如 UI 层可自动化。
- 手测：打开某文件 3 次，再搜索，显示 3。
- 手测：清空 usage 后列回到 `—` 或 0 状态。
- 手测：旧列宽状态下恢复默认列宽。

---

## J3：查询语法增强：wildcard / quote / OR / NOT

### 阶段目标
补齐 Everything 风格常用查询表达能力，让用户可以更精确地表达文件名匹配、短语、二选一和排除。

### 明确做什么
- 支持 `*` wildcard。
- 支持 `?` wildcard。
- 支持 quoted phrase，例如 `"foo bar"`。
- 支持 OR，例如 `foo|bar`。
- 支持 NOT，例如 `!foo` 或 `-foo`。
- 保持与既有语法兼容：
  - `ext:`
  - `kind:`
  - `path:`
  - `root:`
  - `hidden:`
  - `recent:`
  - `frequent:`
- 定义清楚优先级和容错策略。
- GUI 和 CLI 搜索语义一致。
- 更新 docs / manual test。

### 明确不做什么
- 不做完整括号表达式。
- 不做 regex。
- 不做全文搜索。
- 不做 AI 语义搜索。
- 不牺牲 F1/G5 已验证的热路径性能；必要时对复杂语法做候选集后过滤。

### 涉及关键文件
- `Sources/SwiftSeekCore/SearchEngine.swift`
- `Sources/SwiftSeekCore/Gram.swift`
- `Sources/SwiftSeekSearch/main.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `Sources/SwiftSeekBench/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. `foo*` / `f?o` 等 wildcard 能按预期匹配。
2. `"foo bar"` 作为短语匹配，不被空格拆成两个独立 AND token。
3. `foo|bar` 返回包含 foo 或 bar 的结果。
4. `foo !bar` 或 `foo -bar` 排除 bar。
5. 与 `ext:` / `path:` / `recent:` / `frequent:` 组合时语义明确。
6. 非法语法不崩溃，能容错为字面量或空结果。
7. 大库下复杂语法不造成明显热路径退化。

### 必须补的测试 / benchmark / 手测
- smoke：wildcard 匹配。
- smoke：quote phrase 匹配。
- smoke：OR / NOT 组合。
- smoke：与 ext/path/recent/frequent 组合。
- bench：典型 wildcard / OR / NOT 查询耗时。
- 手测：GUI 与 CLI 同 query 结果一致。

---

## J4：搜索历史、Saved Filters 与快速过滤器

### 阶段目标
提升高频使用体验，让用户能复用最近查询和常用过滤器，而不是每次重新输入复杂表达式。

### 明确做什么
- 保存最近查询历史。
- 支持清空历史。
- 支持 Saved Filters / 收藏查询。
- UI 提供入口：
  - 最近查询
  - 常用过滤器
  - 保存当前查询
  - 删除保存的查询
- 支持快速插入常用过滤器，如 `ext:` / `kind:` / `path:` / `recent:` / `frequent:`。
- 文档说明所有历史只保存在本地，不上传、不同步。

### 明确不做什么
- 不云同步。
- 不遥测。
- 不读取系统搜索历史。
- 不把搜索历史和 file usage 混成同一张表。

### 涉及关键文件
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. 普通查询执行后写入最近查询历史。
2. 重复查询去重并更新时间。
3. 可以清空历史，清空后 UI 立即反映。
4. 可以保存当前查询为 Saved Filter。
5. 可以删除 Saved Filter。
6. 入口不会干扰普通 typing 搜索性能。
7. 文档明确隐私边界。

### 必须补的测试 / benchmark / 手测
- smoke：query history insert / dedupe / clear。
- smoke：saved filter add / remove / list。
- 手测：从搜索窗口选取最近查询。
- 手测：保存当前查询并再次使用。
- benchmark：历史记录写入不拖慢搜索输入。

---

## J5：上下文菜单与文件操作增强

### 阶段目标
让结果右键菜单更接近成熟文件搜索器，减少用户跳回 Finder 的次数。

### 明确做什么
- 扩展右键菜单：
  - Open
  - Open With...
  - Reveal in Finder
  - Copy Name
  - Copy Full Path
  - Copy Parent Folder
  - Copy Multiple Paths（如支持多选则做）
  - Rename（如成本可控）
  - Move to Trash
- 所有破坏性操作必须确认。
- 操作失败必须有可见反馈。
- usage 统计只对 Open 计入 `open_count`。
- 如果做多选，必须明确 keyboard selection 和 table selection 的一致性。

### 明确不做什么
- 不做完整文件管理器。
- 不做权限绕过。
- 不做批量重命名器。
- 不把 Reveal / Copy 计入 Run Count。

### 涉及关键文件
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeekCore/ResultAction.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. 右键菜单包含新增动作且目标正确。
2. Copy Name / Full Path / Parent Folder 写入剪贴板内容准确。
3. Open With 使用公开 AppKit API。
4. Rename 成功后索引和 UI 状态可恢复，若不做 Rename 必须在文档说明推迟原因。
5. Move to Trash 有确认和失败反馈。
6. 只有 Open 增加 Run Count。

### 必须补的测试 / benchmark / 手测
- smoke：纯字符串动作，如 parent folder / file name 提取。
- 手测：右键各菜单项。
- 手测：剪贴板内容。
- 手测：打开失败 / 删除失败反馈。
- 手测：Open 后 Run Count 增加，Reveal / Copy 不增加。

---

## J6：首次使用 / 权限引导 / Launch 行为 / 最终收口

### 阶段目标
把 SwiftSeek 从“能工作的开发者工具”进一步收口为长期可用的 Mac 工具体验，并为 `everything-ux-parity` 准备最终验收。

### 明确做什么
- 首次使用引导：
  - 添加 root
  - Full Disk Access 说明
  - compact / fullpath 模式差异
  - Run Count 语义说明
  - usage history 隐私说明
- 权限异常时给明确提示和修复路径。
- 设计或实现 Launch at Login：
  - 如果当前 SwiftPM / 未签名 app bundle 不适合实现，必须写清限制。
  - 不得使用 private API。
- 记忆窗口状态：
  - 设置窗口大小 / 位置
  - 搜索窗口大小 / 位置
  - 设置页当前 tab（如成本合理）
- 文档最终收口：
  - README
  - known_issues
  - manual_test
  - ux parity gap
  - codex_acceptance
  - next_stage

### 明确不做什么
- 不承诺 App Store 沙盒适配。
- 不承诺签名 / 公证已完成，除非真实完成。
- 不读取系统隐私数据。
- 不做云同步或遥测。

### 涉及关键文件
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `Package.swift`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/everything_ux_parity_gap.md`
- `docs/everything_ux_parity_taskbook.md`

### 验收标准
1. 首次使用用户能清楚知道先加 root、为何需要权限、索引模式怎么选。
2. 权限不足时不是沉默失败。
3. Launch at Login 有明确实现或明确推迟说明，不能假实现。
4. 窗口状态记忆不破坏现有列宽 / 排序持久化。
5. 文档与最终代码一致。
6. Codex 可据此判断 `PROJECT COMPLETE`。

### 必须补的测试 / benchmark / 手测
- smoke：新增设置项 round-trip。
- 手测：fresh profile 首次启动引导。
- 手测：无 Full Disk Access 或不可访问 root 的提示。
- 手测：窗口状态跨重启。
- 手测：Launch at Login 行为或限制说明。
- 最终回归：build、smoke、manual test、必要 benchmark、docs 全部对齐。
