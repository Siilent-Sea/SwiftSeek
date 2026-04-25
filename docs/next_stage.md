# 下一阶段任务书：L3

当前活跃轨道：`everything-menubar-agent`

当前阶段：`L3`

前置状态：L1、L2 已通过 Codex 验收。SwiftSeek 默认 no Dock / 菜单栏常驻，用户可在设置里选择下次启动显示 Dock 图标；`LSUIElement=false` 仍保持不变，activation policy 由 runtime 控制。

任务性质：交给 Claude 执行的实现任务书。L3 只做菜单栏菜单增强与状态可见性，不做单实例、多 bundle 防护、正式签名/公证/DMG，也不扩展搜索/索引业务能力。

## L3 目标

让菜单栏从"能打开搜索/设置的入口"升级为真正的主入口：用户不用先打开设置窗口，也能快速判断当前构建、索引状态、索引模式、root 健康和 DB 简况，并能直达已存在的最近/常用能力。

## 必须做

1. 增强菜单栏菜单结构
   - 保留并验证已有菜单项：
     - 搜索…
     - 设置…
     - 索引状态
     - 退出 SwiftSeek
   - 新增只读状态项或子菜单，至少覆盖：
     - 当前构建版本 / GitCommit
     - 当前索引模式（Compact / Full path）
     - root 总数与不健康 root 简况
     - DB 大小简况
   - 如接入最近打开 / 常用项，只能使用现有 H3/H4 usage 数据，不允许发明新的历史来源。

2. status item tooltip 增强
   - tooltip 至少包含：
     - SwiftSeek 版本 / commit
     - 当前索引状态
     - 当前索引模式
     - root 简况
   - tooltip 文本要短，适合悬停快速确认，不做长诊断报告。

3. 菜单状态刷新
   - 菜单打开前或状态变化时刷新索引状态、DB 大小、root 健康和 build identity。
   - 索引中 / 空闲状态要继续正确更新，不回归 L1/L2 的 status item 图标切换。
   - 读取 DB 或 root health 失败时，菜单显示可理解的降级文案，不要 crash。

4. 最近打开 / 常用入口（如果实现）
   - 只能基于 SwiftSeek 自己的 `file_usage` 表。
   - 无数据时显示 disabled empty state。
   - 点击条目应复用现有打开文件路径逻辑，不绕过 usage/privacy 设置。
   - 不允许读取 macOS 全局最近项目、Finder 历史或 private API。

5. 文档同步
   - 更新 `docs/install.md`：说明菜单栏能看到哪些状态，以及这些状态各自代表什么。
   - 更新 `docs/manual_test.md`：新增 L3 手测矩阵，覆盖 tooltip、菜单状态、索引中状态、DB/root 简况和最近/常用入口。
   - 更新 `docs/release_checklist.md`：增加 L3 菜单栏状态 release gate。
   - 更新 `docs/known_issues.md`：把"菜单栏状态信息仍偏基础"改为 L3 已落地，并保留不做 dashboard / 不读系统全局历史的边界。
   - 更新 `docs/stage_status.md`：写入 L3 实现状态，提交 Codex 验收前标为"待 Codex 验收"。

## 明确不做

- 不做单实例 / 多 bundle 防护，那是 L4。
- 不做正式 Developer ID 签名、公证、DMG、auto updater。
- 不做完整菜单栏 dashboard 或复杂弹窗控制台。
- 不做全文搜索、AI 语义搜索、OCR、云盘一致性或 Finder 插件。
- 不新增 DB schema，除非确有不可避免的小型状态缓存；优先复用现有 `Diagnostics`、`DatabaseStats`、`RootHealth`、`BuildInfo`、`file_usage`。
- 不读取 macOS 全局最近打开、系统全局启动次数或 private API。

## 关键文件

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/RootHealth.swift`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `docs/install.md`
- `docs/manual_test.md`
- `docs/release_checklist.md`
- `docs/known_issues.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`

## 验收标准

- 菜单栏仍能稳定打开搜索、设置、退出；L1/L2 行为不回归。
- tooltip 能显示构建、索引状态、索引模式和 root 简况。
- 菜单中能看到 build identity、index mode、root/DB 简况。
- 索引中状态变化能反映到菜单或 tooltip，不只停留在旧静态文本。
- 读取状态失败时有降级文案，不 crash、不隐藏主入口。
- 如果实现最近打开 / 常用，数据来源必须是 SwiftSeek 内部 usage history，且 privacy toggle / clear history 后表现正确。
- 文档和手测矩阵同步；没有提前实现 L4 单实例。

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

plutil -p dist/SwiftSeek.app/Contents/Info.plist | grep -E 'LSUIElement|CFBundleIdentifier|GitCommit|BuildDate'
```

## 必须手测

1. 全新 DB 启动 `dist/SwiftSeek.app`，确认菜单栏图标存在、Dock 默认隐藏。
2. 悬停菜单栏图标，确认 tooltip 包含版本/commit、索引状态、索引模式、root 简况。
3. 打开菜单，确认搜索、设置、退出仍在固定位置且可用。
4. 打开菜单，确认 build identity、index mode、DB 大小、root 简况可读。
5. 添加一个 root 并触发索引，确认索引中 / 空闲状态能更新。
6. 如果实现最近打开 / 常用：通过 SwiftSeek 打开若干文件后确认菜单出现条目；关闭 usage history 或清空 usage 后确认菜单降级为空状态。
7. 在 Dock visible 设置开启后重启，确认菜单栏增强仍可用，Dock 模式不影响菜单状态。
8. 人为制造 DB/root 状态读取失败或无 root 场景，确认菜单显示降级文案而不是 crash。
