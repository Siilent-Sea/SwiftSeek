# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-filemanager-integration`
- 当前阶段：`M3`
- 最新验收结论：`PASS`
- 最新通过阶段：`M2`
- 当前正式验收 session：`019dc959-3bf6-7671-ace6-cf3a3598e592`
- 日期：2026-04-26

## M2 round 2 验收结论

`HEAD=4ef32c0f0c3ef5d0adec6ea7be6545a1d560416f` 通过 M2 验收。

Round 1 阻塞项已修复：

- `Sources/SwiftSeekCore/RevealResolver.swift` 新增 `finderFallbackURL(target:)`，作为 Finder fallback URL 的纯函数单一来源，始终返回原始 `target.path` URL。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift` custom app 分支在 closure 外捕获 `fallbackURL`，`NSWorkspace.open` error 分支现在用该原始 target URL 调 `activateFileViewerSelecting`，不会在 `.parentFolder` 文件场景误选父目录。
- `NSLog` 同时记录 external-app `targetURL` 与 Finder fallback 原始 URL，便于诊断。
- `Sources/SwiftSeekSmokeTest/main.swift` 增加 2 个 M2 round 2 回归用例，覆盖 file fallback 不等于 parentFolder resolved URL，以及 directory fallback 保持目录本身。
- `docs/known_issues.md` §2 已去掉“当前 reveal 路径仍是 Finder”的旧句子，改为指向 §1 的 M2 已落地事实。

M2 通过依据：

- `RevealResolver` 仍保持 AppKit-free，覆盖 strategy、custom app validation、target URL 解析、fallback URL 和 FileManager 探针。
- `ResultActionRunner.perform(_:target:)` 两参数入口仍保留，兼容无 DB 路径；四参数入口能在有 DB 时读取 `RevealTarget` 并路由 Finder / custom app / fallback。
- Finder 模式仍调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`。
- custom app 模式使用公开 `NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration:)`，`config.activates = true`。
- app path 空、失效、非 `.app`、异步打开失败均有 fallback；fallback 会通知 `SearchViewController` 显示 toast。
- `recordOpen` 仍只在 `.open` 成功路径调用，reveal 不增加 Run Count。
- `ResultAction` case 仍名为 `.revealInFinder`，按钮和右键菜单仍为“在 Finder 中显示”，留给 M3 动态文案。
- 未发现 QSpace 私有 API、QSpace bundle id、QSpace URL scheme 或 AppleScript。

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
- `SwiftSeekSmokeTest`：245/245 通过，M1 / L1-L4 / K1-K6 覆盖项仍通过。
- `package-app.sh --sandbox`：通过。
- `Info.plist`：`GitCommit=4ef32c0`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`。
- `codesign -dv`：`Signature=adhoc`、`Identifier=com.local.swiftseek`。

## 下一阶段

M3 任务书已写入 `docs/next_stage.md`。

M3 验收时重点检查：

- 搜索窗口按钮、右键菜单和 hint 随 reveal target 动态变化。
- fallback toast 能表达具体 app 与回退 Finder。
- diagnostics / About 能显示 reveal target type、custom app path、display name、open mode。
- manual test / release checklist 覆盖 Finder、QSpace/custom app、fallback、`.item` / `.parentFolder`、Run Count 不变。
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
