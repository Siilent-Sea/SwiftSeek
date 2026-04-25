# 下一阶段任务书：L4

当前活跃轨道：`everything-menubar-agent`

当前阶段：`L4`

前置状态：L1、L2、L3 已通过 Codex 验收。SwiftSeek 默认以菜单栏 agent 运行；用户可选择下次启动显示 Dock；菜单栏 tooltip / menu 已展示 build、索引、模式、roots 和 DB 简况。

任务性质：交给 Claude 执行的实现任务书。L4 是本轨道最终收口阶段，只做单实例 / 多 bundle 防护、stale bundle 可解释性、release QA 收口和最终文档一致性，不做新的搜索能力、正式签名/公证/DMG/auto updater。

## L4 目标

菜单栏 agent 形态下，避免用户因为多开、旧 bundle、登录项和手动启动并存而看到多个 SwiftSeek 菜单栏图标或操作到旧构建。完成后，本轨道应具备申请 `PROJECT COMPLETE` 的条件。

## 必须做

1. 单实例策略
   - 选择并实现一个公开 macOS / 文件系统方案，例如：
     - `NSRunningApplication` 检测同 bundle id；
     - lock file；
     - distributed notification；
     - 或组合方案。
   - 策略必须适合当前 ad-hoc / 本地安装模型，不依赖正式签名、公证或 private API。
   - 检测维度至少覆盖：
     - 同一 bundle path 被重复打开；
     - `dist/SwiftSeek.app` 与 `/Applications/SwiftSeek.app` 并存；
     - Launch at Login 与手动启动接近同时发生。

2. 检测到已有实例时的行为
   - 新实例不应继续长期常驻。
   - 能通知旧实例时，优先让旧实例显示搜索或设置窗口。
   - 不能通知旧实例时，至少写清楚日志并退出新实例。
   - 用户不能因为防护逻辑进入"没有菜单栏图标、没有 Dock、也无窗口"的无入口状态。

3. stale bundle / 多 bundle 可解释性
   - 继续保留 K1 build identity 三连日志。
   - 在冲突日志或诊断信息中写明：
     - 当前 bundle path；
     - 当前 executable path；
     - GitCommit / BuildDate；
     - 被检测到的已有实例信息（能拿到多少写多少）。
   - 如果无法可靠区分旧新实例，文档必须诚实说明限制和手工处理路径。

4. Release QA 收口
   - 更新 `docs/release_checklist.md`，新增 L4 gate：
     - 双击 app 两次；
     - Launch at Login + 手动启动；
     - `dist` bundle 和 `/Applications` bundle 并存；
     - 菜单栏是否出现重复图标；
     - hotkey 是否冲突；
     - 新实例是否退出或唤醒旧实例。
   - 更新 `docs/manual_test.md`，新增 L4 手测矩阵。
   - 更新 `docs/install.md`，说明多实例/旧 bundle 时用户该看什么日志、如何退出旧实例、如何确认当前运行构建。
   - 更新 `docs/known_issues.md`，把多实例 / stale bundle 风险从"未完成"改为 L4 已收口或明确保留边界。
   - 更新 `docs/stage_status.md`，写入 L4 实现状态，提交 Codex 验收前标为"待 Codex 验收"。

5. 最终轨道收口准备
   - 确认 L1-L4 文档没有互相矛盾：
     - `docs/stage_status.md`
     - `docs/codex_acceptance.md`
     - `docs/next_stage.md`
     - `docs/install.md`
     - `docs/release_checklist.md`
     - `docs/known_issues.md`
     - `docs/manual_test.md`
     - `docs/agent-state/*`
   - 如果 L4 通过后已满足轨道目标，Codex 下一轮可给 `PROJECT COMPLETE`。

## 明确不做

- 不做正式 Developer ID 签名、公证、DMG、auto updater。
- 不做跨用户多实例支持。
- 不绕过 macOS 权限，不使用 private API。
- 不新增全文搜索、AI、OCR、云盘一致性、Finder 插件。
- 不重写搜索窗口、设置窗口或菜单栏为 dashboard/popover。
- 不把单实例防护写成"绝不可能多开"的绝对承诺；ad-hoc、本地多 bundle 场景要保留诚实边界。

## 关键文件

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeekCore/AppPaths.swift`
- `Sources/SwiftSeek/App/LaunchAtLogin.swift`
- `Sources/SwiftSeekCore/Diagnostics.swift`
- `docs/install.md`
- `docs/release_checklist.md`
- `docs/known_issues.md`
- `docs/manual_test.md`
- `docs/stage_status.md`
- `docs/codex_acceptance.md`
- `docs/agent-state/README.md`

## 验收标准

- 重复打开同一 `.app` 不会产生两个长期常驻 SwiftSeek 菜单栏实例。
- Launch at Login 与手动启动并发不会留下两个长期常驻实例。
- `dist/SwiftSeek.app` 与 `/Applications/SwiftSeek.app` 并存时，行为可解释：要么阻止/退出新实例，要么给出清晰日志和文档化处理路径。
- 检测到已有实例时，新实例不会静默常驻；能唤醒旧实例则唤醒，不能唤醒则日志清楚并退出。
- 单实例逻辑不破坏 L1 no Dock、L2 Dock 显示开关、L3 菜单栏状态、全局热键、搜索、设置和退出。
- release checklist / install / known issues / manual test 全部同步 L1-L4。
- 没有引入正式签名、公证、DMG、auto updater 或新搜索能力。

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

1. 启动 `dist/SwiftSeek.app`，确认只有一个菜单栏图标。
2. 再次 `open dist/SwiftSeek.app`，确认不会出现第二个长期常驻实例；若设计为唤醒旧实例，确认旧实例窗口前置。
3. 把当前 app 复制到 `/Applications/SwiftSeek.app`，分别启动 `dist` 与 `/Applications` 两份，确认多 bundle 行为符合设计并有日志解释。
4. 开启 Launch at Login 后手动启动，确认不会留下两个长期菜单栏实例。
5. 检查 Console 日志：build identity、bundle path、executable path 和冲突处理信息清楚。
6. L1 回归：默认 no Dock、菜单栏搜索/设置/退出、全局热键可用。
7. L2 回归：Dock 显示开关重启生效，no Dock / Dock visible 两种模式都可用。
8. L3 回归：tooltip 和菜单状态行仍显示 build / 索引 / 模式 / roots / DB 简况。
9. 按 `docs/release_checklist.md` 跑完整 L1-L4 release gate；若全部通过，提交 Codex 最终验收。
