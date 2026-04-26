# 下一阶段任务书：M4

轨道：`everything-filemanager-integration`

当前阶段：`M4`

任务性质：交给 Claude 执行的最终收口任务书。M1-M3 已通过 Codex 验收；M4 不再扩功能，目标是把文档、release gate、诊断口径和最终验收状态收拢到可以判定 `PROJECT COMPLETE`。

## 背景

M1 已完成 Reveal Target 设置模型与设置页。

M2 已把 reveal 动作接入 Finder / 自定义 App 路由，并保留 Finder fallback。M2 round 2 已确认 fallback 到 Finder 时使用原始 target URL，不会在 `.parentFolder` 模式误选父目录。

M3 已完成动态文案、fallback toast、Diagnostics 块、手测矩阵和 release checklist 项：
- `RevealResolver.displayName(for:)`
- `RevealResolver.actionTitle(for:)`
- `RevealResolver.fallbackReason(_:for:)`
- 搜索窗口 button / 右键菜单 / hint 三个表面同源刷新
- `SearchWindowController.show()` 呼出前刷新 reveal 文案
- `ResultActionRunner` custom app success / fallback 文案接入 displayName / fallbackReason
- `Diagnostics.snapshot` 增加 `Reveal target（M3）：` 块
- SmokeTest 当前基线：256/256

## M4 目标

让 `everything-filemanager-integration` 达到最终可验收完成状态：文档不再保留 Finder-only 旧口径，release gate 能覆盖 M1-M4 的真实能力，自动化验证全绿，Codex 可据此判断是否输出本轨道 `PROJECT COMPLETE`。

## 必须完成

1. README 收口
   - 更新 `README.md` 中与 reveal / Finder / QSpace / 自定义文件管理器相关的描述。
   - 明确默认仍是 Finder。
   - 明确用户可在设置里选择 QSpace / 自定义 `.app`。
   - 明确外部 app 模式使用公开 macOS API 打开 item 或 parentFolder。
   - 明确不保证第三方 app 一定“选中文件”。
   - 保留本地、原生、非云端、非 Finder 插件的边界。

2. known_issues 收口
   - 更新 `docs/known_issues.md`，清理 M1/M2/M3 阶段性说法。
   - 不要再写“动态按钮 / diagnostics 留给 M3”这类已过期句子。
   - 保留真实限制：
     - Finder 是唯一保证选中文件的模式。
     - 自定义 app 是否选中文件由该 app 自身决定。
     - 不使用 QSpace 私有 API。
     - 不硬编码 QSpace bundle id。
     - 不假设 QSpace URL scheme。
     - 不做 AppleScript。

3. architecture 收口
   - 更新 `docs/architecture.md`，增加 filemanager integration 的当前实现结构。
   - 至少说明这些职责：
     - `SettingsTypes.swift`：RevealTarget 持久化类型与 DB get/set。
     - `RevealResolver.swift`：AppKit-free 决策、验证、target URL、displayName、fallbackReason。
     - `ResultActionRunner.swift`：AppKit side-effect、Finder / custom app / fallback 执行。
     - `SearchViewController.swift`：button / menu / hint 文案刷新与 fallback toast。
     - `Diagnostics.swift`：Reveal target 诊断块。
   - 写清楚 Core 不依赖 AppKit 的边界。

4. manual test / release checklist 收口
   - 保留并校对 `docs/manual_test.md` §33ac。
   - 保留并校对 `docs/release_checklist.md` §5f。
   - 把 release checklist header / 当前 release gate 文案更新为 `K6 + L1-L4 + M1-M4`。
   - 确认 smoke 基线是 256。
   - release checklist 必须能指导以下手测：
     - Finder 默认 reveal。
     - QSpace / custom app reveal。
     - app path 失效 fallback。
     - `.item` vs `.parentFolder`。
     - reveal 不增加 Run Count。
     - no Dock / menu bar agent 不回退。
     - single-instance 不回退。

5. 状态文件收口
   - 更新 `docs/stage_status.md` 的 M4 实现记录。
   - 更新 `docs/codex_acceptance.md`，为 M4 Codex 验收预留当前有效视图。
   - 更新 `docs/agent-state/README.md` 与 `docs/agent-state/codex-acceptance-session.json`，确保当前阶段是 `M4`，当前 track 仍是 `everything-filemanager-integration`，session id 仍是 `019dc959-3bf6-7671-ace6-cf3a3598e592`。
   - 不要复用已归档 `everything-menubar-agent` session `019dc5fc-318e-7d31-bb00-2810eaf6642c`。

6. 自动化验证
   - 运行：
     ```bash
     HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox
     HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest
     HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox
     plutil -p dist/SwiftSeek.app/Contents/Info.plist
     plutil -lint dist/SwiftSeek.app/Contents/Info.plist
     codesign -dv dist/SwiftSeek.app
     ```
   - 期望：
     - build 通过。
     - SmokeTest 256/256。
     - package-app 通过。
     - `GitCommit` 等于当前 HEAD 短 hash。
     - `LSUIElement=false`。
     - `CFBundleIdentifier=com.local.swiftseek`。
     - codesign 为 adhoc。

## 禁止事项

- 不新增 QSpace 私有 API。
- 不硬编码 QSpace bundle id。
- 不假设 QSpace URL scheme。
- 不做 AppleScript。
- 不改变 macOS 系统默认文件管理器。
- 不做正式 Developer ID 签名、notarization、DMG、auto updater。
- 不改变 `.open` 的 Run Count 语义。
- 不把 reveal/show 计入 Run Count。
- 不扩展全文搜索、OCR、AI 搜索、跨平台、Electron/Tauri/Web UI、Finder 插件。
- 不把本阶段扩成新功能开发；M4 是最终文档 / release gate / 状态收口。

## 验收标准

- README / known_issues / architecture / manual_test / release_checklist 与 M1-M3 实际代码一致。
- 文档不再自相矛盾，不再把当前 reveal 能力写成 Finder-only。
- 所有真实边界清楚：Finder 才保证选中文件；外部 app 使用公开 API 打开目标 URL；是否选中文件由外部 app 决定。
- 自动化验证全绿。
- L1-L4、K1-K6、M1-M3 无回归。
- Codex 可以输出 `PROJECT COMPLETE`，结束 `everything-filemanager-integration` 轨道。
