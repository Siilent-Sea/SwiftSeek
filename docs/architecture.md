# SwiftSeek 架构（历史快照）

> Note:
> 这份文档主要保留 baseline / archived alignment 阶段的结构快照，不是当前 `everything-performance` 轨道的权威状态文档。
> 当前路线、差距与阶段目标以 `docs/stage_status.md`、`docs/everything_performance_gap.md`、`docs/everything_performance_taskbook.md` 为准。

## 技术栈
- Swift 6.3 / Swift Package Manager（本机无 Xcode.app）
- macOS 13+ 目标
- AppKit（GUI）
- SQLite（C 库，通过 `CSQLite` systemLibrary 封装 + `-l sqlite3`）
- FSEvents（P3 引入，通过 `CoreServices` 框架）
- Carbon `RegisterEventHotKey`（P4 全局热键，通过 `Carbon.HIToolbox` 框架；不需辅助功能权限）

## 目录结构
```
SwiftSeek/
├── Package.swift
├── Sources/
│   ├── CSQLite/                systemLibrary 包裹 <sqlite3.h>
│   │   ├── module.modulemap
│   │   └── shim.h
│   ├── SwiftSeekCore/          纯逻辑库（无 AppKit 依赖）
│   │   ├── AppPaths.swift
│   │   ├── CancellationToken.swift
│   │   ├── Database.swift
│   │   ├── EventQueue.swift
│   │   ├── FileRow.swift
│   │   ├── Gram.swift
│   │   ├── IncrementalWatcher.swift
│   │   ├── IndexProgress.swift
│   │   ├── Indexer.swift
│   │   ├── KeyboardSelection.swift  (P4)
│   │   ├── PollingWatcher.swift
│   │   ├── RebuildCoordinator.swift (P5)
│   │   ├── ResultAction.swift       (P4)
│   │   ├── Schema.swift
│   │   ├── SearchEngine.swift
│   │   └── SettingsTypes.swift      (P5)
│   ├── SwiftSeek/              GUI 可执行
│   │   ├── main.swift
│   │   ├── App/
│   │   │   ├── AppDelegate.swift
│   │   │   ├── GlobalHotkey.swift        (P4)
│   │   │   └── MainMenu.swift
│   │   └── UI/
│   │       ├── ResultActionRunner.swift  (P4)
│   │       ├── SearchViewController.swift (P4)
│   │       ├── SearchWindowController.swift (P4)
│   │       └── SettingsWindowController.swift
│   ├── SwiftSeekIndex/         P1 命令行索引器
│   │   └── main.swift
│   ├── SwiftSeekSearch/        P2 命令行搜索入口
│   │   └── main.swift
│   └── SwiftSeekSmokeTest/     冒烟测试可执行
│       └── main.swift
├── docs/
└── AGENTS.md / CLAUDE.md / README.md
```

## 模块边界
- `SwiftSeekCore`：数据库、路径、Schema、Indexer。不得引入 AppKit。便于替换 UI、便于用独立 runner 测试。
- `SwiftSeek`：AppKit 前端。拥有 `AppDelegate`、菜单、窗口。依赖 `SwiftSeekCore` 做持久化。
- `SwiftSeekIndex`：命令行首次全量索引工具。接受根目录参数，调用 `Indexer.indexRoot` 写入 SQLite。P3 起通过 `--watch` / `--watch-seconds N` 接管 FSEvents → EventQueue → `Indexer.rescanPaths` 增量链路，运行期按 Ctrl-C 停止。
- `SwiftSeekSearch`：命令行搜索入口。打开已索引的 SQLite，委派给 `SearchEngine.search` 并打印 `[score] f|d /path` 行。P4 UI 就绪前作为可重复触发的查询入口。
- `SwiftSeekSmokeTest`：仅依赖 `SwiftSeekCore`，不链接 AppKit。

## 数据库（schema=3）
位置：`~/Library/Application Support/SwiftSeek/index.sqlite3`

打开时 pragma：
- `journal_mode=WAL`
- `synchronous=NORMAL`
- `foreign_keys=ON`

表：
- `meta(key TEXT PRIMARY KEY, value TEXT)` 预留 KV
- `files(id, parent_id, path UNIQUE, path_lower, name, name_lower, is_dir, size, mtime, inode, volume_id)`
- `idx_files_name_lower`、`idx_files_path_lower`、`idx_files_parent`
- `file_grams(file_id REFERENCES files(id) ON DELETE CASCADE, gram TEXT, PRIMARY KEY(file_id, gram)) WITHOUT ROWID`
- `idx_file_grams_gram`
- `roots(id, path UNIQUE, enabled)` P5 `Database.listRoots / setRootEnabled / removeRoot`
- `excludes(id, pattern UNIQUE)` P5 `Database.listExcludes / addExclude / removeExclude / deleteFilesMatchingExclude`
- `settings(key PRIMARY KEY, value)` P5 K/V 表 — 存 `hidden_files_enabled` / `last_rebuild_at` / `last_rebuild_result` / `last_rebuild_stats`

迁移采用按 target 版本步进的 `Schema.migrations`（v1 建表，v2 加 `path_lower` + grams）。`user_version` 同步于 `Schema.currentVersion`；每条迁移在事务中完成。已有 P1 库首次打开时自动升到 v2 并回填 `path_lower`，再用 upsert 写入时顺带补齐 grams。

## 启动流
1. `main.swift` 创建 `NSApplication`，绑定 `AppDelegate`，`setActivationPolicy(.regular)`，`run()`
2. `AppDelegate.applicationDidFinishLaunching`：装菜单 → 创建 Application Support 目录 → 打开并迁移数据库 → 构造 `SearchWindowController(database:)` → 注册 `GlobalHotkey` → 打开设置窗口
3. 设置窗口为 `NSTabViewController`，含四个占位 pane：常规 / 索引范围 / 维护 / 关于
4. 全局热键按下（P4，默认 ⌥Space）→ `GlobalHotkey` 的 Carbon handler 派回主队列 → `SearchWindowController.toggle()`
5. 退出时 `applicationWillTerminate` 关闭数据库句柄

## P1 索引管线
1. `SwiftSeekIndex <rootPath>` 解析 CLI 参数，打开 / 迁移数据库
2. 安装 SIGINT handler（`DispatchSource.makeSignalSource`）→ 调用 `CancellationToken.cancel()`
3. `Indexer.indexRoot(rootURL)`：
   - `realpath(3)` 规范化根路径（修正 `/tmp → /private/tmp` 等 firmlink 差异）
   - `database.registerRoot(path:)` 写入 `roots` 表（`INSERT OR IGNORE`）
   - 可选 `database.clearFiles(underRoot:)`（默认开启，避免陈旧行）
   - `FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)` 递归遍历
   - 每行用 `makeRow(url:)` 读取 `isDirectory` / `fileSize` / `contentModificationDate`
   - 按 `batchSize`（默认 500）分批调用 `database.insertFiles(_:)`（单事务 `BEGIN IMMEDIATE` + `UPSERT`）
   - 每 `progressEvery` 条触发一次 `progress(IndexProgress)`
   - 每次循环头检查 `cancel.isCancelled`，命中则置 `cancelled=true` 并 break；post-loop flush 受 `!cancelled` 守卫——取消后不再 flush 命中时内存里的尾批，DB 里只保留此前已成功提交的完整批次
4. 输出 `IndexStats`（scanned / inserted / skipped / cancelled / 时长）；退出码：取消 130，正常 0，异常 1

## P2 搜索内核
1. `SwiftSeekSearch <query> [--db <path>] [--limit N] [--show-score]` 解析 CLI 参数，定位数据库
2. 打开并 `migrate()`，确保旧 P1 库能就地升级到 v2
3. `SearchEngine.search(raw)`：
   - `normalize(raw)`：trim → lowercase → `split(isWhitespace)` → `joined(" ")`，路径分隔符 `/` 保持不变
   - 若规范化后长度 < 3：走 `shortQueryCandidates`，以 `LIKE '%q%'` 匹配 `name_lower` 或 `path_lower`，候选数由 `limit * candidateMultiplier`（默认 `limit*4`）约束
   - 若长度 ≥ 3：走 `gramCandidates`，取 query 的 3-gram 集合，用 `SELECT ... FROM file_grams fg JOIN files f ... WHERE fg.gram IN (?,?,...) GROUP BY fg.file_id HAVING COUNT(DISTINCT fg.gram) = ?`，保证所有 gram 都出现过；随后在内存中再用 `nameLower.contains(q) || pathLower.contains(q)` 做子串严筛，去除 gram 非连续命中的假阳性
   - `rank(rows:query:)`：用固定分数函数 `score(query:nameLower:pathLower:)` 算分并过滤 0 分
4. 分数分层（更大更优）：
   - 1000：文件名精确等于 query
   - 800：文件名以 query 开头
   - 500：文件名包含 query（非开头）
   - 200：仅路径包含 query（文件名不包含）
5. 同分排序：路径短的在前 → 路径字典序在前
6. 索引写入：`Database.insertFiles(_:)` 在 `BEGIN IMMEDIATE` 事务内
   - 对 `files` upsert（`ON CONFLICT(path) DO UPDATE` 保持 path 唯一）
   - 查 `id` 后 `DELETE FROM file_grams WHERE file_id = ?`
   - 用 `Gram.indexGrams(nameLower:pathLower:)` = `grams(nameLower) ∪ grams(pathLower)` 生成要写入的 gram，再批量 `INSERT OR IGNORE INTO file_grams(file_id, gram)`。FK 设 `ON DELETE CASCADE`，后续删除 files 行会连带清 grams
7. CLI 退出码：0 正常；1 数据库不存在或搜索异常；2 参数不合法

## P3 增量管线
1. 首次全量索引走 P1 路径；`--watch` / `--watch-seconds N` 触发后续守夜
2. 双 backend 并行喂同一个 `EventQueue`（P3 round 2 加固，见下方"受限沙箱下的 polling fallback"）
3. `IncrementalWatcher.start()` 用 `FSEventStreamCreate` 注册已规范化的根路径
   - flags = `kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents`
   - `UseCFTypes` 保证回调里 `eventPaths` 是 CFArray of CFString，可直接桥成 `[String]`
   - `FileEvents` 让 FSEvents 以单文件粒度派发，简化后续处理
   - 通过 `FSEventStreamContext.info = Unmanaged.passRetained(self).toOpaque()` 把 watcher 实例传进 C 回调；`stop()` 时 `FSEventStreamRelease` + `release()` 匹配释放
   - `start()` 现在返回 `Bool`，实际调用 `FSEventStreamStart` 并按返回值决定；失败时释放 stream、解除 selfRef 并返回 `false`，`isRunning` 与实际状态一致
4. `PollingWatcher` 以 `DispatchSourceTimer` 按 `interval`（CLI `--poll-seconds`，默认 1.0s）轮询：
   - 每 tick 用 `FileManager.enumerator` 递归遍历 canonical root，读 `mtime` + `size`，混合成 64-bit stamp
   - 与上次 snapshot 求差集：新增 / 修改 / 消失 路径都 enqueue 给同一个 EventQueue
   - 仅依赖普通文件元数据 syscall，不依赖 `com.apple.FSEvents.client` mach 服务；在 `codex exec` workspace-write 沙箱下依然能工作
   - CLI `--no-poll` 可关闭（仅在确认 FSEvents 可用的环境下使用）
5. 回调线程取到 `[String]` 后全部 `enqueue` 到 `EventQueue`
6. `EventQueue` 串行化处理：
   - 每次 `enqueue` 把路径加入 `pending: Set<String>`，重置 `DispatchSourceTimer`，`debounce` 默认 0.2s（可由 CLI `--debounce-ms` 覆盖）
   - 定时器触发后一次性把 `pending` 作为一个批次交给 `onBatch`
   - `flushNow()` / `stop()` 立即排空便于测试 / 优雅退出
   - FSEvents + polling 重复投递同一路径会被 Set 天然去重，不会造成多次 rescan
7. `onBatch` 调 `Indexer.rescanPaths(batch)`：
   - `coalescePrefixes(_:)` 去掉被同批目录前缀吞掉的子路径，避免重复工作（"/root" swallow "/root/a.txt"，但 "/a/foo" 不会吞 "/a/foobar"）
   - 每条路径 `realpath` 规范化，再 `FileManager.fileExists(atPath:isDirectory:)` 判状态：
     * 不存在 → `Database.deleteFiles(atOrUnderPath:)`（`WHERE path=? OR path LIKE '<p>/%'`）清理自身及所有后代，用 `sqlite3_changes()` 返回实际删除数
     * 目录存在 → 走目录级 fallback：拿 `Database.pathsAtOrUnder(_:)` 取 DB 已知集合，`FileManager.enumerator` 遍历磁盘并分批 upsert（复用 `Database.insertFiles` 的事务 + grams 重建），最后删掉 `known - seen` 的遗留行；`RescanStats.fallbackDirs += 1`
     * 普通文件 → `makeRow` 后单行 upsert
   - 返回 `RescanStats(processed, upserted, deleted, fallbackDirs)`，CLI 每批打印一行，便于肉眼跟踪
8. `SwiftSeekIndex --watch-seconds N`：首次索引完成后起 `RunLoop.current.run(until:)` 循环，N 秒到期或 SIGINT 命中则 `watcher.stop()` + `pollingWatcher?.stop()` + `queue.stop()`；`stop()` 会先排空尚未 emit 的 batch，再解除 FSEvents / 取消 polling timer

## 受限沙箱下的 polling fallback（P3 round 2）
Codex 独立验收运行在 macOS `sandbox-exec` workspace-write 配置里，对 `com.apple.FSEvents.client` mach 服务存在实际闸门：`FSEventStreamStart` 有时会直接返回 `false`，即使返回 `true` 也可能永远不投递事件。为此 round 2 引入 `PollingWatcher` 作为 **真实** 备选 backend（不是 mock，确实读文件系统 metadata），与 `IncrementalWatcher` 并列接入同一个 `EventQueue`：
- 通常环境：FSEvents 次秒级抢先，polling tick 命中时 EventQueue Set 已经去重
- 受限沙箱：FSEvents 静默失效，polling tick 在 `interval` 之内抓到变更，送进同一条 `rescanPaths` 管线
- 两者都失败：说明 `FileManager.enumerator` 也被沙箱断掉，属于真正的环境故障，CLI 会显式打印 `fsevents=false polling=false`，不再伪装成功

## 不在 P3 范围
- 全局热键 + 搜索窗口（P4）
- 设置项真正连到 `roots` / `excludes` / 重建索引（P5）
- 打包 / 签名 / README 级别以外的发布 docs（P6）
- 事件级别的 flags 细分（当前一律 "rescan this path"，不额外解析 `kFSEventStreamEventFlagItemCreated` 等）
- 跨分卷 / 网络盘 / iCloud 的一致性保证

## P4 搜索窗口 + 全局热键 + 键盘流
P4 在 `SwiftSeekCore` 不引入 AppKit 的前提下给 GUI 搭了一条最小可用搜索链路：

1. `GlobalHotkey`（`App/GlobalHotkey.swift`）— Carbon `RegisterEventHotKey`
   - 默认 `keyCode=49`（`kVK_Space`）+ `modifiers=optionKey` → ⌥Space
   - `InstallEventHandler(GetEventDispatcherTarget(), ...)` 监听 `kEventClassKeyboard/kEventHotKeyPressed`；context 用 `Unmanaged.passUnretained(self).toOpaque()`
   - 命中时从 `EventHotKeyID` 匹配本实例的 `signature='SSeK' id='SSK1'`，再 `DispatchQueue.main.async` 回调业务闭包
   - 选用 Carbon 而非 `NSEvent.addGlobalMonitorForEvents`：后者需要用户手动在"辅助功能"白名单里勾选 SwiftSeek，与 v1 "启动即用" 目标冲突；`RegisterEventHotKey` 自 10.3 就不需要任何额外权限
   - `register(...)` 幂等；`deinit` / `unregister()` 配对 `UnregisterEventHotKey` + `RemoveEventHandler`
2. `SearchWindowController`（`UI/SearchWindowController.swift`）
   - `NSPanel`，680×420，`styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]`
   - `level = .floating`，titlebar 透明隐藏，`isMovableByWindowBackground = true`
   - `windowDidResignKey` 自动 `orderOut`（与 Spotlight / Alfred 一致，避免用户需要显式点关）
   - `show()` 把窗口移到主屏中心偏上，`makeKeyAndOrderFront` 后把焦点交给输入框
3. `SearchViewController`（`UI/SearchViewController.swift`）
   - `NSTextField`（不是 `NSSearchField`，避免其额外的 cancel 按钮/历史菜单）作为输入框，`delegate = self`
   - `controlTextDidChange` → `DispatchSourceTimer` 延迟 80ms `runQuery`；新输入到来先 `cancel()` 旧 timer
   - `runQuery` 直调 `SearchEngine(database: database).search(query)`，**不绕 SQLite**，结果存 `[SearchResult]` 再 `tableView.reloadData`
   - `NSTableView` 单列、`rowSizeStyle=.medium`、`headerView=nil`；单元格是 `NSStackView { icon, text }`，`text` 用 `NSAttributedString` 把 `📁/📄 name` 与次级路径做字重/颜色区分；图标来自 `NSWorkspace.shared.icon(forFile:)`
   - `doubleAction` = `onRowDoubleClick(_:)` → `openSelected`
4. 键盘路由：`control(_:textView:doCommandBy:)` 拦截 4 个 selector
   - `moveDown(_:)` / `moveUp(_:)` → `KeyboardSelection.moveDown() / moveUp()` + `reflectSelection()` 将索引同步给 `NSTableView.selectRowIndexes`
   - `insertNewline(_:)` → `openSelected()` → `ResultActionRunner.perform(.open, ...)` 后 `orderOut`
   - `cancelOperation(_:)`（ESC）→ `orderOut`
   - ⌘⏎ / ⌘⇧C 由按钮的 `keyEquivalentModifierMask` 接管，不在上面的 selector 里
5. `KeyboardSelection`（`Core/KeyboardSelection.swift`，纯逻辑）
   - `resultCount` 变化时 clamp `currentIndex`；空集固定为 -1
   - `wrap`（默认 true）控制 moveDown 在末尾是回 0 还是留在末尾（反向同理）
   - 放在 Core 是为了让 `SwiftSeekSmokeTest` 不链接 AppKit 就能跑状态机的 7 条用例
6. `ResultAction` + `ResultActionRunner`
   - `ResultAction` 枚举（`open` / `revealInFinder` / `copyPath`）与 `ResultTarget(path, isDirectory)` 放 Core，便于测试与未来插件
   - `ResultActionRunner`（AppKit 侧）是唯一真正执行 `NSWorkspace.shared.open` / `activateFileViewerSelecting([url])` / `NSPasteboard.general.setString(...)` 的地方
7. `AppDelegate`
   - 启动成功后 `installSearchWindow()` + `installGlobalHotkey()`
   - hotkey 注册失败不 panic，只打日志 `SwiftSeek: global hotkey registration failed — fallback to menu item 搜索…`；菜单里的 "搜索…" 同样带 ⌥Space keyEquivalent，作为冲突兜底

## 不在 P4 范围
- 设置页真正连到 `roots` / `excludes` / 隐藏文件开关闭环 / 重建索引按钮（P5）
- 日志 / 诊断信息页、错误恢复提示（P5/P6）
- 打包 / 签名 / 自动启动（P6）
- 搜索历史、收藏、预览窗（v1 外）

## P5 设置真实闭环（roots / excludes / 隐藏文件 / 重建 / 诊断）

P5 把 `SettingsWindowController` 的四个占位 pane 换成真正连 `Database` 的控件。核心新组件：

1. **Schema v3**（`SwiftSeekCore/Schema.swift`）
   - `target:3` migration 只新增一张 `settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)`
   - 对已有 P1/P2/P4 数据库是纯追加，不动既有表
   - `Schema.currentVersion = 3`；`Database.migrate()` 的现有循环自动兼容

2. **`SettingsTypes.swift`**（新文件，Core 层）
   - `RootRow` / `ExcludeRow` 值类型（`Equatable` + `Sendable`）
   - `SettingsKey` 枚举常量（`hiddenFilesEnabled` / `lastRebuildAt` / `lastRebuildResult` / `lastRebuildStats`）— 避免字符串 key 在 UI 层到处散落
   - `Database.getHiddenFilesEnabled() / setHiddenFilesEnabled(_:)` extension — 统一 `"1"/"0"` 的编解码
   - `ExcludeFilter.isExcluded(_:patterns:)` — 共享给 `Indexer` / `PollingWatcher` 的静态谓词，保证一条路径在首次索引 / 增量 / 重建三个入口表现一致
   - `HiddenPath.isHidden(_:)` — "路径任意组件以 `.` 开头" 的单一定义

3. **Database API（P5 新增）**
   - roots 管理：`listRoots / setRootEnabled / removeRoot`（`removeRoot` 在事务中先 `deleteFiles(atOrUnderPath:)` 级联清行，再 `DELETE FROM roots`）
   - excludes 管理：`listExcludes / addExclude / removeExclude`，`deleteFilesMatchingExclude` 用于"新增 exclude 时立即清理已索引子树"场景
   - 设置 KV：`getSetting / setSetting`（`INSERT ... ON CONFLICT DO UPDATE`）

4. **`Indexer.Options`**（扩展）
   - 新字段：`excludes: [String]` / `includeHiddenFiles: Bool`
   - `indexRoot` 遍历时先查 `ExcludeFilter` 再查 `HiddenPath`，命中任一 → `skipDescendants()` + `skipped += 1`，既不进数据库也不下探子树，保持 O(visited) 代价
   - `rescanPaths` 同样接受 `excludes` / `includeHiddenFiles` 两个参数，并在入口 + 目录级 fallback 都走过滤

5. **`PollingWatcher.Options`**（扩展）
   - 同样新增 `excludes` / `includeHiddenFiles`；`currentSnapshot()` tick 跳过被排除或（hidden=off 时）隐藏的子树，不让它们进入 `{path -> stamp}` 映射，从源头阻断事件产生
   - FSEvents 本身无法在 mach 层过滤，但由于所有事件最终都经 `Indexer.rescanPaths(...)` 写库，而 `rescanPaths` 已被扩展支持同样的过滤，最终效果一致

6. **`RebuildCoordinator`**（新文件，Core 层）
   - 后台 `DispatchQueue`（qos=.utility），`stateLock: NSLock` 串行化状态切换
   - `state: idle | rebuilding(startedAt, processedRoots, totalRoots)`
   - `rebuild(onProgress:onFinish:)` 返回 `Bool` — 已在跑时返回 `false`，UI 应显式把它当"已在重建，忽略本次"而不是 silent fail
   - 真实走 `Indexer.indexRoot(..., options: .init(excludes: ..., includeHiddenFiles: ..., clearBeforeIndex: true))` 遍历每个 enabled root，过程中 DB 锁天然避免并发 watcher 与 rebuild 的 UPSERT 踩脚
   - 完成（成功或失败）都调 `stampResult` 往 `settings` 表写入 `last_rebuild_at / last_rebuild_result / last_rebuild_stats`，让 Diagnostics / Maintenance tab 不需要 NotificationCenter 就能显示最近结果

7. **UI（`Sources/SwiftSeek/UI/SettingsWindowController.swift`）**
   - 所有 pane 都是 `NSViewController`，持有 `database`（和 coordinator），在 `viewWillAppear` 里从 DB 刷新；切换回某个 tab 时总是展示最新状态，避免"设置值已改但 UI 显示旧值"的漂移
   - **GeneralPane**：单个 `NSButton(checkbox)`，`action` 立即 `setHiddenFilesEnabled`；附一行 `secondaryLabelColor` 说明"切换后请去维护重建"（切换不会自动触发重建，避免用户无意按 toggle 就产生长任务）
   - **IndexingPane**：上下两张 `NSTableView`
     * 上：roots，每行 `✅/⏸ <path>`；按钮 `新增目录…`（`NSOpenPanel`，`canChooseDirectories=true`）/ `移除所选`（带 `NSAlert` 确认）/ `启用/停用所选`
     * 下：excludes，每行 `🚫 <path>`；按钮 `新增排除目录…`（同 `NSOpenPanel`；新增后 eager `deleteFilesMatchingExclude` 立即清理已索引子树）/ `移除所选`
   - **MaintenancePane**：`重建索引` 按钮 + `NSProgressIndicator`（indeterminate bar）+ 两行状态（最近时间/结果 + 最近摘要）；`onRebuild` 用 `rebuildCoordinator.rebuild(onProgress:onFinish:)` 异步触发，回调都在后台队列，统一 `DispatchQueue.main.async` 回 UI
   - **AboutPane**：`NSFont.monospacedSystemFont` 的诊断面板 — `数据库路径 / schema / roots 总数 启用数 / excludes 数 / files 行数 / 隐藏开关 / 上次重建*`；`刷新诊断` 按钮强制重新拉 DB

8. **`AppDelegate`**
   - `applicationDidFinishLaunching` 在 DB 打开 + migrate 之后立即构造 `RebuildCoordinator(database: db)` 并缓存在属性里
   - `showSettings(_:)` 首次调用时按需注入 `SettingsWindowController(database:, rebuildCoordinator:)`

## 不在 P5 范围
- 打包、签名、发布（P6）
- 全文内容搜索 / OCR / AI 语义搜索
- 设置页响应式 UI 重写
- 自动启动项 / Launch Agent 集成
- 复杂 exclude 规则（glob / regex）— 本阶段固定"目录级前缀匹配"
- 自动重建触发器（后续可在 `RebuildCoordinator` 顶上加，P5 仅手动触发）

---

## everything-productization 收口（K1-K6）

> 这一段是 K1-K6 落地后的当前状态参考，不重写历史 P1-P5 / E1-J6 段。完整最新状态以 `docs/stage_status.md` + `docs/install.md` + `docs/release_checklist.md` 为准。

### K1 — Build identity
- `Sources/SwiftSeekCore/BuildInfo.swift`：纯函数读 `Bundle.main.infoDictionary` 取 `CFBundleShortVersionString` / `GitCommit` / `BuildDate`，dev 路径有 fallback。
- `AppDelegate.applicationDidFinishLaunching` 启动头三行 NSLog：`summary` / `bundle=` / `binary=`。
- `AboutPane` 顶部 summary 与诊断块同源。
- 设置窗口生命周期 release gate 写入 `docs/manual_test.md` §33s，J1（hide-only close）/ J6（KVO `selectedTabViewItemIndex`）作为长期回归门禁保留。

### K2 — 可重复 .app 打包
- `scripts/package-app.sh`：`swift build -c release` → 重建 `dist/SwiftSeek.app/Contents/{MacOS,Resources}` → 注入 `Info.plist`（含自动写入 `GitCommit` / `BuildDate`）→ 用 `scripts/make-icon.swift --icns` 直接组装 `.icns`（不依赖 `iconutil`）→ ad-hoc `codesign` → 自检（`plutil -lint` / `codesign -dv` / 文件结构 / `.icns` magic）。
- `scripts/make-icon.swift`：`NSBitmapImageRep(pixelsWide:pixelsHigh:samplesPerPixel:4...)` 显式像素尺寸（避开 `NSImage.lockFocus` 的 display-scale 漂移）；`--icns` 模式直接组装 ic04-ic14 OSType 条目的二进制。
- `scripts/build.sh` 仍专注 `.build/release/<bin>` 裸二进制；`.app` 路径走 `package-app.sh`。

### K3 — Diagnostics 单一来源
- `Sources/SwiftSeekCore/Diagnostics.swift`：纯函数 `Diagnostics.snapshot(database:launchAtLoginIntent:launchAtLoginSystemStatus:)`，AppKit-free，覆盖 build identity / DB 路径与 schema / main+wal+shm 大小 / 关键表行数 / 索引模式 / 隐藏开关 / usage history 开关 / query history 开关 / roots / excludes / Launch at Login 双面状态 / last rebuild / 错误聚合。
- `AboutPane.buildDiagnostics()` 委托给 `Diagnostics.snapshot`；"复制诊断信息" 按钮一键到 `NSPasteboard.general`。
- SmokeTest K3 覆盖字段与设置翻转。

### K4 — 安装 / 升级 / 回滚文档
- `docs/install.md` 单一安装入口：安装 / 升级 / 回滚 / 卸载 / 首次打开 / Gatekeeper / Launch at Login 边界 / 多实例 / stale bundle / schema forward-only（v1→v7 表对照表）。
- README 快速上手指向 install.md。
- `docs/manual_test.md` §33v 的 install / upgrade / rollback / Launch at Login dry-run。

### K5 — 权限引导 + Full Disk Access + recheck
- `Sources/SwiftSeekCore/SettingsTypes.swift`：`RootHealth` 拆出 `.volumeOffline`（路径前缀 `/Volumes/<X>` 但 `<X>` 卷未挂载）、`.offline`（路径不存在）、`.unavailable`（权限被拒）；新增 `RootHealthReport { health, detail }` 与 `Database.computeRootHealthReport(for:currentlyIndexingPath:)` 返回结构化判定。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `IndexingPane`：rootsTable cell 改用 `RootHealthReport`，`text.toolTip = report.detail`；rootsBar 新增 "重新检查权限"（`reload()` 不动 DB）+ "打开完全磁盘访问设置"（`NSWorkspace.open` `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`，失败回退通用隐私 + NSAlert）。
- `Diagnostics.snapshot` 增加 `roots 健康（K5）：` 段（最多 20 行）。
- `docs/install.md` 新增"权限 / Full Disk Access / Root 覆盖（K5）"，`docs/manual_test.md` 新增 §33w 4 状态矩阵 + recheck + FDA fallback。

### K6 — Release QA 收口
- `docs/release_checklist.md`：单页 15 步 release gate（fresh build / smoke / package / bundle 元数据 / 启动 build identity / 设置生命周期 10×/ 热键 / add root → search → open / 诊断复制 / K5 root health / Launch at Login / icon / 安装升级回滚 dry-run / release notes / 文档一致性）。
- `docs/release_notes_template.md`：诚实的发布说明模板，"已知边界"段不可删除（ad-hoc / 无 Developer ID / 无 notarization / 无 DMG / 无 auto updater / FDA / 外接盘）。
- 文档同步：本段 + README"当前限制" + `docs/known_issues.md` + `docs/manual_test.md` + `docs/stage_status.md` 与 K1-K5 实现一致。

### 当前轨道明确不做
- Apple Developer ID 签名 / notarization
- DMG / Sparkle / auto updater
- App Store packaging / sandbox 适配
- 全文内容 / OCR / AI 语义搜索
- 网络盘 / 云盘实时一致性承诺
- macOS 全局启动次数读取 / 系统隐私数据扫描
- private API 调用

---

## everything-filemanager-integration 收口（M1-M4）

> 这一段是 M1-M4 落地后的当前状态参考。最新状态以 `docs/stage_status.md` + `docs/install.md` + `docs/release_checklist.md` 为准。

### M1 — Reveal Target 数据模型与设置 UI
- `Sources/SwiftSeekCore/SettingsTypes.swift`：`RevealTargetType { .finder, .customApp }`、`ExternalRevealOpenMode { .item, .parentFolder }`、`RevealTarget` 结构体（`defaultTarget = (.finder, "", .parentFolder)`）；`SettingsKey.revealTargetType / revealCustomAppPath / revealExternalOpenMode`；`Database.getRevealTarget() / setRevealTarget(_:)` extension（每字段独立 fallback）。
- `Sources/SwiftSeek/UI/SettingsWindowController.swift` `GeneralPane`：显示位置 popup（Finder / 自定义 App…）+ "选择 App…" 按钮（`NSOpenPanel` 限定 `.application` content type）+ 当前 app 名称 + 路径 summary（含 QSpace 文件名启发式识别）+ 打开目标 segmented（父目录 / 文件本身）+ 多行 note；popup / segmented / NSOpenPanel 三条保存路径失败都弹 NSAlert。Pane 高度 580。

### M2 — ResultActionRunner 接入 Finder / 自定义 App
- `Sources/SwiftSeekCore/RevealResolver.swift`（纯函数 / AppKit-free）：
  - `Strategy { .finder(targetURL) / .customApp(appURL, targetURL) / .fallbackToFinder(targetURL, reason) }`
  - `CustomAppValidation { .ok(URL) / .empty / .notFound(path) / .notAnApp(path) }`
  - `resolveTargetURL(target:openMode:)`（`.item` 返回原 URL；`.parentFolder` 文件返回父目录、目录返回自己保持不掉级）
  - `validateCustomAppPath(_:fileExists:)`（trim / 不存在 / 非 dir / 缺 `.app` 后缀都进对应失败 case）
  - `decideStrategy(target:revealTarget:fileExists:)`
  - `finderFallbackURL(target:)`（M2 round-2 不变量：fallback 到 Finder 永远选中**原始**目标 URL，不是外部 app 的 resolved URL）
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`：`.revealInFinder` 现支持可选 `database` + `onReveal` 回调；保留旧 2 参数入口（database=nil → Finder）。三分支路由 → Finder `activateFileViewerSelecting` / customApp `NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration:)`（`config.activates = true`）/ fallbackToFinder。完成 handler error → NSLog + `finderFallbackURL` Finder fallback + `onReveal(.fallback)`。
- reveal 路径不调 `recordOpen`，Run Count 仅由 `.open` 成功路径增加。

### M3 — 动态文案、fallback、诊断与手测
- `RevealResolver` 新增 3 helper：
  - `displayName(for:)`：Finder → "Finder"；customApp 空 → "自定义 App"；filename lowercased contains "qspace" → "QSpace"；其它 `.app` 去 `.app` 后缀；其它路径 → 文件名原样
  - `actionTitle(for:)` = `"在 \(displayName) 中显示"`
  - `fallbackReason(_:for:)` = `"无法用 \(displayName) 显示，已回退到 Finder：\(underlying)"`
- `Sources/SwiftSeek/UI/SearchViewController.swift`：reveal button + 右键菜单 reveal item 存为属性；`currentRevealTargetSafe()`、`hintTextForReveal(target:)`（短 displayName ≤10 → "在 <name> 中显示"，长 → 中性 "显示位置"）、`refreshRevealLabels()` 同时刷新 button + menu + bottom hint strip。`SearchWindowController.show()` 在 `makeKeyAndOrderFront` 之后调 refresh，确保 Settings 改动隔次生效。`revealSelected` toast 用 `⚠️ \(reason)`，reason 由 `RevealResolver.fallbackReason` 组成。
- `Sources/SwiftSeekCore/Diagnostics.swift` snapshot 新增 `Reveal target（M3）：` 块，含 type / 显示名称 / 按钮文案 / 打开模式 / 自定义 App 路径。
- `docs/manual_test.md` §33ac + `docs/release_checklist.md` §5f 覆盖 GUI 验证矩阵。

### M4 — 最终收口
- `README.md`、`docs/known_issues.md`、`docs/architecture.md`（本段）、`docs/manual_test.md`、`docs/release_checklist.md`、`docs/stage_status.md` 与 M1-M3 真实代码对齐。
- release_checklist header / smoke baseline / 验证矩阵升到 K6 + L1-L4 + M1-M4。
- 不引入新搜索 / OCR / AI / 跨平台能力；不重写 ResultActionRunner 公共契约；`.revealInFinder` case 名仍保留（rename 是更高代价的 ABI 变更，留给将来 fresh track 决定）。

### 当前轨道（filemanager-integration）明确不做
- QSpace 私有 API / 硬编码 QSpace bundle id / 假设 QSpace URL scheme
- AppleScript 驱动外部 app
- 改变 macOS 系统默认文件管理器
- 让 reveal 计入 Run Count
- 跨用户多实例 / 跨 bundle id 自定义构建间共享设置
- 承诺所有第三方文件管理器都能"选中具体文件"
