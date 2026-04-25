# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-productization`
- 当前阶段：`K1`
- 当前轨道目标：把 SwiftSeek 从“功能轨道已完成的开发者可运行项目”推进到“可重复打包、可安装、可诊断、可回归验证的 macOS 工具”。重点不再是新增搜索功能，而是发布链路、`.app` bundle、图标/Info.plist/codesign、版本标识、stale build 防护、窗口生命周期 release gate、安装/升级/回滚、权限与最终 release QA。
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage` / `everything-ux-parity`

## 当前阶段：K1

### 阶段目标
建立设置窗口回归门禁和 stale build 防护。

K1 必须把用户真实遇到过的设置窗口 / 设置菜单问题变成长期 release gate，并补上最小 build identity，让用户和开发者能判断当前运行的是不是最新构建。

### 当前代码审计依据
- `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` 已存在；无可见窗口时调用 `showSettings(nil)`。
- `SettingsWindowController` 已实现 `NSWindowDelegate.windowShouldClose(_:)`，关闭按钮只 `orderOut` 并返回 `false`。
- `SettingsWindowController` 的 tab 记忆已改为 KVO `selectedTabViewItemIndex`，避免旧的非法 `tabView.delegate` 做法。
- `SearchWindowController` 已加 `setFrameAutosaveName("SwiftSeekSearchPanel")`；设置窗口也有 `setFrameAutosaveName("SwiftSeekSettingsWindow")`。
- `LaunchAtLogin.swift` 使用公开 `SMAppService.mainApp`，但注释已承认未签名 / ad-hoc bundle 下可能不稳定。
- `scripts/build.sh` 仍只构建 `.build/release` 下的可执行文件，不生成稳定 `.app`；脚本注释明确“不做签名 / notarization / .app bundle”，但 `.gitignore` 又写着“Local app bundle (built by scripts/build.sh + codesign)”。
- `scripts/build.sh` 结尾仍打印“schema 当前为 v3”，当前 `Schema.currentVersion` 已是 7。
- `scripts/make-icon.swift` 只生成 iconset PNG，仍要求手动 `iconutil` 输出 `AppIcon.icns`。
- 本地存在 `SwiftSeek.app/Contents/Info.plist` 和 `AppIcon.icns`，`codesign -dv` 显示 ad-hoc 签名；但 `SwiftSeek.app/` 被 `.gitignore` 忽略，Info.plist / icon / codesign 不属于可重复交付流水线。
- About / Diagnostics 当前显示 DB path、schema、roots、excludes、files、hidden、last rebuild；没有 app version、commit、build date、bundle path、executable path 等 build identity。

### 当前阶段禁止事项
- 不做正式 `.app` 打包流水线，留给 K2。
- 不做 DMG。
- 不做 Apple Developer ID 签名或 notarization。
- 不做 auto updater。
- 不重写 Launch at Login，留给 K4 稳定化。
- 不新增搜索 / ranking / 索引业务功能。
- 不把本轮文档立项写成已经完成产品化。

### 当前阶段完成判定标准
K1 只有同时满足以下条件才可验收通过：
1. `docs/manual_test.md` 或等价 release checklist 明确覆盖设置窗口 10 次关闭/打开。
2. release gate 覆盖：启动后打开设置、关闭、从菜单栏重开、从主菜单重开、Dock reopen、设置 tab 切换不崩溃。
3. KVO tab 记忆不能回退到非法 `tabView.delegate` 方案。
4. 增加可见 build identity：About / diagnostics 或等价 UI 至少显示 app version、schema、git commit 或 build timestamp、bundle/executable path。
5. 启动日志打印 build identity，便于区分 stale bundle。
6. 如果暂时无法注入 git commit，必须有 build-info 文件或常量，并在文档说明限制。
7. 文档写清如何判断当前 `.app` / binary 是否刷新到最新构建。
8. 不提前实现 K2-K6。
9. `swift build` 和 `swift run SwiftSeekSmokeTest` 通过，或记录环境阻塞原因。

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
