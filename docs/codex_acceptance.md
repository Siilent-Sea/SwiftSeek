# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-filemanager-integration`
- 当前阶段：`M4`
- 最新验收结论：`PASS`
- 最新通过阶段：`M3`
- 当前正式验收 session：`019dc959-3bf6-7671-ace6-cf3a3598e592`
- 日期：2026-04-26

## M3 round 2 验收结论

`HEAD=666c184df501d3f9c701041bd4ff1300f9aa3c49` 通过 M3 验收。

Round 1 阻塞项已修复：

- `Sources/SwiftSeek/UI/SearchViewController.swift` 新增 `hintTextForReveal(target:)`，loadView 初始 hint 与 `refreshRevealLabels()` 刷新 hint 都使用当前 `RevealTarget`。
- hint 的 `⌘⏎` 槽位与 button / menu 同源：短 displayName 显示“在 <displayName> 中显示”，长 displayName 降级为中性“显示位置”，避免底部单行 hint 溢出。
- `docs/known_issues.md` §1 / §6 已改成 `showToast("⚠️ \(reason)")`，并说明 `reason` 由 `RevealResolver.fallbackReason(...)` 组成。

M3 通过依据：

- `RevealResolver.displayName(for:)` / `actionTitle(for:)` / `fallbackReason(_:for:)` 三个纯 helper 存在且 smoke 覆盖。
- 搜索窗口 reveal button、右键菜单项、hint 三个表面都能从当前 persisted `RevealTarget` 刷新。
- `SearchWindowController.show()` 在 focus 前刷新 reveal 文案，Settings 里改动后下次呼出能生效。
- `ResultActionRunner` custom app success 用 displayName，fallback 用 `fallbackReason`，并保留 M2 round 2 的 Finder fallback 原始 target URL 不变量。
- `Diagnostics.snapshot` 包含 `Reveal target（M3）：` 块，暴露 type / 显示名称 / 按钮文案 / 打开模式 / 自定义 App 路径。
- `docs/manual_test.md` §33ac 与 `docs/release_checklist.md` §5f 已覆盖 M3 GUI 手测 / release gate。
- `ResultAction` case 仍名为 `.revealInFinder`；`recordOpen` 仍只在 `.open` 成功路径调用；未发现 QSpace 私有 API、QSpace bundle id、QSpace URL scheme 或 AppleScript。

## 本轮验证

已运行：

```bash
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox
plutil -p dist/SwiftSeek.app/Contents/Info.plist
plutil -lint dist/SwiftSeek.app/Contents/Info.plist
codesign -dv dist/SwiftSeek.app
```

观察结果：

- `swift build --disable-sandbox`：通过。
- `SwiftSeekSmokeTest`：256/256 通过，M1 / M2 / L1-L4 / K1-K6 覆盖项仍通过。
- `package-app.sh --sandbox`：通过。
- `Info.plist`：`GitCommit=666c184`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`。
- `codesign -dv`：`Signature=adhoc`、`Identifier=com.local.swiftseek`。
- `git status --short`：仅有既存未跟踪 `.claude/`；本轮验收只改验收 / 状态 / 下一阶段任务书文档。

## 下一阶段

M4 任务书已写入 `docs/next_stage.md`。

M4 验收重点：

- README / known_issues / architecture / manual_test / release_checklist 全部从 Finder-only 旧表述收口到 M1-M3 真实能力。
- release checklist header 更新到 `K6 + L1-L4 + M1-M4`。
- smoke / package / plist / codesign 继续通过。
- L1-L4、K1-K6、M1-M3 不回退。
- 继续禁止 QSpace 私有 API、bundle id、URL scheme、AppleScript。

## 历史归档轨道

- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`
- `everything-productization`：K1-K6 / PROJECT COMPLETE 2026-04-26，session `019dc54e-017d-7de3-a24f-35c23f09ce08`
- `everything-menubar-agent`：L1-L4 / PROJECT COMPLETE 2026-04-26，session `019dc5fc-318e-7d31-bb00-2810eaf6642c`

## 轨道切换说明

`everything-filemanager-integration` 使用当前新的 Codex 验收 session `019dc959-3bf6-7671-ace6-cf3a3598e592`；不得复用 `everything-menubar-agent` session `019dc5fc-318e-7d31-bb00-2810eaf6642c`，也不得复用更早归档轨道 session。
