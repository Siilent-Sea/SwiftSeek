# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K5`
- 当前轨道目标：把 SwiftSeek 从“功能轨道已完成的开发者可运行项目”推进到“可重复打包、可安装、可诊断、可回归验证、权限边界诚实的 macOS 工具”。重点不再是新增搜索功能，而是发布链路、`.app` bundle、图标/Info.plist/codesign、版本标识、stale build 防护、窗口生命周期 release gate、安装/升级/回滚、权限与最终 release QA。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage` / `everything-ux-parity`

## 当前阶段：K5

### 阶段目标
补齐权限引导、Full Disk Access 与 root coverage 收口，让用户能明确知道“哪些目录真的可索引、哪些因为系统权限或卷状态不可用、以及如何恢复”。

K5 必须把 K1 的 build identity、K3 的 diagnostics 和现有 root health 继续收口成可解释、可复检、边界诚实的产品面，而不是继续依赖隐含约定。

### 当前代码审计依据
- K1 已通过：BuildInfo / About / diagnostics / startup log 现在能暴露 version、commit、build date、bundle path、binary path。
- K1 的 settings release gate 已写入 `docs/manual_test.md` §33s，J1/J6 生命周期修复作为长期回归门禁保留。
- K2 已通过：`scripts/package-app.sh --sandbox` 现在能在当前 Codex 沙箱内稳定生成 `dist/SwiftSeek.app`。
- 当前 K2 产物已包含 `Info.plist`、`MacOS/SwiftSeek`、`Resources/AppIcon.icns` 和 ad-hoc `_CodeSignature`。
- K3 已通过：`Diagnostics.snapshot` 已成为 About / diagnostics / copy 的单一来源，SmokeTest 203/203 覆盖 K3 字段与设置翻转。
- K4 已通过：`docs/install.md` 已写清安装、升级、回滚、卸载、Launch at Login 边界，以及 stale bundle / 多实例 / schema forward-only 风险。
- 当前 bundle、build identity、diagnostics、install docs 都已具备，但 root 不可访问、Full Disk Access 缺失、离线卷、路径失效这些权限与覆盖率边界还没有完全收口成用户可理解的状态面。

### 当前阶段禁止事项
- 不做 DMG。
- 不做 Apple Developer ID 签名或 notarization。
- 不做 auto updater。
- 不重做 K4 的安装 / 升级 / 回滚文档，只补与权限恢复直接相关的必要交叉说明。
- 不做 K6 的 release notes / 最终 QA checklist。
- 不新增搜索 / ranking / 索引业务功能。
- 不把本轮权限引导写成“已经自动绕过 macOS 限制”。

### 当前阶段完成判定标准
K5 只有同时满足以下条件才可验收通过：
1. root 不可访问时，用户能看见明确原因，而不是只看到结果缺失。
2. 用户能从 UI 或文档知道如何补齐 Full Disk Access。
3. 补权限后存在明确的 recheck / refresh 路径。
4. 外接盘离线、路径不存在、权限被拒绝不会混成同一种状态。
5. diagnostics / docs / UI 三处口径一致，不夸大能力。
6. 不提前实现 K6。
7. 必要构建、smoke、package 与手测通过，或明确记录环境阻塞原因。

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
