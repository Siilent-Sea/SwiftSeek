# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前轨道：`everything-filemanager-integration`
- 当前阶段：`M4`
- 最新验收结论：`PROJECT COMPLETE`
- 当前正式验收 session：`019dc959-3bf6-7671-ace6-cf3a3598e592`
- 日期：2026-04-26

## M4 最终验收结论

`HEAD=101d0e902d9d536f1d7ab1a5831bd6f034247fcb` 通过 M4 最终验收。`everything-filemanager-integration` 轨道 M1-M4 全部通过，允许归档为 `PROJECT COMPLETE`。

M4 通过依据：

- M4 是 doc-only consolidation：`HEAD~1..HEAD` 只改 `README.md`、`docs/architecture.md`、`docs/known_issues.md`、`docs/release_checklist.md`、`docs/stage_status.md`，没有 `Sources/` 改动。
- `README.md` 已说明文件管理器集成（M1-M4）：设置 → 显示位置、自定义 `.app`、父目录 / 文件本身、动态 button / menu / hint、fallback toast、Run Count invariant、无私有 API / bundle id / URL scheme 假设。
- `docs/architecture.md` 已新增 `everything-filemanager-integration 收口（M1-M4）` 段，列 M1 / M2 / M3 / M4 交付与明确不做事项。
- `docs/known_issues.md` 已把 productization、menubar-agent、filemanager-integration M1-M4 放入已完成形态收口，并保留真实边界：外部 app 是否选中文件由该 app 决定；不调私有 API；不假设 QSpace bundle id / URL scheme。
- `docs/release_checklist.md` header 已升到 `K6 + L1-L4 + M1-M4 单页`，§5f 继续作为 reveal target 动态文案 / fallback / 诊断发布门禁。
- `docs/stage_status.md` 已记录 M4 实现落地并翻到 `PROJECT COMPLETE`。
- `ResultAction` case 仍名为 `.revealInFinder`；`recordOpen` 仍只在 `.open` 成功路径调用；M2 `finderFallbackURL(target:)` 原始目标 fallback 不变量仍有 smoke 覆盖。
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
- `SwiftSeekSmokeTest`：256/256 通过，L1-L4 / K1-K6 / M1-M3 覆盖项仍通过。
- `package-app.sh --sandbox`：通过。
- `Info.plist`：`GitCommit=101d0e9`、`LSUIElement=false`、`CFBundleIdentifier=com.local.swiftseek`。
- `codesign -dv`：`Signature=adhoc`、`Identifier=com.local.swiftseek`。
- `git status --short`：仅有既存未跟踪 `.claude/`；本轮验收只改最终验收 / 状态文档。

## 下一阶段

None. `everything-filemanager-integration` 已完成。

## 历史归档轨道

- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`
- `everything-productization`：K1-K6 / PROJECT COMPLETE 2026-04-26，session `019dc54e-017d-7de3-a24f-35c23f09ce08`
- `everything-menubar-agent`：L1-L4 / PROJECT COMPLETE 2026-04-26，session `019dc5fc-318e-7d31-bb00-2810eaf6642c`
- `everything-filemanager-integration`：M1-M4 / PROJECT COMPLETE 2026-04-26，session `019dc959-3bf6-7671-ace6-cf3a3598e592`
