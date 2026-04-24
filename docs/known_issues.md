# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage` 都已归档；当前活跃轨道是 `everything-ux-parity`，重点是桌面 App 行为、Run Count 可见性和 Everything-like UX parity。

## 当前活跃轨道相关限制

### 1. 设置窗口关闭后可重新打开（J1 已解决）
- 用户报告：设置窗口点左上角关闭后再次无法打开，只能 Dock 右键退出重启。
- J1 修复：
  - `SettingsWindowController` conform `NSWindowDelegate`，在 init 末尾 `window.delegate = self`。
  - `windowShouldClose(_:)` 只 `orderOut` 并返回 `false` —— 窗口从不进入 "closed" 状态，下一次 `makeKeyAndOrderFront` 是确定性的重排序到前。
  - 保留 `isReleasedWhenClosed = false`。
- 验证：菜单栏"设置…"、主菜单 `SwiftSeek → 设置…` 和 Dock reopen 均能重新打开；smoke 覆盖 10 次关闭/打开循环。

### 2. Dock / Menu Bar / 主菜单生命周期已成熟（J1 已解决）
- `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` 在无可见窗口时调 `showSettings`，覆盖 Dock 点击。
- `AppDelegate.showSettings(_:)`：`NSApp.activate(ignoringOtherApps:)` 提前调用；若 `settingsWindowController?.window == nil` 防御性重建。
- 菜单栏 `NSStatusItem` 的"设置…" + 主菜单 `SwiftSeek → 设置…` 均挂 `showSettings` selector。
- `applicationShouldTerminateAfterLastWindowClosed` 保持 `false` 确保关窗不退 App。

### 3. Run Count 统计范围仅限 SwiftSeek 内部 open
- `Run Count` / `打开次数` 只表示通过 SwiftSeek 成功触发 `.open` 的次数。
- 不读取 macOS 全局启动次数。
- 不读取系统最近项目。
- 不扫描系统隐私数据。
- 不使用 private API。
- Reveal in Finder / Copy Path 不计入 Run Count。

### 4. Run Count 数据层已存在，但用户可见性待复核
- 当前代码已有：
  - Schema v6 `file_usage`
  - `Database.recordOpen(path:)`
  - `SearchResult.openCount` / `lastOpenedAt`
  - `SearchEngine` 的 `LEFT JOIN file_usage`
  - 结果表“打开次数” / “最近打开”两列
  - `recent:` / `frequent:` 查询入口
  - 使用历史开关与清空入口
- 但用户反馈没看到“启动次数 / Run Count”，因此 J2 必须复核：
  - 打开动作是否实际写入当前 DB
  - 结果列是否默认可见
  - 列宽是否被历史持久化状态压窄
  - 文案是否足够清楚
  - 用户运行的二进制是否为最新构建
- 不能因为 H1-H5 已 `PROJECT COMPLETE` 就忽略用户可见性问题。

### 5. Everything-like 查询语法仍不完整
- 已支持：`ext:` / `kind:` / `path:` / `root:` / `hidden:` / `recent:` / `frequent:`。
- 仍不支持：
  - `*` wildcard
  - `?` wildcard
  - quoted phrase，例如 `"foo bar"`
  - OR，例如 `foo|bar`
  - NOT，例如 `!foo` 或 `-foo`
  - 括号表达式
  - regex
- J3 只处理 wildcard / quote / OR / NOT；括号和 regex 默认不纳入。

### 6. 搜索历史 / Saved Filters 仍缺失
- 当前没有最近查询历史。
- 当前没有 Saved Filters / 收藏查询。
- 当前没有快速过滤器入口。
- 这会让高频用户反复输入相同 `ext:` / `path:` / `root:` 组合。
- J4 处理这些能力，并且必须保持本地、不上传、不遥测。

### 7. 上下文菜单动作不足
- 当前结果右键菜单只有：
  - Open
  - Reveal in Finder
  - Copy Path
  - Move to Trash
- 仍缺：
  - Open With...
  - Copy Name
  - Copy Full Path 的更明确文案
  - Copy Parent Folder
  - Copy Multiple Paths（如果支持多选）
  - Rename（如成本可控）
- J5 处理这些文件操作增强；破坏性操作必须确认。

### 8. 首次使用 / Full Disk Access / Launch 行为还不完整
- 当前设置窗口有 roots 为空时的引导条，但还没有完整首次使用流程。
- Full Disk Access、不可访问 root、compact/fullpath 模式、Run Count 语义和 usage history 隐私边界需要更明确的用户引导。
- Launch at Login 如果要做，必须考虑当前 SwiftPM / app bundle / code signing 状态；不能假装未签名命令行产物已经具备完整登录项体验。

## 已归档轨道后的保留限制

### DB footprint
- Compact 模式已将 500k 实测 main DB 从 fullpath 3.46 GB 降到 1.07 GB。
- Full path substring 模式仍可选，但体积更大。
- VACUUM / checkpoint 是维护入口，不是替代 compact 的根治方案。
- 500k 下 warm 3+char 会超出 F1 在 10k 规模时设定的旧目标，这是已记录的规模效应事实。

### 搜索相关性
- 当前已有 plain token AND、basename / token boundary / path segment / extension bonus。
- 当前已有 usage-based tie-break：同 score 下按 openCount DESC -> lastOpenedAt DESC 排序。
- 它仍是启发式相关性，不是成熟 Everything ranking 模型；learning-to-rank / 统计模型不在当前 UX parity 主线范围。

### RootHealth
- 已有 ready / indexing / paused / offline / unavailable。
- 设置页 roots 列表和搜索 0 结果空态会暴露部分状态。
- UX parity 只会在 J6 补权限 / 首次使用引导，不重新打开 RootHealth 数据模型。

## 环境约束

### 必须在 macOS 13+ 上构建与运行
- 目标 `.macOS(.v13)`。
- Apple Silicon 与 Intel 都可用，release 二进制跟随本机架构。

### 无 Xcode.app 时只能 SwiftPM 构建
- 仓库未提供 `.xcodeproj` / `.xcworkspace`。
- 仅安装 Command Line Tools 的机器可用 `swift build` / `swift run ...`。

### 无 code signing / notarization / .app bundle
- 当前交付路径是 `scripts/build.sh` 到 `.build/release/SwiftSeek`。
- 正式 `.app` bundle + 签名 + 公证不在当前范围内。

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

## 运行时补充说明

### disable root 语义
- 停用：保留已索引数据，但搜索不返回。
- 启用：无需重建，搜索立即恢复。
- 移除：级联清理该 root 下记录。

### Gatekeeper 首次运行拦截
- release 可执行首次运行可能被 Gatekeeper 拦截。
- 这属于未签名交付的预期限制。
