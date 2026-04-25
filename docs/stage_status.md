# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K2`
- 当前轨道目标：把 SwiftSeek 从“功能轨道已完成的开发者可运行项目”推进到“可重复打包、可安装、可诊断、可回归验证的 macOS 工具”。重点不再是新增搜索功能，而是发布链路、`.app` bundle、图标/Info.plist/codesign、版本标识、stale build 防护、窗口生命周期 release gate、安装/升级/回滚、权限与最终 release QA。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage` / `everything-ux-parity`

## 当前阶段：K2

### 阶段目标
建立可重复生成 `.app` bundle 的本地打包流水线。

K2 必须把当前手工或半手工的 `.app`、Info.plist、icon、codesign 组装路径收口成可重复脚本，让 SwiftSeek 真正具备“fresh clone 后本地可交付 app bundle”的能力。

### 当前代码审计依据
- K1 已通过：BuildInfo / About / diagnostics / startup log 现在能暴露 version、commit、build date、bundle path、binary path。
- K1 的 settings release gate 已写入 `docs/manual_test.md` §33s，J1/J6 生命周期修复作为长期回归门禁保留。
- `scripts/build.sh` 已修正文案，不再宣称 schema v3，并明确自己只构建 `.build/release` 二进制。
- 当前已有 `scripts/package-app.sh`，而且 round 2 已修正 PNG 像素尺寸与文件名声明不一致的问题；受限沙箱下 smoke 也能 201/201 通过。
- 但 K2 round 2 复验时主路径仍在 `iconutil -c icns` 失败，说明 iconset 还有除尺寸之外的合法性问题，仍未形成可放行的稳定 `.app` 流水线。
- 验收时产物只到 `dist/SwiftSeek.app/Contents/MacOS/SwiftSeek`；`Resources/AppIcon.icns` 未生成，完整 bundle 尚未成立。

### 当前阶段禁止事项
- 不做 DMG。
- 不做 Apple Developer ID 签名或 notarization。
- 不做 auto updater。
- 不做安装 / 升级 / 回滚，留给 K4。
- 不做权限引导和 Full Disk Access 收口，留给 K5。
- 不新增搜索 / ranking / 索引业务功能。
- 不把本轮文档立项写成已经完成产品化。

### 当前阶段完成判定标准
K2 只有同时满足以下条件才可验收通过：
1. fresh clone 后一条命令能生成 `.app`。
2. `.app/Contents/MacOS/SwiftSeek` 存在且可执行。
3. `Info.plist` 字段完整，并自动写入 version / bundle id / build metadata。
4. `AppIcon.icns` 自动进入 bundle，不依赖手工主路径。
5. `codesign -dv --verbose=2` 显示 ad-hoc 签名。
6. `open dist/SwiftSeek.app` 或等价命令可启动。
7. `scripts/build.sh`、package 脚本、README、manual test 的边界一致。
8. 不提前实现 K3-K6。
9. `swift build`、package 验证命令与必要 smoke 通过，或明确记录环境阻塞原因。

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

## 当前阻塞

### `K2 round 2`
- 结论：`REJECT`，日期 2026-04-25，验收提交 `5bbb071`。
- blocker：
  - `scripts/package-app.sh --sandbox` 在 `iconutil -c icns` 处仍报 `Invalid Iconset`
  - round 2 新增的 PNG 尺寸自检已通过，但 iconset 仍被拒绝，说明问题不只在像素尺寸
  - `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns` 未生成
  - 因为 icon 生成失败，codesign / 完整 bundle 自检链路没有实际通过

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
