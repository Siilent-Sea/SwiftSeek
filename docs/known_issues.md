# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity` 均已归档；当前活跃轨道是 `everything-productization`，重点是产品化、安装、打包、生命周期回归门禁和诊断能力。

## 当前活跃轨道相关限制

### 1. 当前构建链路仍不是完整安装包
- `scripts/build.sh` 当前只构建 `.build/release/SwiftSeek*` 可执行文件，并运行 smoke / startup check。
- 脚本注释仍明确“不做签名 / notarization / .app bundle”。
- README 当前也主要描述 `.build/release` 二进制交付。
- 这意味着 SwiftSeek 当前更像开发者本地运行产物，不是成熟的“下载 / 拖入 Applications / 启动 / 升级 / 回滚”工具。

### 2. `.app` / icon / Info.plist / codesign 仍存在手工或半手工环节
- `scripts/make-icon.swift` 只生成 iconset PNG，并要求手工 `iconutil -c icns`。
- 本地存在 `SwiftSeek.app/Contents/Info.plist` 和 `AppIcon.icns`，但 `SwiftSeek.app/` 被 `.gitignore` 忽略。
- 本地 app 当前是 ad-hoc signed，`codesign -dv` 可见 `Signature=adhoc`、`TeamIdentifier=not set`。
- Info.plist / icon / codesign 还没有纳入可重复 package 脚本。
- 因此当前不能把本地 `.app` 当作稳定交付流水线产物。

### 3. 旧 bundle / stale binary 风险
- 用户可能同时拥有：
  - 最新源码
  - `.build/release/SwiftSeek`
  - 本地被忽略的 `SwiftSeek.app`
  - `/Applications` 中的旧 SwiftSeek.app
- K1 已补上 About / diagnostics / startup log 的 build identity，但这不等于 stale bundle 风险彻底消失。
- 用户仍可能遇到“源码已经修了，但双击启动的还是旧 App”。
- 当前应通过 About 顶部 summary、诊断中的 `bundle:` / `binary:` 和启动日志三连来核对自己到底跑的是哪一个产物；K2 会继续把这条链路接到可重复 package 流程。

### 4. 设置窗口 bug 已修，但必须进入 release gate
- J1 已修设置窗口关闭后不可重开：
  - `SettingsWindowController.windowShouldClose(_:)` hide-only close。
  - `AppDelegate.applicationShouldHandleReopen` 支持 Dock reopen。
  - 主菜单 / menu bar 设置入口指向 `showSettings`。
- J6 后设置菜单无反应又出现过一次，后续 hotfix 用 KVO 观察 `selectedTabViewItemIndex`，避免非法 `tabView.delegate`。
- 这类生命周期问题必须作为每次 release 的门禁，不应只依赖历史 `PROJECT COMPLETE`。

### 5. Build identity 已在 K1 落地
- `Sources/SwiftSeekCore/BuildInfo.swift` 提供运行时 build identity surface：从 `Bundle.main.infoDictionary` 读 `CFBundleShortVersionString` / `GitCommit` / `BuildDate`，dev 路径回落到静态 fallback ("1.0-dev" / "dev" / "unknown")。
- `AppDelegate.applicationDidFinishLaunching` 启动头三行日志：`SwiftSeek: SwiftSeek <version> commit=<hash> build=<date>` / `bundle=<path>` / `binary=<path>`。
- About 面板顶部 versionLabel 显示 `BuildInfo.summary`；诊断块以五行 build identity 起始（版本 / commit / build date / bundle / binary）；新加 "复制诊断信息" 按钮一键写剪贴板。
- 当前 `.app` bundle Info.plist 已手动添加 `GitCommit` / `BuildDate` 键；K2 的 `scripts/package-app.sh` 会自动写入。
- 用户反馈 bug 时贴 About → 复制诊断信息 即给出完整 build identity，不再需要靠截图猜版本。

### 6. 未签名 / 未公证带来的 macOS 行为边界
- 当前没有 Apple Developer ID 签名。
- 当前没有 notarization。
- Gatekeeper、Launch Services、Launch at Login、登录项批准等行为会受到未签名 / ad-hoc bundle 影响。
- `LaunchAtLogin.swift` 使用公开 `SMAppService.mainApp`，但未签名 / 未公证构建可能失败、需要用户在系统设置批准，或登录后行为不稳定。
- 当前轨道可以做 ad-hoc 本地包和诚实提示，不应假装已完成正式签名发行。

### 7. 缺少正式安装 / 升级 / 回滚流程
- 当前没有清晰文档说明：
  - 如何生成 app bundle。
  - 如何安装到 `/Applications`。
  - 升级前如何退出旧 App。
  - 如何确认替换成功。
  - 如何保留旧版本回滚。
  - 新 DB schema 与旧 App 的兼容限制。
- 对 SwiftSeek 这种 SQLite schema 持续演进的工具，回滚限制必须写清。

### 8. 权限 / Full Disk Access / root 覆盖引导仍需产品化
- J6 已有首次使用 banner，RootHealth 已能显示 offline / unavailable / paused。
- 但权限诊断仍没有形成统一产品流程：
  - root 可访问性复查。
  - Full Disk Access 指引。
  - external volume offline 与 permission denied 的区分。
  - “重新检查权限”入口。
- 用户仍可能把权限问题误判为搜索或索引问题。

### 9. 缺少 release QA checklist
- 历史 `docs/manual_test.md` 很长，但不是面向最终 release artifact 的一页 checklist。
- 当前需要把以下项目固定为 release gate：
  - fresh clone build
  - package app
  - launch app
  - settings reopen
  - search hotkey
  - add root
  - search
  - open file
  - Run Count update
  - DB stats
  - Launch at Login note
  - app icon
  - About build identity
  - install / upgrade / rollback docs

## 已归档能力与仍保留边界

### UX parity 已完成但不等于产品化完成
- `everything-ux-parity` 已完成设置窗口 hide-only close、Dock reopen、Run Count 可见性、wildcard / quote / OR / NOT、搜索历史 / Saved Filters、上下文菜单、首次使用 banner、窗口状态记忆和 Launch at Login 公开 API 包装。
- 这些是功能与体验闭环，不是 release packaging 闭环。

### Run Count 统计范围
- `Run Count` / `打开次数` 只表示通过 SwiftSeek 成功触发 `.open` 的次数。
- 不读取 macOS 全局启动次数。
- 不读取系统最近项目。
- 不扫描系统隐私数据。
- 不使用 private API。

### 查询和搜索边界
- 已支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:` / `recent:` / `frequent:`。
- 已支持 J3 的 wildcard / quote / OR / NOT。
- 仍不做全文内容搜索、OCR、AI 语义搜索、regex、括号表达式。

### DB footprint
- Compact 模式已将 500k 实测 main DB 从 fullpath 3.46 GB 降到 1.07 GB。
- Full path substring 模式仍可选，但体积更大。
- VACUUM / checkpoint 是维护入口，不是替代 compact 的根治方案。

## 环境约束

### 必须在 macOS 13+ 上构建与运行
- 目标 `.macOS(.v13)`。
- Apple Silicon 与 Intel 都可用，release 二进制跟随本机架构。

### 无 Xcode.app 时只能 SwiftPM 构建
- 仓库未提供 `.xcodeproj` / `.xcworkspace`。
- 仅安装 Command Line Tools 的机器可用 `swift build` / `swift run ...`。

### 受限沙箱下的构建约束
```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/build.sh --sandbox
```

## 明确不做
- 全文内容搜索
- OCR
- AI 语义搜索
- 云盘 / 网络盘实时一致性承诺
- 跨平台
- Electron / Tauri / Web UI 替代原生
- APFS 原始解析
- Finder 插件
- App Store 沙盒适配
- macOS 全局启动次数读取
- 系统隐私数据扫描
- private API
- 在没有证书与明确要求时承诺正式签名 / 公证
