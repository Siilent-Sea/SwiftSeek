# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。历史轨道 `v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`、`everything-productization` 均已归档；当前活跃轨道是 `everything-menubar-agent`。

## 当前活跃轨道相关限制

### 1. 默认隐藏 Dock 图标（L1 已落地）

- `AppDelegate.applicationDidFinishLaunching` 在最早期（NSLog build identity 三连之后）调用 `NSApp.setActivationPolicy(.accessory)`，使 Dock 不显示 SwiftSeek 图标。
- `Info.plist` 仍保留 `LSUIElement=false`：选择运行时 activation policy 而非 plist `LSUIElement=true` 的取舍写在 `scripts/package-app.sh` 注释和 `docs/install.md` 默认形态段。
- L2 会基于 runtime activation policy 加 "显示 Dock 图标" 设置开关；plist 路径保留以便 L2 不需要 user 重打包就能切。
- 在 ad-hoc / 未签名 bundle 上，不同 macOS 版本对 activation policy 的稳定性仍需手测；release checklist §5b 强制每次发布手动确认。

### 2. 菜单栏 status item 是默认主入口（L1 已落地）

- `AppDelegate.installStatusItem()` 安装的 `NSStatusItem` 是 L1 之后用户与 SwiftSeek 交互的主入口。
- 当前菜单栏菜单包含：
  - 搜索…（⌥Space）
  - 设置…（⌘,）
  - 索引：空闲 / 索引中（只显示）
  - 退出 SwiftSeek（⌘Q）
- L1 不扩展菜单栏复杂状态项；L3 才做最近打开 / 常用 / 索引模式 / DB 大小 / root 简况。
- L1 不再依赖 Dock reopen 作为默认入口；`applicationShouldHandleReopen` 仅作为 fallback（`open` 第二次时弹设置窗口）。

### 3. 无 Dock 模式下的入口与退出（L1 已落地）

- J1/J6 之前依赖 Dock click 唤回设置窗口；L1 改为依赖菜单栏图标 + 全局热键。
- 退出路径优先级：菜单栏 → "退出 SwiftSeek"（⌘Q） > `pkill -f "SwiftSeek.app"` > Activity Monitor 强制退出。
- `applicationShouldHandleReopen` 仍保留：双击已运行的 SwiftSeek.app 第二次会弹设置窗口作为 fallback，避免"双击没反应"的迷惑感。
- 菜单栏图标在某些极端场景（屏幕过窄被挤掉、stale bundle 在跑、Gatekeeper 拦截）可能不出现；`docs/install.md` 默认形态段写了排查矩阵。

### 4. LSUIElement / activationPolicy 在 ad-hoc App 下需要实测

- 当前 SwiftSeek 仍是 ad-hoc codesign，不是 Developer ID 签名，不做 notarization。
- `LSUIElement=true` 与 `NSApp.setActivationPolicy(.accessory)` 都会影响 Dock、Command+Tab、主菜单可见性和窗口前置行为。
- macOS 不同版本、LaunchServices 缓存、未签名 / ad-hoc bundle 可能表现有差异。
- L1/L2 必须用真实 `dist/SwiftSeek.app` 手测，不能只看源码推断。

### 5. 退出路径必须明确

- 隐藏 Dock 后，用户不能靠 Dock 右键退出。
- 当前 status item 的"退出 SwiftSeek"是关键路径，必须纳入 release gate。
- 如果 status item 异常，文档需要保留备用路径，例如 Activity Monitor、`pkill -f SwiftSeek` 或重新打开 app 后退出。

### 6. 多开 / 旧 bundle 风险仍存在

- productization 轨道已补 build identity 和 stale bundle 排查，但当前没有单实例保护。
- 同一台机器仍可能同时存在：
  - `dist/SwiftSeek.app`
  - `/Applications/SwiftSeek.app`
  - `~/Downloads/SwiftSeek.app`
  - `.build/release/SwiftSeek`
- 菜单栏 agent 形态下，多开更难被用户注意到，可能出现多个菜单栏图标、hotkey 争用、DB 写竞争或操作到旧 build。
- L4 需要单实例 / 多 bundle 防护与最终收口。

### 7. 隐藏 Dock 的用户可配置性尚未完成

- 当前设置中没有"显示 Dock 图标"或"菜单栏模式"开关。
- L1 只要求默认隐藏 Dock；L2 才处理用户可恢复 Dock 的设置项。
- 如果动态切换 activation policy 不稳定，应诚实提示"需重启生效"。

### 8. 菜单栏状态信息仍偏基础

- 当前 status item tooltip 只是"SwiftSeek 搜索"。
- 菜单里只有基本索引状态，没有 build version、index mode、root count、DB 大小等简要信息。
- L3 会把菜单栏从入口扩展成可快速判断状态的主入口，但不做臃肿 dashboard。

## 已归档能力与仍保留边界

### Productization 已完成；L1 已把默认形态切到菜单栏 agent

- `everything-productization` 已完成可重复 `.app` 打包、Info.plist / icon / ad-hoc codesign、build identity、diagnostics、install / rollback 文档、Full Disk Access / root 覆盖引导和 release checklist。
- L1 在 productization 之上把默认 activation policy 切成 `.accessory`，Dock 不再常驻；菜单栏 status item 是主入口；release_checklist §5b 把 no-Dock 验证写成强制项。
- L2-L4 仍未完成：Dock 显示开关、菜单栏增强（最近 / 常用 / 索引摘要）、单实例与多 bundle 防护。

### Run Count 统计范围

- `Run Count` / `打开次数` 只表示通过 SwiftSeek 成功触发 `.open` 的次数。
- 不读取 macOS 全局启动次数。
- 不读取系统最近项目。
- 不扫描系统隐私数据。
- 不使用 private API。

### 查询和搜索边界

- 已支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:` / `recent:` / `frequent:`。
- 已支持 wildcard / quote / OR / NOT。
- 仍不做全文内容搜索、OCR、AI 语义搜索、regex、括号表达式。

### DB footprint

- Compact 模式已将 500k 实测 main DB 从 fullpath 3.46 GB 降到 1.07 GB。
- Full path substring 模式仍可选，但体积更大。
- VACUUM / checkpoint 是维护入口，不是替代 compact 的根治方案。

## 环境约束

- macOS 13+。
- SwiftPM 工程，无 `.xcodeproj` / `.xcworkspace`。
- 当前本地交付仍是 ad-hoc bundle；正式 Developer ID 签名、notarization、DMG、auto updater 不在当前默认范围。

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
