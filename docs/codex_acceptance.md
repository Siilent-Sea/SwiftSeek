# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前活跃轨道：`everything-filemanager-integration`
- 当前阶段：`M1`
- 当前阶段验收结论：尚未验收
- 当前正式验收 session：待创建
- 日期：2026-04-26

## 当前审计结论

本轮是新轨道立项与任务书落盘，不是业务代码实现，也不是 M1 验收。基于当前代码确认：

- `Sources/SwiftSeekCore/ResultAction.swift` 仍定义 `case revealInFinder`。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift` 对 `.revealInFinder` 直接调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`。
- `Sources/SwiftSeek/UI/SearchViewController.swift` 的 action button 和 row context menu 都写死“在 Finder 中显示”。
- `Sources/SwiftSeekCore/SettingsTypes.swift` 没有 `reveal_target_type`、`reveal_custom_app_path`、`reveal_external_open_mode`。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 目前只提供隐藏文件、结果上限、热键、索引模式、Launch at Login、Dock 图标等常规设置，没有 Reveal Target 配置。
- 当前 release checklist / manual test 仍以 Finder reveal 为唯一目标，没有 QSpace/custom app/fallback/item-vs-parentFolder 验证。

结论：
- `everything-menubar-agent` 已归档，不再是当前停止条件。
- 当前新轨道 `everything-filemanager-integration` 已建立，M1 等待 Claude 执行。
- Codex 下一次验收应只判断 M1 是否完成 Reveal Target 数据模型与设置 UI，不应要求 M2 的实际外部 app 打开。

## 当前验收要求

M1 验收时至少检查：

- fresh DB 默认 reveal target 为 Finder。
- custom app path 能通过 settings round-trip。
- external open mode 能 round-trip。
- malformed setting fallback 到 Finder。
- 设置页能选择 Finder / 自定义 App，并显示当前 app 名称和路径。
- 文档明确 QSpace 通过用户选择 `.app` 支持，不硬编码未知 bundle id / URL scheme。
- `ResultActionRunner` 行为仍未替换；如果 M1 提前接入外部 app，需要检查是否越界或是否完整。

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

`everything-filemanager-integration` 必须使用新的 Codex 验收 session；不得复用 `everything-menubar-agent` session `019dc5fc-318e-7d31-bb00-2810eaf6642c`，也不得复用更早归档轨道 session。
