# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K3`
- 当前阶段验收结论：K2 已 `PASS`，等待 K3 实现
- 当前正式验收 session：`019dc54e-017d-7de3-a24f-35c23f09ce08`
- 日期：2026-04-26

### 当前审计结论
K2 round 3 基于提交 `cc41750` 复验，结论为 `PASS`。

本轮确认成立的事实：
- `scripts/make-icon.swift` 已不再依赖 `iconutil`，而是直接按 `.icns` 容器格式写出 `AppIcon.icns`。
- `scripts/package-app.sh --sandbox` 在当前 Codex 沙箱内真实通过，完整日志里已出现：
  - `AppIcon.icns OK: 273908 bytes`
  - `plutil -lint: ... OK`
  - `codesign -dv` 显示 `Signature=adhoc`
  - bundle 结构包含 `Contents/Info.plist`、`Contents/MacOS/SwiftSeek`、`Contents/Resources/AppIcon.icns`、`Contents/_CodeSignature/CodeResources`
- 同一套沙箱变量下：
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest`
  - 结果 `201/201` 通过。
- `Info.plist` 自动写入的值与当前提交一致：
  - `BuildDate = 2026-04-26`
  - `CFBundleIdentifier = com.local.swiftseek`
  - `CFBundleShortVersionString = 1.0-K2`
  - `GitCommit = cc41750`

结论：
- K2 的“fresh clone 后一条命令稳定生成 `.app` bundle”目标已在当前沙箱中被实际验证成立。
- K1 的 build identity / settings release gate 没有回退。

## 当前验收要求
K3 完成后，Codex 才能给出下一轮 `PASS` 或 `REJECT`。当前不允许因为 K2 已通过就把后续产品化阶段视为自动完成。

验收时必须检查：
- About / diagnostics 一屏能复制完整诊断信息。
- 诊断信息包含 build identity、schema、DB path、bundle/executable path。
- 启动日志包含 build identity 和 schema。
- DB stats 与真实数据库统计不矛盾。
- 用户反馈模板或诊断说明写入文档。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`

## 轨道切换说明
`everything-productization` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
