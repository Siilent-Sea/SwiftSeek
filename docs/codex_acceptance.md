# Codex 验收记录

本文件只保留当前有效视图。历史轨道的 `PROJECT COMPLETE` 只作为归档背景，不会传递到新的活跃轨道。

## 当前有效状态
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K6`
- 当前阶段验收结论：K5 已 `PASS`，等待 K6 实现
- 当前正式验收 session：`019dc54e-017d-7de3-a24f-35c23f09ce08`
- 日期：2026-04-26

### 当前审计结论
K5 round 1 基于提交 `a175880` 验收，结论为 `PASS`。

本轮确认成立的事实：
- `Sources/SwiftSeekCore/SettingsTypes.swift` 已把 root health 扩展为 `ready` / `indexing` / `paused` / `offline` / `volumeOffline` / `unavailable`，并新增 `RootHealthReport` 与 `Database.computeRootHealthReport(for:currentlyIndexingPath:)`。
- `/Volumes/<X>/...` 缺失时会按 mount point 判断为 `.volumeOffline`；普通缺路径仍为 `.offline`；路径存在但不可读为 `.unavailable`；disabled root 的 `.paused` 优先于磁盘状态。
- `SettingsWindowController.IndexingPane` 已新增 "重新检查权限" 与 "打开完全磁盘访问设置" 按钮；recheck 只刷新 UI，不写 DB；FDA 按钮先打开 Full Disk Access deep link，失败后回退隐私面板和 NSAlert。
- roots 表行现在使用 `RootHealthReport`，可见 label 显示状态，tooltip 显示同源 detail。
- `Diagnostics.snapshot` 已新增 `roots 健康（K5）：` 段，最多列 20 个 root，每行 `<徽标>  <路径>  — <detail>`。
- `SwiftSeekSmokeTest` 已升到 `209/209`，新增 6 个 K5 smoke，覆盖 ready / offline / volumeOffline / unavailable / paused 覆盖磁盘状态 / diagnostics roots block。
- `docs/install.md`、`docs/known_issues.md`、`docs/manual_test.md`、`README.md` 已同步 K5 权限、FDA、recheck、四状态矩阵和诊断同源说明。
- 受限沙箱变量下：
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox`
  - 通过。
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest`
  - 结果 `209/209` 通过。
  - `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox`
  - 通过，并注入当前 `GitCommit = a175880`。

结论：
- K5 的“权限 / Full Disk Access / root coverage 可诊断、可复检、边界诚实”目标已落地。
- K1 build identity、K2 package 流水线、K3 diagnostics、K4 install docs、J1/J6 生命周期路径都没有回退。

## 当前验收要求
K6 完成后，Codex 才能给出 `PROJECT COMPLETE` 或 `REJECT`。当前不允许因为 K5 已通过就把产品化轨道视为自动完成。

验收时必须检查：
- fresh clone 或 clean workspace 下 release checklist 能按文档跑通。
- `.app` 可重复打包、启动、验证 Info.plist / icon / codesign / build identity。
- 设置窗口 release gate、搜索窗口、add root、search、open file、Run Count、DB stats、diagnostics copy 都通过最终 QA。
- README / known issues / manual test / architecture / package scripts 与当前代码一致。
- 未签名 / 未公证 / ad-hoc 边界继续诚实呈现，不假装正式发行版。

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24
- `everything-usage`：H1-H5 / PROJECT COMPLETE 2026-04-24
- `everything-ux-parity`：J1-J6 / PROJECT COMPLETE 2026-04-25，session `019dc07b-55f0-7712-9d7f-74441d7c81df`

## 轨道切换说明
`everything-productization` 必须使用新的 Codex 验收 session；不得复用任何已归档轨道 session id。
