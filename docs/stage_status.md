# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-productization`
- 当前阶段：`PROJECT COMPLETE`
- 当前轨道目标：把 SwiftSeek 从“功能轨道已完成的开发者可运行项目”推进到“可重复打包、可安装、可诊断、可回归验证、权限边界诚实的 macOS 工具”。重点不再是新增搜索功能，而是发布链路、`.app` bundle、图标/Info.plist/codesign、版本标识、stale build 防护、窗口生命周期 release gate、安装/升级/回滚、权限与最终 release QA。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage` / `everything-ux-parity`

## 当前阶段：PROJECT COMPLETE

### 阶段目标
`everything-productization` 已完成。K1-K6 已全部通过验收，当前轨道可以停止。

后续如果开启新轨道，必须重新定义 gap / taskbook / stage_status；历史 `PROJECT COMPLETE` 只代表当前轨道已归档，不自动覆盖后续目标。

### 当前代码审计依据
- K1 已通过：BuildInfo / About / diagnostics / startup log 现在能暴露 version、commit、build date、bundle path、binary path。
- K1 的 settings release gate 已写入 `docs/manual_test.md` §33s，J1/J6 生命周期修复作为长期回归门禁保留。
- K2 已通过：`scripts/package-app.sh --sandbox` 现在能在当前 Codex 沙箱内稳定生成 `dist/SwiftSeek.app`。
- 当前 K2 产物已包含 `Info.plist`、`MacOS/SwiftSeek`、`Resources/AppIcon.icns` 和 ad-hoc `_CodeSignature`。
- K3 已通过：`Diagnostics.snapshot` 已成为 About / diagnostics / copy 的单一来源，SmokeTest 203/203 覆盖 K3 字段与设置翻转。
- K4 已通过：`docs/install.md` 已写清安装、升级、回滚、卸载、Launch at Login 边界，以及 stale bundle / 多实例 / schema forward-only 风险。
- K5 已通过：RootHealthReport / diagnostics roots block / recheck permissions / Full Disk Access jump / K5 docs 已落地；受限沙箱下 build、SmokeTest 209/209、package-app 均通过。
- K6 已通过：
  - `docs/release_checklist.md` 单页 15 步 release gate（fresh build / smoke / package / bundle 元数据 / 启动 build identity / 设置生命周期 10× / 热键 / add root → search → open / 诊断复制 / K5 root health / Launch at Login / icon / 安装升级回滚 dry-run / release notes / 文档一致性）。
  - `docs/release_notes_template.md` 诚实发布说明模板，"已知边界"段强制保留 ad-hoc / 无 Developer ID / 无 notarization / 无 DMG / 无 auto updater / FDA / 外接盘 / schema forward-only。
  - `docs/architecture.md` 末尾新增 K1-K6 productization 收口段，作为代码 ↔ 文档锚点。
  - `docs/known_issues.md` §9 改写为 K6 已落地，列明 release gate 强约束。
  - `docs/manual_test.md` 新增 §33x：指向 release_checklist + release_notes_template，包含干净 workspace 验证命令与文档一致性清单。
  - `README.md` "当前限制" 与"当前进度" 都提到 K6 已落地并链到 release checklist + release notes。
  - 受限沙箱下 `swift build --disable-sandbox` + SmokeTest 209/209 + `./scripts/package-app.sh --sandbox` 仍通过。
  - 最终 package 产物的 `GitCommit = 9e4e686`，与当前 HEAD 一致；`plutil -lint`、`codesign -dv`、AppIcon 检查均通过。

### 当前完成边界
- 不做 DMG，除非用户明确改变 K6 范围。
- 不做 Apple Developer ID 签名或 notarization。
- 不做 auto updater。
- 不新增搜索 / ranking / 索引业务功能。
- 不把 ad-hoc bundle 写成正式签名发行版。

### 当前轨道完成判定
`everything-productization` 满足 `PROJECT COMPLETE` 条件：
1. K1-K6 全部阶段已验收通过。
2. `.app` 打包、build identity、diagnostics、install / upgrade / rollback、permissions / FDA、release QA checklist 已形成闭环。
3. 没有阻塞级问题。
4. 文档已达到非作者本人也能按步骤执行的程度。

## 已通过阶段

### `K1`
- 结论：`PASS`，日期 2026-04-25，验收提交 `d890c81`。
- 已落地：
  - 设置窗口 reopen / Dock reopen / tab KVO 形成 release gate
  - About / diagnostics / startup log 暴露 build identity
  - `scripts/build.sh` 去掉过期 schema v3 文案
  - README / manual test / known issues 写清 stale bundle 自检
- 环境备注：
  - 当前 Codex 沙箱下 `swift build --disable-sandbox` / `swift run --disable-sandbox SwiftSeekSmokeTest` 无法直接复跑，原因是 `ModuleCache` 权限和 CLT/SDK 版本不匹配；已记录为环境阻塞，不视为 K1 实现 blocker。

### `K2`
- 结论：`PASS`，日期 2026-04-26，验收提交 `cc41750`。
- 已落地：
  - `.icns` 由 `scripts/make-icon.swift` 直接组装，不再依赖 `iconutil`
  - `scripts/package-app.sh --sandbox` 在当前 Codex 沙箱内真实通过
  - `dist/SwiftSeek.app` 完整包含 `Info.plist`、`MacOS/SwiftSeek`、`Resources/AppIcon.icns`、`_CodeSignature`
  - `plutil -lint`、`codesign -dv`、bundle 结构检查全部通过
  - 受限沙箱变量下 `SwiftSeekSmokeTest` 仍为 `201/201`

### `K3`
- 结论：`PASS`，日期 2026-04-26，验收提交 `8eba98c`。
- 已落地：
  - `Diagnostics.snapshot` 成为 diagnostics 单一来源
  - About 面板与“复制诊断信息”接到同一份快照文本
  - Diagnostics 扩到 build identity、DB、rows、settings、Launch at Login、last rebuild
  - 受限沙箱变量下 `swift build --disable-sandbox` 通过
  - 受限沙箱变量下 `SwiftSeekSmokeTest` 升到 `203/203`

### `K4`
- 结论：`PASS`，日期 2026-04-26，验收提交 `0ebd033`。
- 已落地：
  - `docs/install.md` 成为单一安装入口，覆盖安装、升级、回滚、卸载、Gatekeeper、Launch at Login 边界、多实例 / stale bundle 风险
  - README 快速上手已指向 `docs/install.md`
  - `docs/manual_test.md` 增加 K4 install / upgrade / rollback / Launch at Login / stale bundle dry-run 与回归验证
  - `docs/known_issues.md` 已同步 K4 状态并重申 schema forward-only 边界
  - 受限沙箱变量下 `swift build --disable-sandbox`、`SwiftSeekSmokeTest` 203/203、`./scripts/package-app.sh --sandbox` 继续通过

### `K5`
- 结论：`PASS`，日期 2026-04-26，验收提交 `a175880`。
- 已落地：
  - `RootHealthReport` 与 `computeRootHealthReport` 提供 ready / indexing / paused / offline / volumeOffline / unavailable 的结构化判定与 detail
  - 设置页 roots 表显示 K5 状态，tooltip 暴露 detail
  - 设置页新增 "重新检查权限" 与 "打开完全磁盘访问设置" 按钮
  - `Diagnostics.snapshot` 新增 `roots 健康（K5）：` 同源诊断块
  - `docs/install.md`、`docs/manual_test.md`、`docs/known_issues.md`、`README.md` 已同步 FDA / root coverage / recheck 文档
  - 受限沙箱变量下 `swift build --disable-sandbox`、`SwiftSeekSmokeTest` 209/209、`./scripts/package-app.sh --sandbox` 继续通过，package 注入 `GitCommit = a175880`

### `K6`
- 结论：`PROJECT COMPLETE`，日期 2026-04-26，验收提交 `9e4e686`。
- 已落地：
  - `docs/release_checklist.md` 单页 15 步 release gate
  - `docs/release_notes_template.md` 诚实 release notes 模板，强制保留已知边界
  - `docs/architecture.md`、`docs/known_issues.md`、`docs/manual_test.md`、`README.md` 已同步 K1-K6 productization 收口状态
  - 受限沙箱变量下 `swift build --disable-sandbox`、`SwiftSeekSmokeTest` 209/209、`./scripts/package-app.sh --sandbox` 通过
  - `dist/SwiftSeek.app/Contents/Info.plist` 的 `GitCommit = 9e4e686`，与当前 HEAD 一致
  - `plutil -lint`、`codesign -dv`、AppIcon 检查通过

## 已归档轨道

### `v1-baseline`
- `PROJECT COMPLETE` 2026-04-23，P0-P6，SwiftSeek v1 基线能力完成。

### `everything-alignment`
- `PROJECT COMPLETE` 2026-04-24，E1-E5，Everything-like 体验第一轮对齐完成。

### `everything-performance`
- `PROJECT COMPLETE` 2026-04-24，F1-F5，搜索热路径 / ranking / 结果视图 / DSL / RootHealth / 索引自动化一轮性能与落地收口。

### `everything-footprint`
- `PROJECT COMPLETE` 2026-04-24，G1-G5，session `019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`。
- 500k 实测亮点：compact 1.07 GB vs fullpath 3.46 GB（3.2x 更小），首次索引 44.87s vs 197.62s（4.4x 更快），reopen/migrate ms 级。

### `everything-usage`
- `PROJECT COMPLETE` 2026-04-24，H1-H5，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`。
- 范围：SwiftSeek 内部 `.open` 计数、Run Count、最近打开、`recent:` / `frequent:`、usage tie-break、隐私控制和 500k usage benchmark。

### `everything-ux-parity`
- `PROJECT COMPLETE` 2026-04-25，J1-J6，session `019dc07b-55f0-7712-9d7f-74441d7c81df`。
- 范围：设置窗 hide-only 生命周期、Dock reopen、Run Count 可见性、wildcard / quote / OR / NOT、搜索历史 / Saved Filters、上下文菜单、首次使用引导、Launch at Login 说明、窗口状态记忆。
- 结论边界：UX parity 证明桌面使用功能闭环成立，但不覆盖稳定发布流水线、正式 `.app` packaging、build identity、stale bundle 防护、安装/升级/回滚和 release QA。

## 当前文档入口
- 产品化差距清单：`docs/everything_productization_gap.md`
- K1-K6 阶段任务书：`docs/everything_productization_taskbook.md`
- 当前阶段给 Claude 的任务摘要：`docs/next_stage.md`
