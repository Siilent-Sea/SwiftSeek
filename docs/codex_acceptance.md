# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K4`
- 当前阶段验收结论：K3 已 `PASS`，等待 K4 实现
- 当前正式验收 session：`019dc54e-017d-7de3-a24f-35c23f09ce08`
- 日期：2026-04-26

### 当前审计结论
K3 round 1 基于提交 `8eba98c` 验收，结论为 `PASS`。

本轮确认成立的事实：
- `Sources/SwiftSeekCore/Diagnostics.swift` 新增 `Diagnostics.snapshot(database:launchAtLoginIntent:launchAtLoginSystemStatus:)`，并且是 AppKit-free 的单一来源实现。
- `SettingsWindowController.AboutPane.buildDiagnostics()` 已收口到 `Diagnostics.snapshot(...)`，复制诊断信息按钮沿用现有剪贴板路径，因此 GUI 面和 smoke 使用同一份文本生成逻辑。
- 受限沙箱变量下：
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox`
  - 通过。
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest`
  - 结果 `203/203` 通过。
- K3 smoke 已覆盖：
  - build identity 字段
  - DB / rows / settings / Launch at Login 字段
  - 设置翻转后的 diagnostics 文本变化
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox` 继续通过，说明 K2 package 流水线没有被 K3 回归破坏。
- package 自检输出里 `Info.plist` 字段与当前提交一致：
  - `BuildDate = 2026-04-26`
  - `CFBundleIdentifier = com.local.swiftseek`
  - `CFBundleShortVersionString = 1.0-K2`
  - `GitCommit = 8eba98c`

结论：
- K3 的“完整诊断单一来源 + 可复制 diagnostics + smoke 可验证”目标已落地。
- K1 build identity、K2 package 流水线、J1/J6 生命周期路径都没有回退。

## 当前验收要求
K4 完成后，Codex 才能给出下一轮 `PASS` 或 `REJECT`。当前不允许因为 K3 已通过就把后续产品化阶段视为自动完成。

验收时必须检查：
- 本地安装 / 升级 / 回滚流程写清并可执行。
- Launch at Login 的用户意图与系统状态继续诚实呈现。
- unsigned / ad-hoc 环境下的限制写清，不假装正式发行。
- 至少给出多实例 / 旧 app / schema 回滚的风险说明。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`

## 轨道切换说明
`everything-productization` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
