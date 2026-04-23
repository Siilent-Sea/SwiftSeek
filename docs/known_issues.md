# SwiftSeek 已知问题 / 当前限制（P6 快照，2026-04-23）

本文档列出 v1 已知限制和当前环境约束。**这些不是 bug，是 v1 明确不做或暂不支持的项**，提交给 Codex 做最终验收时一并披露。

## 环境约束

### 1. 必须在 macOS 13+ 上构建与运行
- 目标 `.macOS(.v13)`，低于 13 的系统 AppKit / FSEvents 行为不保证
- Apple Silicon 与 Intel 都可用，release 二进制跟随本机架构

### 2. 无 Xcode.app 时只能 SwiftPM 构建
- 本仓未提供 `.xcodeproj` / `.xcworkspace`
- 仅安装 `CommandLineTools` 的机器可用 `swift build` / `swift run ...` 正常工作
- 装了 Xcode.app 的机器可 `open Package.swift` 让 Xcode 自动生成工程
- 未来若需要 `xcodebuild`，再补 `SwiftSeek.xcodeproj`

### 3. 无 code signing / notarization / .app bundle
- P6 交付路径是 `scripts/build.sh` → `.build/release/SwiftSeek` 原生 Mach-O 可执行
- 首次运行被 Gatekeeper 挡住时可：
  - 在 Finder 里右键 → 打开（一次性授权）
  - 或 `sudo spctl --add .build/release/SwiftSeek`
  - 或 `xattr -d com.apple.quarantine .build/release/SwiftSeek`（如果 zip/download 被打了隔离标）
- 正式 .app bundle + 签名 + 公证需要 Apple Developer 账号，属于 v1 范围外

### 4. 受限沙箱（`codex exec` workspace-write）下的构建约束
- clang module cache 默认路径 `~/.cache/clang` 在沙箱下不可写
- 必须在命令前加：`HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache`
- 脚本写法：`./scripts/build.sh --sandbox`
- 首次索引默认库路径 `~/Library/Application Support/SwiftSeek/index.sqlite3` 在沙箱下也不可写，需改用 `SwiftSeekIndex --db /tmp/...` 或直接跑 `SwiftSeekStartup --db /tmp/...`

### 5. 受限沙箱下 FSEvents 不可用
- `codex exec` workspace-write 沙箱阻塞 `com.apple.FSEvents.client` mach 服务
- `IncrementalWatcher.start()` 可能返回 `true` 但从不派发事件，或直接返回 `false`
- P3 round 2 新增 `PollingWatcher` 作为真实 fallback backend：用 `FileManager.enumerator` + mtime/size 差集，不依赖 FSEvents
- 终端用户环境（没有沙箱闸门）FSEvents 先到，polling 是冗余
- `SwiftSeekIndex --no-poll` 可关 polling（仅用于确认 FSEvents 已可用的环境）

## v1 功能范围外（明确不做）

### 搜索
- 全文内容搜索：仅搜文件名与路径
- OCR：不识别图片/PDF 里的文字
- 语义搜索 / AI：无语义理解，纯字符串匹配（前缀 / 包含 / 3-gram）

### 平台
- Windows / Linux 不支持：用 AppKit + FSEvents + Carbon，都是 macOS-only
- iOS / iPadOS 不支持：v1 只做桌面

### 存储同步
- 云盘（iCloud Drive、Dropbox、OneDrive 等）不一致性：SwiftSeek 通过 FSEvents / polling 感知本地文件系统变化，云盘的离线 / 增量下载状态不保证实时同步
- 外接盘弹出后未重新挂载时的索引残留：目前靠手工移除 root 或重建

### 权限
- "辅助功能"权限：**不需要**；全局热键走 Carbon `RegisterEventHotKey`，Spotlight 式授权模型
- Full Disk Access：未要求；默认只能索引用户有读权限的目录
- 索引系统目录（`/System` / `/Library` 等）需要用户手动在"隐私与安全性 → 完整磁盘访问权限"授权

### 交付
- 不提供自动更新器
- 不提供 Launch Agent / 开机自启动
- 不提供 Dock 菜单或 Menu Bar extra
- 不提供 Widget / Shortcuts / Siri 集成

## 运行时行为说明

### disable root 语义
- **停用（⏸）**：保留已索引行，但 `SearchEngine` 在查询时过滤，不返回
- **启用（✅）**：无需重建，搜索立即恢复返回
- **移除**：级联清 `files` 表所有属于该 root 的行 + 删除 `roots` 行，不可逆
- 停用与启用之间切换时数据无损

### exclude 生效时机
- 新增 exclude 时 `IndexingPane.onAddExclude` 会**立即** `deleteFilesMatchingExclude` 清理已索引子树；所以切换后搜索立刻不命中
- 首次索引 / 重建 / 增量扫描都会读当前 excludes，确保新路径不会被写入

### 隐藏文件开关
- **定义**：路径任意段以 `.` 开头（`.git`、`.DS_Store`、`.config` 等；**不**包括 `foo.bar`）
- 切换开关**不会**自动触发重建；手动到 `维护 → 重建索引` 让改动对已索引数据生效

### schema 迁移
- 当前 `Schema.currentVersion = 3`
- v1 → v2：加 `path_lower` 列 + `file_grams` 表 + `backfillFileGrams()` 自动回填（P2）
- v2 → v3：新增 `settings(key, value)` 表（P5）
- 迁移在事务中运行；失败会 `ROLLBACK`
- 降级不支持：v3 数据库不能被 v2 代码打开（`user_version` 锁住）

### 日志定位
- 所有错误通过 `NSLog` 写到系统日志
- 查看：`log stream --predicate 'process=="SwiftSeek"'` 或 Console.app 过滤 `SwiftSeek`
- CLI 工具（`SwiftSeekIndex`、`SwiftSeekSearch`、`SwiftSeekStartup`、`SwiftSeekSmokeTest`）同时写 stdout / stderr

## 已知小问题

### Gatekeeper 首次运行拦截
现象：从 `.build/release/SwiftSeek` 直接启动，可能被 Gatekeeper 挡住。
处理：见上文 "3. 无 code signing" 段落的三种解法。

### ⌥Space 与其他 App 冲突
现象：如果 Spotlight 或其他 App（Alfred / Raycast）已占用 ⌥Space，`GlobalHotkey.register()` 会返回 `false`，日志里会看到：
```
SwiftSeek: global hotkey registration failed — fallback to menu item 搜索…
```
处理：用菜单 `SwiftSeek → 搜索…` 作为兜底入口（同样带 ⌥Space keyEquivalent，但此时是窗口内本地快捷键）；或禁用占用 ⌥Space 的其他 App，重启 SwiftSeek。
v1 未提供"修改热键"的 UI；需要改则临时改 `GlobalHotkey.defaultKeyCode` / `defaultModifiers` 常量后重新编译。

### polling 间隔与 CPU
现象：`SwiftSeekIndex --watch --poll-seconds 0.5` 在大目录下 CPU 占用偏高（每 0.5s 全量 stat）。
处理：默认 1.0s 是一个经验值；设更长的 interval 减小 CPU；FSEvents 可用时优先用 FSEvents，polling 只是冗余。

### 中文 / CJK 目录名
现象：3-gram 对短 CJK 字符串（< 3 字）走 LIKE fallback，性能与 ASCII 不一样。
处理：v1 已覆盖；若结果不符预期，请在 issue 里附 query + 预期结果 + `--show-score` 输出。

## 运行时观测要点

- 启动日志：`SwiftSeek: database ready at <path> schema=3`（未打印即启动失败，看 `presentFatal` 对话框）
- 热键注册成功日志：**无**（失败才有日志，上面列过）
- Rebuild 失败：`SwiftSeek: RebuildCoordinator stampResult failed: ...` 或维护 tab 状态栏显示 `failed: <msg>`
- 搜索 roots 读失败：`SwiftSeek: SearchEngine listRoots failed, falling back to unfiltered search: ...`
- 设置页 DB 读失败：`SwiftSeek: IndexingPane listRoots/listExcludes failed: ...` / `SwiftSeek: AboutPane ... failed: ...`，UI 会展示 `读取...失败：<msg>` 而非静默空白

## v2+ 路线（仅登记方向，v1 不做）
- 文件内容索引（可选 full-text）
- 自动更新器（Sparkle）
- `.app` bundle + 签名 + 公证
- 热键自定义 UI
- 外接盘 / 云盘挂载事件处理
- Menu Bar extra / Dock 菜单
