# SwiftSeek

macOS 原生本地极速文件搜索器（v1 开发中）。

## v1 能力
- Swift + AppKit + SQLite + FSEvents，macOS 13+
- 本地文件 / 文件夹搜索（文件名 / 路径优先，3-gram 倒排）
- 首次全量索引 + FSEvents + 文件系统 polling 双 backend 增量更新
- 全局热键 ⌥Space 呼出浮动搜索窗口（Carbon；不需辅助功能权限）
- 键盘流：↑/↓ 移动 · ⏎ 打开 · ⌘⏎ Reveal · ⌘⇧C 复制路径 · ESC 隐藏
- 设置页真实连线：索引目录（roots）/ 排除目录 / 隐藏文件开关 / 重建索引 / 诊断信息

## v1 明确不做
全文内容搜索、OCR、AI 语义搜索、云盘实时一致性、跨平台、Electron / Web UI 替代原生、APFS 原始解析、Finder 插件、App Store 沙盒适配、代码签名 / 公证。完整已知限制见 [docs/known_issues.md](docs/known_issues.md)。

## 当前进度
`docs/stage_status.md` 为权威来源。当前处于 **P6**（稳定性与交付；P0~P5 已由 Codex PASS）。

## 快速上手（本地交付）

最简一条龙（干净 checkout → release 二进制 → 跑完自检）：
```
./scripts/build.sh
```
受限沙箱（`codex exec` workspace-write）用：
```
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/build.sh --sandbox
```
构建完成后二进制在 `.build/release/` 下：
- `SwiftSeek` — GUI 主程序
- `SwiftSeekIndex <dir>` — 首次 / 增量索引（CLI）
- `SwiftSeekSearch <query>` — CLI 搜索
- `SwiftSeekStartup [--db <path>]` — 非 GUI 启动检查（headless 友好）
- `SwiftSeekSmokeTest` — 51 条冒烟用例

首次运行 Gatekeeper 可能拦截；处理方式见 [docs/known_issues.md#gatekeeper-首次运行拦截](docs/known_issues.md)。

## 构建

环境：macOS 13+，Swift 6.x。

本项目以 **SwiftPM** 组织，原因是开发环境未安装 Xcode.app，仅 CommandLineTools 可用。未来若安装 Xcode，可直接 `open Package.swift` 生成 Xcode 工程。

```
swift build                              # 全量编译
swift run SwiftSeek                      # 启动 GUI（P0 菜单 + 设置 + DB；P4 搜索窗口 + ⌥Space 全局热键）
swift run SwiftSeekSmokeTest             # 冒烟测试（P0+P1+P2+P3+P4+P5，共 51 条用例）
swift run SwiftSeekIndex <path>          # P1：对 <path> 做首次全量索引；P3 增量见 --watch
swift run SwiftSeekSearch <query>        # P2：在已索引库中搜索
```

在受限沙箱（`codex exec` workspace-write）下，clang module cache 默认路径不可写，需额外设置两个环境变量：

```
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift build --disable-sandbox

HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekSmokeTest

# 启动路径验证（无需 WindowServer，适合 headless 验收环境）
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-check.sqlite3
```

普通开发环境直接用 `swift build` / `swift run ...` 即可（不需要 env 前缀）。

P1/P3 `SwiftSeekIndex` 常用开关：
- `--db <path>`：自定义数据库位置（默认 `~/Library/Application Support/SwiftSeek/index.sqlite3`）
- `--batch N` / `--progress N`：批大小 / 进度频次
- `--verbose`：每次进度都打印当前路径
- `--no-clear`：保留之前在该根下的历史行（默认先 `DELETE` 再索引）
- `--cancel-after-ms N`：开发辅助，N 毫秒后自动触发取消
- `--watch`：首次全量索引完成后起 FSEvents + polling 双 backend 监听，按 Ctrl-C 停止
- `--watch-seconds N`：同 `--watch`，N 秒后自动退出（便于脚本化验证）
- `--debounce-ms N`：事件合并窗口，默认 200ms
- `--poll-seconds N`：polling backend 轮询间隔，默认 1.0s
- `--no-poll`：关闭 polling，仅 FSEvents（仅在确认 FSEvents 可用的环境使用）
- 运行期按 Ctrl-C 可立即取消索引 / 停止 watcher

P2 `SwiftSeekSearch` 常用开关：
- `--db <path>`：自定义数据库位置（默认同上）
- `--limit N`：最大返回数，默认 20
- `--show-score`：每行前面加 `[score]`，便于核查排序
- 查询规则：trim + lowercase + 连续空白折叠；`/` 保留（支持路径命中）
- 分数分层：文件名精确命中 1000 > 前缀 800 > 包含 500 > 仅路径 200；同分短路径在前
- 查询长度 < 3 字符时走 `LIKE '%q%'` fallback，否则经由 3-gram 候选召回 + 子串严筛

P3 增量管线：`IncrementalWatcher`（FSEvents：`kFSEventStreamCreateFlagFileEvents | NoDefer | UseCFTypes`，`start()` 检查 `FSEventStreamStart` 真实返回值）+ `PollingWatcher`（备用 backend，`DispatchSourceTimer` 周期性扫描 mtime+size 的差集，不依赖 FSEvents mach 服务，在 `codex exec` 受限沙箱下仍能工作）→ 同一个 `EventQueue`（trailing debounce，Set 天然去重）→ `Indexer.rescanPaths`：前缀合并后对每条路径判 exists/isDir，不存在删（级联清后代）、文件 upsert、目录走 enumerator + `known - seen` 差集清理。

P4 搜索入口：启动后按 **⌥Space** 呼出浮动搜索窗口（Carbon `RegisterEventHotKey`，不需辅助功能权限；菜单 `SwiftSeek → 搜索…` 同样可呼出，兜底 hotkey 冲突）。输入实时查询（80ms debounce），走 `SearchEngine`；键盘：↑/↓ 移动、⏎ 打开、⌘⏎ Reveal in Finder、⌘⇧C 复制路径、ESC 隐藏；点击窗口外任意位置自动隐藏（Spotlight 风格）。

P5 设置页（`SwiftSeek → 设置…` 或 ⌘,）四个 tab 真实连线：
- **常规**：隐藏文件开关（定义 = 任意路径组件以 `.` 开头；切换后需重建才对已索引数据生效）
- **索引范围**：roots 列表（新增 / 移除 / 启用停用，✅/⏸ 标记）+ excludes 列表（新增走 `NSOpenPanel`，新增时立即清理已索引的被排除路径）
- **维护**：重建按钮（走 `RebuildCoordinator`，后台队列，`NSProgressIndicator` 进行中指示，并发保护；最近一次时间/结果/摘要从 `settings` 表读取）
- **关于**：诊断信息（DB 路径、schema 版本、roots 总数/启用数、excludes 数、files 行数、隐藏开关、最近一次重建）
Core 侧：`Schema` 升到 v3（加 `settings` 表，KV 存 `hidden_files_enabled` / `last_rebuild_*`）；`Indexer.Options.excludes` + `Options.includeHiddenFiles`；`PollingWatcher.Options.excludes` + `includeHiddenFiles`；`RebuildCoordinator` 负责并发保护与结果落库。

## 目录
```
Sources/
  CSQLite/              sqlite3 绑定
  SwiftSeekCore/        无 UI 的核心（DB、Schema、Indexer、EventQueue、
                        Watcher、SearchEngine、KeyboardSelection、
                        SettingsTypes、RebuildCoordinator）
  SwiftSeek/            AppKit GUI（AppDelegate、MainMenu、GlobalHotkey、
                        SearchWindowController/ViewController、
                        ResultActionRunner、SettingsWindowController）
  SwiftSeekIndex/       P1：命令行首次全量 + P3 增量索引器
  SwiftSeekSearch/      P2：命令行搜索入口
  SwiftSeekStartup/     P4：非 GUI 启动检查（headless 友好）
  SwiftSeekSmokeTest/   可执行冒烟测试（代替 XCTest）
scripts/
  build.sh              P6：本地交付构建脚本（`--sandbox` 开沙箱 env）
docs/
  stage_status.md       当前阶段、完成判定、历史 verdict
  architecture.md       架构快照（P5 最新）
  manual_test.md        手工验证步骤
  known_issues.md       P6 已知问题 / 当前限制 / 环境约束
  codex_acceptance.md   Codex 验收记录
  next_stage.md         Codex 颁发的下一阶段任务书
AGENTS.md / CLAUDE.md   代理协议
```

## 协作模式
- Claude：主开发代理，负责实现、自检。
- Codex：独立验收代理，负责 PASS / REJECT / 下一阶段任务书。
- 只有 Codex 能给出最终 `PROJECT COMPLETE`。
