# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity` 均已归档；当前活跃轨道是 `everything-productization`，重点是产品化、安装、打包、生命周期回归门禁和诊断能力。

## 当前活跃轨道相关限制

### 1. K2 已建立可重复 .app 打包流水线
- `scripts/package-app.sh` 现在能一条命令完成：`swift build -c release` + lay out `dist/SwiftSeek.app` + 写 `Info.plist` + 生成 `AppIcon.icns` + ad-hoc `codesign` + 自检。
- `.icns` 由 `scripts/make-icon.swift` 直接写出，不再依赖 `iconutil`，规避了本地与 Codex 沙箱之间的 `iconutil` 漂移。
- 当前可验证产物：
  - `dist/SwiftSeek.app/Contents/Info.plist`
  - `dist/SwiftSeek.app/Contents/MacOS/SwiftSeek`
  - `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns`
  - `dist/SwiftSeek.app/Contents/_CodeSignature/CodeResources`
- `scripts/build.sh` 仍专注 `.build/release` CLI 二进制；`.app` 正式本地交付路径是 `scripts/package-app.sh`。

### 2. 仍未做正式发行级签名 / 公证
- 当前是 ad-hoc `codesign`，不是 Apple Developer ID 签名。
- 当前没有 notarization。
- 当前没有 DMG、auto updater、`/Applications` 安装/升级/回滚流程。
- 因此 K2 证明的是“本地可重复 bundle 流水线成立”，不是“正式发行链路完成”。

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

### 5. Build identity + 完整诊断已在 K1 + K3 落地
- **K1**：`Sources/SwiftSeekCore/BuildInfo.swift` 提供运行时 build identity（version / commit / build date / bundle / binary），从 `Bundle.main.infoDictionary` 读，dev 路径有 fallback。`AppDelegate` 启动头三行 NSLog + About 顶部 summary 同步显示。
- **K2**：`scripts/package-app.sh` 自动注入 `GitCommit` / `BuildDate` 到 Info.plist。
- **K3**：抽出 `Sources/SwiftSeekCore/Diagnostics.swift` 纯函数 `Diagnostics.snapshot(database:launchAtLoginIntent:launchAtLoginSystemStatus:)` 作为单一来源；扩字段：
  - DB main / wal / shm 大小
  - files / file_usage / query_history / saved_filters 行数
  - 索引模式 / 隐藏文件开关 / usage history 开关 / query history 开关
  - roots（总+启用）/ excludes 计数
  - Launch at Login 用户意图 + 系统实际状态（SMAppService.enabled / .notRegistered / unsupported / headless）
  - last rebuild 时间 / 结果 / 摘要
- About 面板"复制诊断信息"按钮直接 export `Diagnostics.snapshot` 完整文本。
- bug-report 模板见 `docs/manual_test.md` §33u — 用户复制即用。
- 与 `SwiftSeekDBStats` CLI 口径一致（同一时刻读同一 `Database.computeStats()`）。

### 6. 未签名 / 未公证带来的 macOS 行为边界
- 当前没有 Apple Developer ID 签名。
- 当前没有 notarization。
- Gatekeeper、Launch Services、Launch at Login、登录项批准等行为会受到未签名 / ad-hoc bundle 影响。
- `LaunchAtLogin.swift` 使用公开 `SMAppService.mainApp`，但未签名 / 未公证构建可能失败、需要用户在系统设置批准，或登录后行为不稳定。
- 当前轨道可以做 ad-hoc 本地包和诚实提示，不应假装已完成正式签名发行。

### 7. 安装 / 升级 / 回滚流程已在 K4 文档化
- `docs/install.md` 是 K4 的单一入口，覆盖：
  - **安装**：`./scripts/package-app.sh` → `cp -R dist/SwiftSeek.app /Applications/` → 首次打开 / Gatekeeper / xattr quarantine 处理
  - **升级**：退出旧 → 重新打包 → 替换 → 用 build identity 核对 commit hash 是否匹配
  - **回滚**：备份 DB → 替换 binary → schema forward-only 边界（Schema v1→v7 表对照表）→ 旧 binary 打开新 schema DB 的风险与建议（删 DB / 重命名让旧 binary 重建）
  - **Launch at Login 边界**：未签名 / ad-hoc 可能需手动批准；`dist/` 直接跑通常注册不上
  - **多实例 / stale bundle**：通过 About → 顶部 summary + bundle/binary 行 + Console 启动头三行判断；替换失败常见原因（旧进程没退、LaunchServices 缓存、`cp -R` 残留）
  - **卸载**：bundle / DB / preferences / 登录项的清单
- README 快速上手段已加入 install.md 链接，让用户从首页进入即可找到完整流程。
- 当前 schema 已是 v7（H2 引入 query_history / saved_filters）。回滚到 K1 之前的 binary 必须先备份 DB；`Database.migrate()` 永远 forward-only。

### 8. 权限 / Full Disk Access / root 覆盖引导（K5 已落地）
- **K5 已收口**：
  - **RootHealth 状态从 3 类细化到 4+ 类**：`.ready` / `.indexing` / `.paused` / `.offline`（路径不存在）/ `.volumeOffline`（`/Volumes/<X>` 卷未挂载）/ `.unavailable`（权限不足）。
  - **每行带详细原因 tooltip**：`Database.computeRootHealthReport(for:)` 返回结构化 `RootHealthReport { health, detail }`，UI 把 detail 挂到 NSTextField.toolTip，鼠标停留即可看到判定依据。
  - **设置 → 索引 → "重新检查权限" 按钮**：不重启 app、不动 DB，重新评估每个 root 的当前状态。补完 Full Disk Access 后即用即检。
  - **设置 → 索引 → "打开完全磁盘访问设置" 按钮**：直接 `NSWorkspace.open` 到 `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`，授权失败回退通用隐私面板，再失败弹 NSAlert 手动指引。
  - **诊断块同步**：`Diagnostics.snapshot` 增加 `roots 健康（K5）：` 段，最多列 20 个 root，每行格式 `<徽标>  <路径>  — <详细原因>`，与 UI 完全同源。
  - **文档同步**：`docs/install.md` 新增"权限 / Full Disk Access / Root 覆盖（K5）"段，列出四种状态徽标的含义与恢复路径。
- 仍存在的边界：
  - macOS 权限模型本身不绕过：未签名 / ad-hoc bundle 在某些 macOS 版本下即使加了 Full Disk Access 也可能被 TCC 二次拦截。
  - 网络盘 / 云盘的实时一致性不承诺。
  - K5 不重做 K4 的安装文档，只补与权限恢复直接相关的交叉说明。

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
