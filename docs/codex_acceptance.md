# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态

- 当前轨道：`everything-dockless-hardening`
- 当前阶段：`N1`
- 最新验收结论：尚未验收
- 当前正式验收 session：`PENDING_NEW_CODEX_ACCEPTANCE_SESSION`
- 日期：2026-04-27

## 新轨道立项原因

用户真实反馈：`everything-menubar-agent` 已归档后，实际使用中 SwiftSeek 仍常驻 Dock。历史文档中的“默认 no Dock”不能再作为当前事实。

本轮代码优先审计确认：

- `scripts/package-app.sh` 仍写 `<key>LSUIElement</key><false/>`。
- `Sources/SwiftSeek/App/AppDelegate.swift` 启动时先 `NSApp.setActivationPolicy(.accessory)`，DB 打开后读取 `dock_icon_visible`。
- 如果 `dock_icon_visible=1`，AppDelegate 会切到 `.regular` 并记录 `Dock icon visible (user preference)`。
- `Sources/SwiftSeekCore/SettingsTypes.swift` 已有 `dock_icon_visible` 设置，默认 false；true 表示下次启动显示 Dock。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` 已有 Dock 显示复选框和重启说明，但没有完整 Dock 状态诊断 / 一键恢复菜单栏模式。
- `Sources/SwiftSeekCore/Diagnostics.swift` 当前没有 Dock mode 专用块，不能直接展示 persisted setting、effective activation policy、Info.plist `LSUIElement`。

## N1 验收焦点

N1 不要求最终隐藏 Dock，也不要求修改 package 默认策略。Codex 验收时只看：

- Diagnostics 是否新增 Dock 状态块。
- 启动日志是否解释 persisted setting、chosen activation policy、Info.plist `LSUIElement`。
- `dock_icon_visible=1` 是否明确标为用户设置导致 Dock 出现。
- smoke 是否覆盖 Dock setting default / round-trip / diagnostics 关键字段。
- 文档是否仍诚实说明 N1 是诊断阶段，不是假装最终修复。

## 下一阶段

见 [docs/next_stage.md](next_stage.md)。当前下一阶段为 N1。

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

## 会话规则

- `everything-dockless-hardening` 必须使用新的正式 Codex 验收 session。
- 不得复用 `everything-filemanager-integration` 的完成 session `019dc959-3bf6-7671-ace6-cf3a3598e592`。
- 新 session 创建后，必须同步更新 `docs/agent-state/codex-acceptance-session.txt` 与 `.json`。
