# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K5`
- 当前阶段验收结论：K4 已 `PASS`，等待 K5 实现
- 当前正式验收 session：`019dc54e-017d-7de3-a24f-35c23f09ce08`
- 日期：2026-04-26

### 当前审计结论
K4 round 1 基于提交 `0ebd033` 验收，结论为 `PASS`。

本轮确认成立的事实：
- K4 按任务书保持文档型实现，没有新增业务代码或越界功能；提交只改了 `README.md`、`docs/install.md`、`docs/known_issues.md`、`docs/manual_test.md`。
- `docs/install.md` 已收口本地安装、升级、回滚、卸载、Launch at Login 边界、多实例 / stale bundle 风险与 schema forward-only 约束。
- `README.md` 快速上手已经把用户入口指向 `docs/install.md`，不会再把 `.app` 使用路径埋在零散文档里。
- `docs/manual_test.md` §33v 已加入 K4 dry-run：安装 / 升级 / 回滚、Launch at Login 两轴验证、多实例 stale bundle 自检，以及对 K1/K2/K3/J1/J6 的回归钩子。
- `docs/known_issues.md` 已把 K4 标成落地，并继续诚实保留 schema forward-only 边界。
- 受限沙箱变量下：
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox`
  - 通过。
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest`
  - 结果 `203/203` 通过。
- `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox` 继续通过，说明 K2 package 流水线没有被 K4 文档收口破坏。
- package 自检输出里 `Info.plist` 字段与当前提交一致：
  - `BuildDate = 2026-04-26`
  - `CFBundleIdentifier = com.local.swiftseek`
  - `CFBundleShortVersionString = 1.0-K2`
  - `GitCommit = 0ebd033`

结论：
- K4 的“安装 / 升级 / 回滚 / Launch at Login 边界说明 / stale bundle 风险收口”目标已落地。
- K1 build identity、K2 package 流水线、K3 diagnostics、J1/J6 生命周期路径都没有回退。

## 当前验收要求
K5 完成后，Codex 才能给出下一轮 `PASS` 或 `REJECT`。当前不允许因为 K4 已通过就把后续产品化阶段视为自动完成。

验收时必须检查：
- 对无权限 root、Full Disk Access 缺失、离线卷宗、权限被拒绝等状态给出明确可见的解释，而不是沉默失败。
- 用户从 UI 或文档能看懂如何补齐 Full Disk Access，以及补齐后如何重新检查。
- 外接盘离线、路径不存在、权限被拒绝不能被混成同一种“索引异常”。
- 不要把 K5 写成“权限问题已经完全自动解决”；只能诚实暴露系统边界与恢复路径。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`

## 轨道切换说明
`everything-productization` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
