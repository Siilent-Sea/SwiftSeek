# SwiftSeek Everything-productization Gap

本文件基于当前代码与仓库状态，记录 SwiftSeek 与成熟 macOS 工具产品化交付之间的差距。`everything-ux-parity` 已完成桌面体验闭环，但发布、安装、诊断、生命周期回归门禁仍没有形成稳定流水线。

## 1. `scripts/build.sh` 不生成正式 `.app`

- 当前现状：`scripts/build.sh` 只执行 release build、smoke、startup check，然后列出 `.build/release/SwiftSeek*` 可执行文件。脚本注释明确“不做签名 / notarization / .app bundle”。结尾还写“schema 当前为 v3”，但当前 `Schema.currentVersion` 已是 7。
- 为什么是问题：用户需要的是可安装、可替换、可辨认的 Mac App，而不是每次运行 SwiftPM release binary。脚本文案还会误导 schema 和产物状态。
- 用户影响：用户容易运行旧二进制或旧 `.app`，出现“代码已修但体验没变”；也难以判断当前安装物是不是最新构建。
- 推荐优先级：高。
- 建议解决阶段：K1 / K2。

## 2. icon / Info.plist / codesign 仍是手工或半手工流程

- 当前现状：`scripts/make-icon.swift` 只生成 `.iconset` PNG，并要求手动 `iconutil -c icns`。本地存在 `SwiftSeek.app/Contents/Info.plist` 和 `AppIcon.icns`，`codesign -dv` 显示 ad-hoc 签名，但 `SwiftSeek.app/` 被 `.gitignore` 忽略，Info.plist / icon / codesign 不在可重复脚本里。
- 为什么是问题：成熟工具的 `.app` 产物必须可重复生成。手工写 plist、手工 iconutil、手工 codesign 会导致版本、图标、bundle id、签名状态漂移。
- 用户影响：不同机器或不同时间构建出的 App 可能不一致；Launch Services、Dock 图标、Launch at Login 和 Gatekeeper 行为都可能变化。
- 推荐优先级：高。
- 建议解决阶段：K2。

## 3. stale bundle 风险

- 当前现状：仓库可以直接运行 `.build/release/SwiftSeek`，也有本地忽略的 `SwiftSeek.app`。README 当前仍以 `.build/release` 为主，未提供“如何确认当前运行的 bundle 已刷新”的稳定路径。
- 为什么是问题：用户反馈过“设置窗口 / Run Count 看不到”等可见问题，其中一个现实风险是源码和当前运行 App 不是同一个构建。没有 build identity 时，排查只能猜。
- 用户影响：用户以为 bug 没修；开发者以为代码有回归；实际可能只是运行了旧 App。
- 推荐优先级：高。
- 建议解决阶段：K1。

## 4. 设置窗口 / 菜单生命周期需要 release gate

- 当前现状：J1 已实现 `windowShouldClose` hide-only close、Dock reopen、主菜单 / 菜单栏重开；J6 后又出现过设置菜单无反应，后续 hotfix 改用 KVO 观察 tab index，避免非法 `tabView.delegate`。
- 为什么是问题：窗口生命周期是用户真实踩过的问题，不能只靠一次轨道验收。每次 release 都必须把设置窗口关闭 / 重开 / tab 切换 / Dock reopen 放进门禁。
- 用户影响：设置入口一旦失效，roots、DB 维护、Launch at Login、权限引导全部不可用。
- 推荐优先级：高。
- 建议解决阶段：K1 / K6。

## 5. 缺少稳定版本 / commit / build 标识

- 当前现状：About pane 只有 `v1 开发中`、DB path、schema、roots、excludes、files、hidden、last rebuild；启动日志只打印 DB path 和 schema。没有 app version、git commit、build timestamp、bundle path、executable path 或 package identity。
- 为什么是问题：产品化排障首先要知道“用户运行的是哪个版本”。当前无法从 UI 或日志直接判断旧 bundle、旧二进制、旧 schema 文档漂移。
- 用户影响：用户反馈 bug 时无法提供准确版本；开发者难以复现与定位。
- 推荐优先级：高。
- 建议解决阶段：K1 / K3。

## 6. 缺少安装 / 升级 / 回滚流程

- 当前现状：README 仍是开发者式 `swift build` / `swift run` / `.build/release`；没有拖入 `/Applications`、退出旧 app、替换 app、验证 build identity、保留旧版本、schema 回滚限制等流程。
- 为什么是问题：成熟工具必须让用户知道如何安装、升级、回滚。尤其 SwiftSeek 有 SQLite schema migration，旧 App 跑新 DB 可能有真实兼容风险。
- 用户影响：升级时可能同时跑新旧实例，或用旧 App 打开新 schema DB，导致行为不可预测。
- 推荐优先级：中到高。
- 建议解决阶段：K4。

## 7. Launch at Login 在未签名 app 下存在真实限制

- 当前现状：`LaunchAtLogin.swift` 使用公开 `SMAppService.mainApp`，并已经在注释和 UI 文案里提示未签名 / 未公证构建可能失败或需要系统批准。但缺少正式安装包语境下的系统状态诊断、安装位置建议和 release QA。
- 为什么是问题：Login Item 依赖 app bundle 与签名状态。裸 SwiftPM binary 或 ad-hoc bundle 可能注册失败、需要批准或登录后不稳定。
- 用户影响：用户勾选了“随登录启动”但实际没有启动，会认为 App 不可信。
- 推荐优先级：中。
- 建议解决阶段：K4。

## 8. Full Disk Access / 权限引导仍需产品化

- 当前现状：J6 首次使用 banner 已提示 Documents / Desktop / Downloads / 外置卷权限和 Full Disk Access；RootHealth 也能显示 offline / unavailable。但权限诊断仍分散在 banner、roots 状态和 manual test，没有形成产品化的“重新检查权限 / 解释 root 覆盖”流程。
- 为什么是问题：macOS 文件搜索器接近 Everything 的主要障碍是权限。用户需要知道哪些 root 可访问、哪些不可访问、为什么搜不到。
- 用户影响：用户把权限问题误判为搜索问题或索引问题。
- 推荐优先级：中。
- 建议解决阶段：K5。

## 9. 缺少 release QA checklist

- 当前现状：`docs/manual_test.md` 包含大量历史手测步骤，但没有围绕 release artifact 的统一 checklist：fresh clone、package app、launch app、settings reopen、hotkey、add root、search、open file、Run Count、DB stats、Launch at Login note、icon、About build identity。
- 为什么是问题：功能轨道的验收不等于发布验收。没有 release checklist，容易漏测安装物和运行物的真实体验。
- 用户影响：每次发布都有可能带着旧 bundle、旧 icon、旧 plist、设置窗口回归或未验证权限提示。
- 推荐优先级：高。
- 建议解决阶段：K6。
