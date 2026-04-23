# SwiftSeek 阶段状态

## 当前阶段
P6（稳定性与交付：日志 / 错误处理 / 文档收口 / 本地交付路径）

## 已通过阶段
- P0（2026-04-23 Codex PASS，经一轮 REJECT 后复验通过）
- P1（2026-04-23 Codex PASS，经一轮 REJECT 后复验通过）
- P2（2026-04-23 Codex PASS，经一轮 REJECT 后复验通过）
- P3（2026-04-23 Codex PASS，round 2 修复 FSEvents 受限沙箱问题后复验通过）
- P4（2026-04-23 Codex PASS，round 3 修复沙箱 env 前缀文档漂移后复验通过；fresh session 019db8b5）
- P5（2026-04-23 Codex PASS，round 2 修复 disabled-root 搜索泄漏后复验通过；fresh session 019db8d0）

## 当前阶段目标（P6）
- 把 SwiftSeek v1 收到"可交付、可复验、不是只有作者自己会用"的状态
- 关键路径异常都有可观察输出（日志 / UI 提示），不再大量 silent fail
- README / architecture / manual_test / known_issues 与真实实现一致
- 提供一条真实可执行的本地交付路径
- P0 ~ P5 无回归

## 当前阶段禁止事项
- 新增功能（全文 / OCR / 语义 / 跨平台 / 云盘一致性）
- 大型日志框架 / 安装器 / 自动更新器
- 主架构改造
- `.app` bundle / 签名 / 公证（v1 外）

## 当前阶段完成判定标准

> 在 `codex exec` workspace-write 沙箱下，clang module cache 默认路径 `~/.cache` 不可写，需在命令前加 `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache`。普通开发环境不需要。

1. `swift build --disable-sandbox` 成功
2. `swift run --disable-sandbox SwiftSeekSmokeTest` 51/51 PASS
3. `swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-p6.sqlite3` 输出 `database ready ... schema=3` + `startup check PASS`
4. `./scripts/build.sh --sandbox` 一条龙跑通 release build + smoke + startup，打印 `.build/release/` 下五个可执行
5. `.build/release/SwiftSeekStartup --db /tmp/...` 独立运行成功（证明 release 二进制可交付）
6. 关键 silent-fail 已加日志：
   - `SettingsWindowController.IndexingPane.reload` / `MaintenancePane.reflectLastResult` / `AboutPane.buildDiagnostics` / `GeneralPane.viewWillAppear` 所有 DB 读失败都 `NSLog` 并在 UI 显示错误信息
   - `RebuildCoordinator.stampResult` 失败时 `NSLog`
   - `SearchEngine.search` 的 `listRoots` 失败走 `NSLog` 兼容 legacy 回退
7. 文档：`README.md` 有"快速上手"段；`docs/known_issues.md` 登记所有已知限制；`docs/manual_test.md` 含 P6 交付流程；`docs/architecture.md` 保持 P5 快照有效
8. P0 ~ P5 无回归
4. 热键呼出的窗口真正调用当前 `SearchEngine.search(...)` 拿到 `[SearchResult]`，不是 mock 数据
5. 键盘流覆盖：↑↓ 移动、⏎ 打开、⌘⏎ Reveal、⌘⇧C 复制路径、ESC 隐藏；resignKey 自动隐藏
6. 文档同步：`docs/architecture.md`、`docs/manual_test.md`、README 写明 P4 入口与交互
7. 没有越界做 P5 ~ P6

## 上一轮 Codex verdict
P5 PASS（round 2，session 019db8d0）。P6 尚未提交 Codex 验收。

## 上一轮 Codex blockers 是否已关闭
P5 全部闭环。P6 正在开发（下方 P6 自检段落）。

## P6 自检结果（Claude 侧，round 1，待 Codex 验收）
- `swift build --disable-sandbox` 成功（0 warning / 0 error）
- `swift run --disable-sandbox SwiftSeekSmokeTest` **51**/51 PASS（P0~P5 全部保留，不回退）
- `swift run --disable-sandbox SwiftSeekStartup --db /tmp/...` 输出 `database ready ... schema=3` + `startup check PASS`
- `./scripts/build.sh --sandbox` 一条龙 release build + smoke + startup + 列产物目录，退出码 0
- `.build/release/SwiftSeekStartup --db /tmp/...` 独立运行成功（Mach-O arm64 native binary，产物 `.build/release/SwiftSeek` / `SwiftSeekIndex` / `SwiftSeekSearch` / `SwiftSeekStartup` / `SwiftSeekSmokeTest` 五个 executable）
- silent-fail 审计：全部 `try?` + 隐式丢错路径已加 `NSLog`，或用 `do-try-catch` 给 UI 显示错误消息（详见完成判定标准 6.）
- 新增文件：
  - `scripts/build.sh`（可执行的本地交付脚本，P6）
  - `docs/known_issues.md`（P6 环境约束 / v1 范围外 / 运行时行为说明 / 已知小问题 / v2+ 路线登记）
- `README.md` 重写"快速上手"段落为 `./scripts/build.sh` 一条龙；`v1 目标` 改为 `v1 能力`；明确不做项指向 `known_issues.md`
- `docs/manual_test.md` 追加 P6 段：29 交付脚本 / 30 release 二进制独立运行 / 31 silent-fail 审计 / 32 日志可观察 / 33 已知限制对照
- 对齐 CLAUDE.md 纪律：未越界做 v2 功能；未引入大型日志框架 / 安装器 / 自动更新器

## P5 round 1 Codex REJECT blockers 关闭（2026-04-23，round 2）
1. **disabled root 搜索仍命中**（Codex 黑盒复现：`UPDATE roots SET enabled=0` 后 `SwiftSeekSearch alpha` 仍返回 `[800] /..../alpha.txt`）→ `SearchEngine.search` 在候选检索后对 rows 过滤，只保留 path 在 enabled roots 下的；并新增 `pathUnderAnyRoot(_:roots:)` public helper。禁用后搜索不命中、重新启用立刻恢复（索引数据不删），语义写入 `SettingsWindowController.IndexingPane` 的 status 行。
2. **smoke 漏覆盖该 blocker** → 新增 3 条 P5-round2 用例：
   - disabled root 下 `SearchEngine.search("alpha")` 不返回，re-enable 后恢复
   - disabled root 下路径命中（score 200）也被过滤
   - `pathUnderAnyRoot` helper 的 exact / descendant / sibling-shared-prefix / empty-roots 分别行为
3. **语义文档**：`IndexingPane` status 行写明"停用保留索引数据但搜索不返回；移除会级联清理"。

## P5 自检结果（Claude 侧，round 1，待 Codex 验收）
- `swift build --disable-sandbox` 成功（0 warning / 0 error）
- `swift run --disable-sandbox SwiftSeekSmokeTest` **51**/51 PASS
  - 新增 10 条 P5 用例：
    1. schema v3 migration + `settings` 表创建
    2. roots 的 add / list / enable toggle / remove 持久化，remove 级联清 files
    3. excludes：首次索引跳过被排除目录（skipped 记录）
    4. excludes：已索引路径后加 exclude → `deleteFilesMatchingExclude` 立即清理 >= 2 行
    5. 隐藏文件开关 off → .dot 路径被跳过；on → 可搜到
    6. `getHiddenFilesEnabled` / `setHiddenFilesEnabled` round-trip
    7. `RebuildCoordinator` 多 root 走完 + `last_rebuild_*` 三项落库
    8. `RebuildCoordinator` 并发保护：第二次调用返回 false
    9. `ExcludeFilter` 对 exact / descendant / sibling-shared-prefix 的分别行为
    10. `HiddenPath` 只识别路径组件前缀 `.`，不误伤中间点号
- `swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-p5-check.sqlite3` → `database ready ... schema=3` + `startup check PASS`
- 手工 GUI 抽检：`swift run --disable-sandbox SwiftSeek` 后台 4s 启动不崩溃，`schema=3` 落盘
- 对齐 CLAUDE.md 纪律：未越界 P6；设置项全部走 `Database` 持久化；不引入新配置体系

## P4 round 1 Codex REJECT blockers 关闭（2026-04-23）
1. **GUI 启动无 `database ready` 日志（Codex 沙箱无 WindowServer）** → 新增 `SwiftSeekStartup` 非 GUI CLI：不依赖 AppKit/WindowServer，直接调 `AppPaths.ensureSupportDirectory + Database.open + migrate`，打印 `database ready at <path> schema=2`；支持 `--db /tmp/...` 覆盖（解决沙箱 `~/Library` 不可写问题）；Codex 可直接运行 `swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-check.sqlite3` 证明启动路径
2. **Smoke 未覆盖 GUI 启动路径** → 新增 2 条 P4-startup smoke：
   - `P4 startup: AppPaths + Database.open + migrate reaches schema=2` — 覆盖 AppDelegate Core 路径
   - `P4 SearchEngine round-trip: index file then search from same DB` — 证明 `SearchEngine(database:)` init + search（SearchViewController 所依赖的路径）

## P4 自检结果（Claude 侧，round 3，待 Codex 验收）
- `swift build --disable-sandbox` 成功（0 warning / 0 error）
- `swift run --disable-sandbox SwiftSeekSmokeTest` **38**/38 PASS
- `swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-check.sqlite3` → `database ready schema=2` + `startup check PASS`
- Codex round 2（fresh session `019db8a7`）用 `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache` 验证后三条命令均通过，源码确认 P4 连线全部正确
- Round 2 REJECT 原因：文档未写 sandbox env 前缀、smoke count 未更新 36→38、状态文案过时
- Round 3 fixes：README / manual_test / stage_status 全部更新 env 前缀 + 38 条 + 状态文案：6 P0 + 5 P1 + 8 P2 + 10 P3 + 7 P4
  - P4 用例：
    1. 空结果集时 moveDown / moveUp 保持 currentIndex = -1
    2. `setResultCount(3)` 自动 snap 到 0；两次 moveDown 到 2
    3. `wrap=true`（默认）在末尾向下 wrap 回 0，开头向上 wrap 到末尾
    4. `wrap=false` 两端 clamp
    5. `setResultCount` 从 10 → 3 把 stale index 8 重夹到 2；从 3 → 0 回到 -1
    6. `moveToFirst` / `moveToLast` 跳边
    7. `ResultTarget` 相等性对 path + isDirectory 敏感
- 启动冒烟：`swift run --disable-sandbox SwiftSeek` 后 4s 内日志显示 `SwiftSeek: database ready at .../SwiftSeek/index.sqlite3 schema=2`，未崩溃；hotkey 注册成功（失败才会日志）
- 文件清单：
  - `Sources/SwiftSeekCore/KeyboardSelection.swift` — 纯 Swift 状态机，不依赖 AppKit
  - `Sources/SwiftSeekCore/ResultAction.swift` — 共享 `ResultAction` 枚举 + `ResultTarget` 结构体
  - `Sources/SwiftSeek/App/GlobalHotkey.swift` — Carbon `RegisterEventHotKey` 封装；默认 ⌥Space（`kVK_Space=49` + `optionKey`）；不依赖辅助功能权限
  - `Sources/SwiftSeek/UI/SearchWindowController.swift` — `NSPanel` 浮动窗口（680×420，`.floating`，`.nonactivatingPanel`）；`windowDidResignKey` 自动隐藏
  - `Sources/SwiftSeek/UI/SearchViewController.swift` — 输入框 + `NSTableView`，80ms `DispatchSourceTimer` debounce；键盘路由经 `control(_:textView:doCommandBy:)` → `moveUp/moveDown/insertNewline/cancelOperation`；状态栏显示 `N 条 · Xms`
  - `Sources/SwiftSeek/UI/ResultActionRunner.swift` — AppKit 侧唯一执行点，`NSWorkspace.shared.open` / `activateFileViewerSelecting` / `NSPasteboard.general`
  - `Sources/SwiftSeek/App/AppDelegate.swift` — 启动时打开 DB → 构造 `SearchWindowController(database:)` → 注册 `GlobalHotkey`，按下切换窗口
  - `Sources/SwiftSeek/App/MainMenu.swift` — 新增 "搜索…" 菜单项，keyEquivalent=⌥Space，兜底入口
- 对齐 CLAUDE.md 纪律：未越界做 P5 ~ P6；未引入设置页真实连线 / 数据库新字段 / 全文搜索等

## P3 自检结果（Claude 侧，round 2，待 Codex 复验）
- `swift build` 成功（0 warning / 0 error）
- `swift run SwiftSeekSmokeTest` 29/29 PASS：6 P0 + 5 P1 + 8 P2 + 10 P3
  - P3 round 2 新增用例：
    9. `PollingWatcher alone detects create/modify/delete without FSEvents`：只挂 polling → 新增 / 删除各触发一次 batch，SearchEngine 视图同步
    10. `IncrementalWatcher.start returns false for non-existent root`：验证 `start()` 真实返回值语义 + `stop()` 空安全
  - 既有 `IncrementalWatcher + EventQueue detect real FS events end-to-end` 改为 FSEvents + PollingWatcher 并列启动，whichever-fires-first 满足断言；timeout 从 5s 放宽到 8s 仅作抗干扰冗余
- 手工 `SwiftSeekIndex --watch-seconds 6 --poll-seconds 0.5` 实地跑：
  - 启动日志：`[watch] FSEvents start=true` + `[watch] polling started interval=0.5s` + `[watch] started root=... fsevents=true polling=true`
  - 新增 `gamma.txt` → `batch size=1` → `[rescan] processed=1 upserted=1 deleted=0 fallbackDirs=0`
  - `mv alpha.txt alpha-renamed.txt` → `batch size=4`（包含 root / 旧路径 / 新路径 / 其他）→ `upserted=6 deleted=1 fallbackDirs=1`
  - `rm beta.txt` → `batch size=3` 里包含 beta.txt → `deleted=1`
  - 连续 3 次 `echo >> gamma.txt` → 合并为 `batch size=1` 单次 rescan
  - 终态 DB `roots=1 files=5`；`SwiftSeekSearch alpha` 命中 `alpha-renamed.txt`；`beta` 0 结果；`gamma` 命中 `gamma.txt`
- 对齐 Codex round 1 REJECT 原文的三条 REQUIRED_FIXES，均已真实代码化，不是仅文档变动

## 历史：上一轮 P2 Codex verdict
P2 PASS（2026-04-23，经一轮 REJECT 后复验通过）；P2 round 1 的两个 doc-only blocker 此前已修（`docs/manual_test.md:30` schema=2、`docs/architecture.md` P1 取消语义与实现对齐）。

## P3 自检结果（round 1，已被 round 2 迭代覆盖）
- `swift build` 成功（0 warning / 0 error）
- `swift run SwiftSeekSmokeTest` 27/27 PASS：6 P0 + 5 P1 + 8 P2 + 8 P3
  - P3 用例：
    1. `EventQueue` trailing-debounce：4 次 enqueue（含 1 次重复 + 1 次批量）窗口内只 emit 1 个 batch，内容为 3 条去重路径
    2. `Indexer.coalescePrefixes`：保留 `/root`、`/other`、`/other2/deep/nested`，吞掉 `/root/sub/a.txt`、`/root/sub` 与 `/other2/deep/nested/x.txt`；反例 `/a/foo` 不吞 `/a/foobar`
    3. `rescanPaths` 新增单文件：DB upsert 后 `SearchEngine.search` 可命中
    4. `rescanPaths` 删除单文件：`deleted == 1`，search 不再命中
    5. `rescanPaths` 重命名：传入 `{oldPath, newPath}` 集合 → 旧行被删、新行被插入
    6. `rescanPaths` 删除目录：整个子树级联清理，`deleted >= 2`
    7. `rescanPaths` 修改同一路径文件：mtime / size 真实刷新（1.05s 后写入更长内容，断言 mtime 严格增大）
    8. 真实 FSEvents 端到端：`IncrementalWatcher` + `EventQueue` + 临时目录里新增文件，信号量等待 5s 内 batch 到达 → `rescanPaths` 后可 `SearchEngine.search` 命中
- 手工 `SwiftSeekIndex --watch-seconds 30 --debounce-ms 200` 在 `$(mktemp -d -t swiftseek-p3)` 样本（alpha.txt / beta.txt / sub/inner.txt）实地验证：
  - 新增 `gamma.txt` → `[watch] batch size=1` → `[rescan] processed=1 upserted=1 deleted=0 fallbackDirs=0`
  - `mv alpha.txt alpha-renamed.txt` → `batch size=2`（FSEvents 同批给出 old + new 两个路径）→ `upserted=1 deleted=1`
  - `rm beta.txt` → `batch size=1` → `upserted=0 deleted=1`
  - 连续 3 次 `echo >> gamma.txt` → 合并为单个 `batch size=1`（debounce 200ms 真实生效）
  - 终态 `db: roots=1 files=5`（root + sub + sub/inner.txt + gamma.txt + alpha-renamed.txt），`file_grams` 431 行
  - `SwiftSeekSearch alpha` 只命中 `alpha-renamed.txt`；`beta` 0 结果；`gamma` 命中 `gamma.txt`
- 早期一次 smoke `Exit 139` 崩溃：`~/Library/Logs/DiagnosticReports/SwiftSeekSmokeTest-*.ips` 定位到 `watcherCallback` 内 `cfArray as? [String]` 段错误，根因 FSEvents flags 缺 `kFSEventStreamCreateFlagUseCFTypes`；补齐 flag 后 smoke 全绿、真实 watch 稳定
- FSEvents 的 `ObjCBool` / `CFArray` 生命周期：`Unmanaged.passRetained(self).toOpaque()` 给 context.info，`stop()` 时 `FSEventStreamRelease` + 手动 `release()` 匹配，避免 selfRef 泄漏
- 对齐 CLAUDE.md 纪律：未越界做 P4 ~ P6；未动 FTS / 全文搜索 / AI / 云盘一致性相关代码

## P2 自检结果（Claude 侧，待 Codex 复验）
- `swift build` 成功（0 warning / 0 error）
- `swift run SwiftSeekSmokeTest` 19/19 PASS：6 P0 + 5 P1 + 8 P2
  - P2 用例：normalize / 文件名前缀 / 路径命中 / 3-gram 召回 / 排序稳定 / CJK / 含空格文件名 / v1→v2 迁移 + grams 回填
- 手工样本树（alpha.txt / alphabet.txt / docs/alpha-notes.md / beta/alpha report.txt / extras-with-alpha/README.md / 中文文档.md）经 `SwiftSeekSearch` CLI 验证：
  - `alp`：前 4 条为文件名前缀命中（score 800），依次 alpha.txt / alphabet.txt / docs/alpha-notes.md / beta/alpha report.txt；extras-with-alpha 目录（名字含 alp 但非前缀）得 500；extras-with-alpha/README.md 得 200（仅路径命中），位于末尾
  - `docs/alpha`：仅召回 `docs/alpha-notes.md`，score 200
  - `pha`：召回 5 条 score 500（文件名包含）+ 1 条 score 200（路径命中）
  - `中文`：1 条 score 800（短 query fallback 走 LIKE）
  - `alpha report`：gram 路径召回 1 条，score 800
- Schema v2 迁移：`Schema.migrations` 按 target 版本步进。v1 库打开后：
  1. `ALTER TABLE files ADD COLUMN path_lower` + 用 `UPDATE ... SET path_lower = LOWER(path)` 回填
  2. 建 `file_grams` 表（`ON DELETE CASCADE` + `WITHOUT ROWID`）与 `idx_file_grams_gram`
  3. `Database.backfillFileGrams()` 在同一事务内遍历 files，向 `file_grams` 写入 `Gram.indexGrams(nameLower:pathLower:)`
  4. 最后 `PRAGMA user_version = 2` 并 `COMMIT`
- 旧库升级实测：v1 库含 2 条老行，`SwiftSeekSearch "alpha"` 触发 migrate → `user_version=2`，`file_grams` 30 条；查询 "row" 返回 `[800] /old/Row.TXT`，查询 "alpha" 返回 `[800] /archive/docs/Alpha.md`，老数据无需重建即可搜
- grams 真实落库：`sqlite3 <db> "SELECT COUNT(*) FROM file_grams;"` 非空（样本 6 文件 DB 为 959 条），非运行时内存拼接

## P1 自检结果（Claude 侧）
- `swift build` 成功（0 warning / 0 error）
- `swift run SwiftSeekSmokeTest` 11/11 PASS（6 条 P0 用例 + 5 条 P1 用例：样本树全量索引 / 一般取消 / 预先取消不产生任何 ghost 写入 / 在 progress 回调中取消不会 flush 尾批 / 重新索引清理旧行）
- 真实样本目录验证（2026-04-23）：
  - 样本含多级子目录 + 中文目录 + 含空格文件名，共 10 条记录
  - `sqlite3 <db> "SELECT path FROM roots;"` 返回 canonical 根路径（`/private/var/folders/...`）
  - `sqlite3 <db> "SELECT COUNT(*) FROM files;"` = 10
  - `SELECT COUNT(*) FROM files WHERE path = '<root>' OR path LIKE '<root>/%';` = 10（根与所有后代都落在同一前缀下）
- 取消验证（2026-04-23 round 2）：10000 文件样本 + `--cancel-after-ms 30 --batch 100 --progress 100`，触发 `[CANCELLED]` 后 `files=3100`（batch 整倍数，尾批未 flush），退出码 130
- 路径规范化：改用 `realpath(3)`，避免 macOS `/tmp → /private/tmp` 等 firmlink 导致 root 路径与 `FileManager.enumerator` 枚举子项前缀不一致

## Codex round 1 REJECT 闭环（2026-04-23）
- Blocker：`Indexer.swift` 在 `cancel.isCancelled` 命中 break 后仍无条件 flush 残留 batch，导致取消后仍入库
- 修复：`if !cancelled, !batch.isEmpty { try database.insertFiles(batch) ... }`
- 卡住缺陷的测试：新增 `Pre-cancelled indexer flushes no rows` 与 `In-flight cancel never flushes pending partial batch`。预先取消路径断言 `inserted == 0 && files 行数 == 0`；在 progress 回调里同步取消的路径断言 `inserted % batchSize == 0 && DB 行数 == inserted`

## 构建工具说明
- 本机未安装 Xcode.app，仅 CommandLineTools（Swift 6.3.1）。`xcode-select -p` 返回 `/Library/Developer/CommandLineTools`
- `/usr/bin/xcodebuild` 可执行文件存在，但调用时会报 `tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`。因此当前 **P0 不把 `xcodebuild` 作为构建/验收入口**
- 工程以 SwiftPM 组织：`Package.swift`（未安装 Xcode 时也可直接构建；安装 Xcode 后可 `open Package.swift`）
- 主要命令：
  - `swift build` 构建
  - `swift run SwiftSeek` 启动 GUI
  - `swift run SwiftSeekSmokeTest` 跑 P0 冒烟测试
- XCTest 在 CLT 下缺失。`Testing.framework` 存在但其运行时依赖 `lib_TestingInterop.dylib` 的 rpath 在 CLT 环境无法自动解析（需要 Xcode.app），因此 P0 不使用 `swift test`，改用独立可执行 `SwiftSeekSmokeTest` 作为自动化冒烟测试
- 在受限沙箱（例如 `codex exec` 默认 `workspace-write` 模式）下，SwiftPM 内部会再调一次 `sandbox-exec`，可能因嵌套沙箱报 `sandbox-exec: sandbox_apply: Operation not permitted`。此时应在 Codex 调用侧使用 `--sandbox danger-full-access`，或在命令中显式追加 `--disable-sandbox`，例如：
  - `swift build --disable-sandbox`
  - `swift run --disable-sandbox SwiftSeekSmokeTest`
