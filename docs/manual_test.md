# SwiftSeek 手工测试（baseline + 所有归档轨道 + everything-ux-parity）

> Note:
> 这份文档覆盖 P0-P6、E1-E5、F1-F5、G1-G5、H1-H5、J1-J6 已落地能力的手工验证。
> `everything-ux-parity` 已完成；当前活跃轨道若未来切换，以 `docs/stage_status.md` 为准。
> 历史性能 / footprint / usage 轨道 benchmark 与任务书仍保留归档参考。

前置：macOS 13+，Swift 6.x 可用。

## 1. 构建

**普通开发环境**：
```
cd /path/to/SwiftSeek
swift build
```

**受限沙箱 / `codex exec` workspace-write 环境**（clang module cache 不可写，需覆盖路径）：
```
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift build --disable-sandbox
```
期望：`Build complete!` 无 error。

## 2. 冒烟测试

普通环境：`swift run SwiftSeekSmokeTest`

受限沙箱：
```
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekSmokeTest
```
期望末尾：
``` 
Smoke total: 198  pass: 198  fail: 0
```
并以 exit code 0 结束。

## 2b. 非 GUI 启动检查（适合 headless 验收环境）

受限沙箱无 WindowServer，`swift run SwiftSeek` 无法走完 AppDelegate。改用：
```
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-check.sqlite3
```
期望输出：
```
SwiftSeek: database ready at /tmp/ss-check.sqlite3 schema=3
SwiftSeek: startup check PASS
```
exit code 0。这证明 `AppPaths.ensureSupportDirectory + Database.open + migrate + SearchEngine.init` 链路可用。

## 3. GUI 启动
```
swift run SwiftSeek
```
期望：
- 前台出现 SwiftSeek 进程（Dock / 顶部菜单栏）
- 顶部菜单第一项为 "SwiftSeek"（关于 / 设置… / 隐藏 / 退出）
- 自动弹出"SwiftSeek 设置"窗口，含四个标签：常规 / 索引范围 / 维护 / 关于
- 控制台输出：`SwiftSeek: database ready at <path> schema=3`
- `<path>` 指向 `~/Library/Application Support/SwiftSeek/index.sqlite3`

退出：菜单 "SwiftSeek → 退出 SwiftSeek" 或 ⌘Q。

## 4. 数据库落盘校验
```
ls -l ~/Library/Application\ Support/SwiftSeek/
sqlite3 ~/Library/Application\ Support/SwiftSeek/index.sqlite3 ".tables"
sqlite3 ~/Library/Application\ Support/SwiftSeek/index.sqlite3 "PRAGMA user_version;"
```
期望：
- 目录存在，含 `index.sqlite3`（以及 WAL 下的 `-wal`、`-shm` 可选）
- `.tables` 至少输出：`excludes  file_grams  files  meta  roots  settings`
- `user_version` 为 `3`

## 5. 重开保持
再跑一次 `swift run SwiftSeek`，确认不会因已存在 DB 而报错。

## 已知范围外（当前阶段不做）
- 打包、签名、发布（P6）
- 全文内容搜索 / OCR / 语义搜索（v1 外）

如上述任一期望项不满足即为对应阶段未完成，不得视为通过。

---

## P1 手工测试

### 6. 命令行首次全量索引

```
# 准备样本目录
SAMPLE=$(mktemp -d -t swiftseek-sample)
mkdir -p "$SAMPLE/sub1/sub2" "$SAMPLE/empty-dir" "$SAMPLE/中文目录"
echo hello > "$SAMPLE/a.txt"
echo world > "$SAMPLE/sub1/b.txt"
echo deep  > "$SAMPLE/sub1/sub2/c.txt"
echo cn    > "$SAMPLE/中文目录/文件.txt"
touch "$SAMPLE/with space.txt"

# 指定一个独立 DB，避免污染默认库
DB=$(mktemp -t swiftseek-p1).sqlite3; rm -f "$DB"
swift run SwiftSeekIndex "$SAMPLE" --db "$DB"
```

期望：
- stderr 至少一条 `[progress] scanned=N inserted=M` 行
- stdout 最后两行：
  ```
  [DONE] root=<canonical root> scanned=10 inserted=10 skipped=0 time=...s
  db: roots=1 files=10
  ```
- 退出码 0

数据库核对：
```
sqlite3 "$DB" "SELECT path FROM roots;"
sqlite3 "$DB" "SELECT COUNT(*) FROM files;"
sqlite3 "$DB" "SELECT name FROM files ORDER BY path;"
sqlite3 "$DB" "SELECT COUNT(*) FROM files WHERE path = (SELECT path FROM roots) OR path LIKE (SELECT path FROM roots)||'/%';"
```
期望：
- `roots` 返回 canonical 根（如 `/private/var/folders/...`）
- `files` 合计 10 条
- 名字列含 `a.txt` / `b.txt` / `c.txt` / `with space.txt` / `文件.txt` / `中文目录` 等
- 前缀匹配查询返回 10（根与所有后代同前缀）

### 7. 取消（真取消）

```
BIG=$(mktemp -d -t swiftseek-big)
for i in $(seq 1 200); do
  mkdir -p "$BIG/dir$i"
  for j in $(seq 1 50); do echo x > "$BIG/dir$i/file$j.txt"; done
done
DB=$(mktemp -t swiftseek-cancel).sqlite3; rm -f "$DB"
swift run SwiftSeekIndex "$BIG" --db "$DB" --cancel-after-ms 30 --batch 100 --progress 100
echo "exit=$?"
sqlite3 "$DB" "SELECT COUNT(*) FROM files;"
```

期望：
- stderr 出现 `[SwiftSeekIndex] --cancel-after-ms fired`
- stdout 最后一行 `[CANCELLED] ... scanned=... inserted=... ...`
- exit=130
- 最终 files 数远少于 10000（确认取消后真的停了）
- `files` 数应当是 `--batch` 的整倍数（取消只保留取消前已成功提交的完整批次，不会再 flush 命中取消时内存里的尾批）。例如 `--batch 100` → `files % 100 == 0`

### 8. Ctrl-C 手工取消

在交互终端执行任意较长目录索引：
```
swift run SwiftSeekIndex "$HOME/Downloads" --db /tmp/demo.sqlite3 --batch 100 --progress 500
```
运行时按 Ctrl-C。

期望：
- 立即出现 `[SwiftSeekIndex] SIGINT received — cancelling`
- 几秒内输出 `[CANCELLED] ...` 并退出，退出码 130

---

## P2 手工测试

### 9. 命令行搜索入口

准备 P2 样本（先索引）：
```
SAMPLE=$(mktemp -d -t swiftseek-p2)
mkdir -p "$SAMPLE/docs" "$SAMPLE/beta" "$SAMPLE/extras-with-alpha"
touch "$SAMPLE/alpha.txt" "$SAMPLE/alphabet.txt"
touch "$SAMPLE/docs/alpha-notes.md"
touch "$SAMPLE/beta/alpha report.txt"
touch "$SAMPLE/extras-with-alpha/README.md"
touch "$SAMPLE/中文文档.md"

DB=$(mktemp -t swiftseek-p2).sqlite3; rm -f "$DB"
swift run SwiftSeekIndex "$SAMPLE" --db "$DB"
```

查询：
```
swift run SwiftSeekSearch "alp"         --db "$DB" --show-score
swift run SwiftSeekSearch "docs/alpha"  --db "$DB" --show-score
swift run SwiftSeekSearch "pha"         --db "$DB" --show-score
swift run SwiftSeekSearch "中文"        --db "$DB" --show-score
swift run SwiftSeekSearch "alpha report" --db "$DB" --show-score
```

期望：
- `alp`：4 条 `[800]` 文件名前缀命中（依次 alpha.txt / alphabet.txt / docs/alpha-notes.md / beta/alpha report.txt），随后 `[500]` `extras-with-alpha` 目录（name 包含 alp），最后 `[200]` `extras-with-alpha/README.md`（仅路径命中）
- `docs/alpha`：唯一 `[200] f <root>/docs/alpha-notes.md`
- `pha`：5 条 `[500]` 文件名包含 + 1 条 `[200]` 仅路径命中
- `中文`：唯一 `[800] f <root>/中文文档.md`（短 query 走 LIKE fallback）
- `alpha report`：唯一 `[800] f <root>/beta/alpha report.txt`（gram 路径召回）

### 10. grams 真实落库核查

```
sqlite3 "$DB" "SELECT COUNT(*) FROM file_grams;"
sqlite3 "$DB" "SELECT DISTINCT gram FROM file_grams WHERE gram LIKE 'alp%' ORDER BY gram LIMIT 5;"
```

期望：
- 行数明显非零（样本 6 文件 + 若干目录，各自贡献若干 3-gram）
- 能看到 `alp` / `alp` 相关 gram，证明 grams 是落库的真实表而非运行时内存拼接

### 11. P1 旧库平滑升级 P2

```
# 用只装了 P1 的实现再跑一次已有库？本仓已合并 P2，无法单独模拟。
# 等价方式：用旧 DB（user_version=1）手动构造
OLD_DB=$(mktemp -t swiftseek-old).sqlite3; rm -f "$OLD_DB"
sqlite3 "$OLD_DB" <<'SQL'
PRAGMA user_version=1;
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE files (id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER,
  path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, name_lower TEXT NOT NULL,
  is_dir INTEGER NOT NULL, size INTEGER NOT NULL DEFAULT 0,
  mtime INTEGER NOT NULL DEFAULT 0, inode INTEGER, volume_id INTEGER);
CREATE INDEX idx_files_name_lower ON files(name_lower);
CREATE INDEX idx_files_parent ON files(parent_id);
CREATE TABLE roots (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1);
CREATE TABLE excludes (id INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern TEXT NOT NULL UNIQUE);
INSERT INTO files(path,name,name_lower,is_dir) VALUES ('/old/row','row','row',0);
SQL
swift run SwiftSeekSearch "row" --db "$OLD_DB" --show-score
swift run SwiftSeekSearch "alpha" --db "$OLD_DB" --show-score
sqlite3 "$OLD_DB" "PRAGMA user_version;"
sqlite3 "$OLD_DB" "SELECT COUNT(*) FROM file_grams;"
sqlite3 "$OLD_DB" "SELECT path, path_lower FROM files;"
```

期望：
- `SwiftSeekSearch` 首次打开旧库自动迁移（`Database.migrate()` 应用 v2 migration + `backfillFileGrams()`）
- `user_version` 升为 `2`
- `.tables` 含 `file_grams`
- 旧行的 `path_lower` 从空被回填为 `LOWER(path)`
- `file_grams` 计数 > 0（旧行的 3-gram 已被回填）
- `row` / `alpha` 查询直接命中，无需重建索引（取决于旧行内容）

---

## P3 手工测试

### 12. `SwiftSeekIndex --watch-seconds N`：FSEvents 端到端

准备样本：
```
SAMPLE=$(mktemp -d -t swiftseek-p3)
mkdir -p "$SAMPLE/sub"
echo a1 > "$SAMPLE/alpha.txt"
echo b1 > "$SAMPLE/beta.txt"
echo i1 > "$SAMPLE/sub/inner.txt"

DB=$(mktemp -t swiftseek-p3).sqlite3; rm -f "$DB"
```

启动 watch（30 秒后自动退出；另开一个终端做改动）：
```
swift run SwiftSeekIndex "$SAMPLE" --db "$DB" --watch-seconds 30 --debounce-ms 200
```

另一个终端里依次做四种变更：
```
# 新增
echo g1 > "$SAMPLE/gamma.txt"

# 重命名
mv "$SAMPLE/alpha.txt" "$SAMPLE/alpha-renamed.txt"

# 删除
rm "$SAMPLE/beta.txt"

# 快速多次修改（观察 debounce 合并）
echo x1 >> "$SAMPLE/gamma.txt"
echo x2 >> "$SAMPLE/gamma.txt"
echo x3 >> "$SAMPLE/gamma.txt"
```

期望 watch 侧 stdout：
- 首次 `[DONE] ...` + `db: roots=1 files=4`
- `[watch] started root=<canonical> debounce=0.2s`
- 每次变更后出现一行 `[watch] batch size=N sample=[...]`
- 紧跟一行 `[rescan] processed=X upserted=Y deleted=Z fallbackDirs=W`
- 3 次追加 `gamma.txt` 应合并为单一 batch（size=1 路径为 gamma.txt），验证 debounce 真的生效
- 30 秒到期或 Ctrl-C 退出时输出 `[watch] stopped` 和 `db: roots=1 files=4`

DB 与搜索核对：
```
sqlite3 "$DB" "SELECT name FROM files ORDER BY path;"
swift run SwiftSeekSearch "alpha"          --db "$DB"
swift run SwiftSeekSearch "alpha-renamed"  --db "$DB"
swift run SwiftSeekSearch "beta"           --db "$DB"
swift run SwiftSeekSearch "gamma"          --db "$DB"
```
期望：
- `files` 表含：`<root>` / `sub` / `sub/inner.txt` / `alpha-renamed.txt` / `gamma.txt`（共 5 行）
- `alpha`：只命中 `alpha-renamed.txt`，旧 `alpha.txt` 已被清理
- `alpha-renamed`：命中 `alpha-renamed.txt`
- `beta`：0 结果（已删除且已从索引移除）
- `gamma`：命中 `gamma.txt`

### 13. 删除目录（级联清理）

在 watch 仍运行时：
```
rm -rf "$SAMPLE/sub"
```
期望：
- `[watch] batch size=1` 指向 `sub`
- `[rescan] ... deleted>=2 ...`（`sub` 和 `sub/inner.txt` 两行都被清掉）
- `SELECT * FROM files WHERE path LIKE '<root>/sub%';` 返回 0 行

### 14. Ctrl-C 优雅退出

`--watch`（无时限）模式下按 Ctrl-C：
```
swift run SwiftSeekIndex "$SAMPLE" --db "$DB" --watch
# 按 Ctrl-C
```
期望：
- `[SwiftSeekIndex] SIGINT received — stopping watcher`
- `[watch] stopped`
- 进程以 exit code 0 结束
- 中途触发的变更若已 debounce 排空则已写入 DB

### 15. 受限沙箱 / FSEvents 被闸门（polling fallback）

Codex `workspace-write` 沙箱下 FSEvents 可能静默失效。此时 `PollingWatcher` 必须接棒。最小验证：
```
swift run SwiftSeekIndex "$SAMPLE" --db "$DB" --watch-seconds 6 --poll-seconds 0.5 --no-poll
# 只有 FSEvents；在受限沙箱内很可能看不到 batch 日志
swift run SwiftSeekIndex "$SAMPLE" --db "$DB" --watch-seconds 6 --poll-seconds 0.5
# 双 backend：无论哪边先拿到事件，都能把变更落库
```
期望日志起始：
```
[watch] FSEvents start=true|false
[watch] polling started interval=0.5s
[watch] started root=... debounce=0.2s fsevents=true|false polling=true
```
期望至少一条 `[watch] batch ...` 与 `[rescan] ...`，且结束时 DB 行数 / `SwiftSeekSearch` 结果与磁盘一致。

---

## 真实验证记录（P3）

### 2026-04-23 P3 round 2 本机验证（Claude，Codex REJECT 闭环）

修复项：`IncrementalWatcher.start()` 改返回 `Bool` 并实际校验 `FSEventStreamStart`；新增 `PollingWatcher`（读 mtime+size 快照、`DispatchSourceTimer` 周期扫描），CLI 默认并列启动两者，smoke 端到端用例与 CLI watch 都在任一 backend 有能力时自动落库。

- `swift build` → `Build complete!` 0 warn / 0 err
- `swift run SwiftSeekSmokeTest` → `Smoke total: 29  pass: 29  fail: 0`
  - 新增 `P3 PollingWatcher alone detects create/modify/delete without FSEvents`：只挂 PollingWatcher，新建 + 删除各触发一次 batch，搜索视图同步
  - 新增 `P3 IncrementalWatcher.start returns false for non-existent root`：验证 `start()` 真实返回值语义 + `stop()` 空安全
  - 既有 `P3 IncrementalWatcher + EventQueue detect real FS events end-to-end` 改为 FSEvents + polling 并列，whichever-fires-first 满足断言
- 手工 `SwiftSeekIndex --watch-seconds 6 --poll-seconds 0.5` 双 backend 闭环（样本：alpha.txt / beta.txt / sub/inner.txt）：
  - `[watch] FSEvents start=true` / `[watch] polling started interval=0.5s` / `[watch] started root=... fsevents=true polling=true`
  - 新增 `gamma.txt` → `[watch] batch size=1 sample=[".../gamma.txt"]` → `[rescan] processed=1 upserted=1 deleted=0`
  - `mv alpha.txt alpha-renamed.txt` → `batch size=4` → `[rescan] upserted=6 deleted=1 fallbackDirs=1`（root 目录被同批事件拉进 fallback 走一轮 enumerator diff）
  - `rm beta.txt` → batch 覆盖 beta.txt → `deleted=1`
  - 连续 3 次 `echo >> gamma.txt` → 合并为 `batch size=1` 单次 rescan
  - 终态 DB：5 行（root + sub + sub/inner.txt + gamma.txt + alpha-renamed.txt）；`SwiftSeekSearch alpha` 只命中 `alpha-renamed.txt`，`beta` 0 结果，`gamma` 命中

### 2026-04-23 P3 round 1 本机验证（已被 round 2 迭代覆盖）

- `swift build` → `Build complete!` 0 warning / 0 error
- `swift run SwiftSeekSmokeTest` → `Smoke total: 27  pass: 27  fail: 0`
  - 新增 8 条 P3 用例覆盖：EventQueue debounce、coalescePrefixes（含 `/a/foo` 不吞 `/a/foobar` 反例）、rescanPaths 新增 / 删除 / 改名 / 目录级删除级联 / 修改 mtime 刷新、IncrementalWatcher+EventQueue 真实 FSEvents 端到端
- `SwiftSeekIndex --watch-seconds 30 --debounce-ms 200` 在 `swiftseek-p3.*` 样本目录实地跑：
  - 新增 `gamma.txt` → `batch size=1 sample=[".../gamma.txt"]` → `[rescan] processed=1 upserted=1 deleted=0 fallbackDirs=0`
  - `mv alpha.txt alpha-renamed.txt` → `batch size=2 sample=[".../alpha-renamed.txt", ".../alpha.txt"]` → `[rescan] processed=2 upserted=1 deleted=1 fallbackDirs=0`
  - `rm beta.txt` → `batch size=1 sample=[".../beta.txt"]` → `[rescan] processed=1 upserted=0 deleted=1 fallbackDirs=0`
  - 连续 3 次 `echo >> gamma.txt` → 合并为一个 `batch size=1`（验证 debounce 真实生效）
  - 最终 `db: roots=1 files=5`（root + sub + sub/inner.txt + gamma.txt + alpha-renamed.txt），`file_grams` 431 行
  - `SwiftSeekSearch alpha` → 只命中 `alpha-renamed.txt`；`beta` → 0 结果；`gamma` → 命中 `gamma.txt`
- 早期一次 smoke crash（`Exit 139`）经 `~/Library/Logs/DiagnosticReports/` 崩溃报告定位到 `watcherCallback` 内 `cfArray as? [String]` 段错误，根因为 FSEvents flags 缺 `kFSEventStreamCreateFlagUseCFTypes`；补 flag 后 smoke 27/27 全绿，手工 watch 亦稳定

---

## 真实验证记录（P2）

### 2026-04-23 P2 本机验证（Claude 主开发代理）

- `swift build` → `Build complete!` 0 warning / 0 error
- `swift run SwiftSeekSmokeTest` → `Smoke total: 19  pass: 19  fail: 0`
  - 新增 8 条 P2 用例覆盖：normalize / 文件名前缀命中 / 路径命中但文件名不命中 / 3-gram 候选召回 / 排序稳定 / CJK 文件名 / 含空格文件名 / v1→v2 迁移 + grams 回填
- CLI 实地查询（临时样本 DB）：
  - `alp` → 6 行：4×`[800]` 文件名前缀命中，1×`[500]` 目录 name 包含，1×`[200]` 仅路径命中
  - `docs/alpha` → 1 行 `[200] f .../docs/alpha-notes.md`
  - `pha` → 6 行：5×`[500]` + 1×`[200]`
  - `中文` → 1 行 `[800] f .../中文文档.md`
  - `alpha report` → 1 行 `[800] f .../beta/alpha report.txt`
- `sqlite3 <db> "SELECT COUNT(*) FROM file_grams;"` 非零（6 文件样本 DB 返回 959 行），`file_grams` 表确实落库
- 旧库（user_version=1，2 条老行）通过 `SwiftSeekSearch` 触发 `migrate()`：`PRAGMA user_version` 升至 `2`，`file_grams` 回填 30 行；查询 `row` → `[800] /old/Row.TXT`，查询 `alpha` → `[800] /archive/docs/Alpha.md`，无需重建

---

## 真实验证记录（P1）

### 2026-04-23 P1 本机验证（Claude 主开发代理）— round 2 (Codex REJECT 闭环)

- `swift build` → `Build complete!`
- `swift run SwiftSeekSmokeTest` → `Smoke total: 11  pass: 11  fail: 0`
  - 新增用例 `Pre-cancelled indexer flushes no rows (no ghost writes)`：预先 cancel + index → stats.inserted == 0 且 `files` 表行数 == 0
  - 新增用例 `In-flight cancel never flushes pending partial batch`：在 progress 回调里触发 cancel → stats.inserted % batchSize == 0 且 DB 行数一致
- 样本目录（10 条）索引：stdout `[DONE] ... scanned=10 inserted=10 skipped=0`，DB 内 `roots=1` `files=10`，中文/空格路径均落盘
- 10000 条样本 + `--cancel-after-ms 30 --batch 100 --progress 100`：触发 `[CANCELLED]`，最终 `files=3100`（100 的整倍数，确认取消后没有继续 flush 尾批），scanned=3100 远少于完整 10030
- 路径规范化验证：`Indexer.canonicalize("/tmp")` 返回 `/private/tmp`，`roots.path` 与 `files.path` 共享同一 canonical 前缀

### round 1 原始问题（已关闭）
Codex P1 round 1 发现：取消命中 break 之后仍执行 post-loop `insertFiles(batch)`，导致 `inserted=4133`（batch=100 条件下 4100 + 33 条尾批被错误写入）。修复：`if !cancelled, !batch.isEmpty { ... }`，取消后不再 flush 尾批。

---

## 真实验证记录

### 2026-04-23 10:46 本机验证（Claude 主开发代理）

环境：
- macOS（Darwin 25.4.0）
- Swift 6.3.1（`/usr/bin/swift`，Command Line Tools）
- Xcode.app 未安装（`xcode-select -p` = `/Library/Developer/CommandLineTools`）

执行步骤与观察：

1. `rm -rf "$HOME/Library/Application Support/SwiftSeek"` — 预先清理旧数据目录，保证验证可重现
2. `swift build` → `Build complete!`
3. `swift run SwiftSeek`（后台启动后探测 8 秒）
   - 进程存活：`PID=75684 STAT=SN`
   - 控制台日志：
     ```
     2026-04-23 10:46:44.912 SwiftSeek[75684:7527414] SwiftSeek: database ready at ~/Library/Application Support/SwiftSeek/index.sqlite3 schema=1
     ```
4. 结束进程后校验数据落盘：
   - `ls -la "$HOME/Library/Application Support/SwiftSeek/"` 显示：
     ```
     index.sqlite3       4096 字节
     index.sqlite3-shm  32768 字节
     index.sqlite3-wal  45352 字节
     ```
   - `sqlite3 index.sqlite3 ".tables"` → `excludes  files  meta  roots`
   - `sqlite3 index.sqlite3 "PRAGMA user_version;"` → `1`

窗口 / 菜单观察（前台短时交互，未长期驻留）：
- Dock / 菜单栏出现 SwiftSeek 进程（`.regular` 激活策略生效）
- 顶部菜单第一项为 "SwiftSeek"，子项：关于 SwiftSeek / 设置…（⌘,） / 隐藏 SwiftSeek（⌘H） / 退出 SwiftSeek（⌘Q）
- 启动自动弹出 "SwiftSeek 设置" 窗口，含四个 tab：常规 / 索引范围 / 维护 / 关于
- 每个 tab 打开后显示占位标题与说明文本，未连接真实 I/O（P0 约束）

结果：
- 第 1、2、3、4、5 项期望均成立
- 第 3 项（GUI）中，因是 SwiftPM 非打包可执行，运行期间系统会打印少量 AppKit / LaunchServices 环境相关的辅助日志，不影响业务日志与 DB 初始化
- 第 5 项（二次启动不报错）通过 `swift run SwiftSeek` 再次触发 DB 打开时 `migrate()` 走幂等分支

结论：P0 完成判定 1–5 的证据已采集，文档与实现一致。

---

## P4 手工测试（搜索窗口 + 全局热键 + 键盘流）

前置：本机已跑过 P1 首次索引，DB 已有行（否则搜索结果恒为空）。

### 16. 准备样本索引
```
mkdir -p /tmp/swiftseek-p4-sample/{docs,beta,中文目录}
touch /tmp/swiftseek-p4-sample/alpha.txt
touch /tmp/swiftseek-p4-sample/alphabet.txt
touch /tmp/swiftseek-p4-sample/docs/alpha-notes.md
touch /tmp/swiftseek-p4-sample/beta/beta-report.txt
touch /tmp/swiftseek-p4-sample/中文目录/笔记.md
swift run --disable-sandbox SwiftSeekIndex /tmp/swiftseek-p4-sample
```
期望末尾：`[done] ... scanned=N inserted=N cancelled=false`（N ≥ 7）。

### 17. GUI 启动 + 热键
```
swift run --disable-sandbox SwiftSeek
```
- 控制台输出 `SwiftSeek: database ready ... schema=2`
- 如果 ⌥Space 已被其他 App 占用，会额外输出
  `SwiftSeek: global hotkey registration failed — fallback to menu item 搜索…`
  否则无额外输出即注册成功
- 按 ⌥Space：浮动搜索窗口应从屏幕中央略上方位置出现，输入框获取焦点
- 如 ⌥Space 冲突：改点菜单 `SwiftSeek → 搜索…`（同样 keyEquivalent ⌥Space），等效唤出

### 18. 实时查询
- 在输入框键入 `alp`
  - 约 80ms 后结果表出现：`alpha.txt`、`alphabet.txt`、`docs/alpha-notes.md` 等
  - 右下状态栏显示 `X 条 · Yms`
  - 前三项 score 800（文件名前缀命中），排在顶部
- 继续键入 `alpha`：结果相应收敛
- 清空输入框：状态栏变为空字符串，结果表清空

### 19. 键盘选择 + 动作
- ↓ / ↑：在结果行之间移动；最后一行按 ↓ 环回到第一行
- ⏎：调用 `NSWorkspace.open` 打开选中项；窗口应立即隐藏
  - 文件：系统默认应用打开
  - 目录：Finder 打开
- 再次 ⌥Space 唤回窗口；上次查询会被重置（首次 commit 的窗口不保留历史）
- ⌘⏎（Reveal in Finder）：Finder 打开并选中目标；窗口保留
- ⌘⇧C（Copy Path）：剪贴板写入路径；状态栏短暂显示 `已复制：<path>`
  - 粘贴验证：`pbpaste` 应打印对应路径
- ESC：立即隐藏窗口

### 20. resignKey 自动隐藏
- 窗口可见时，点击其他 App（如 Finder 或 Terminal）
- 期望 SwiftSeek 搜索窗口立即 `orderOut`（与 Spotlight / Alfred 一致）

### 21. 退出
- 菜单 `SwiftSeek → 退出 SwiftSeek`（⌘Q）
- 期望进程退出，无崩溃；下次启动 DB 依然可用

### 22. P4 完成后受限沙箱下的可观察证据（2026-04-23 Claude round 1）
（在不支持真实 GUI 的沙箱中，只做"能启动不崩溃"的最小可见证据）
- `swift run --disable-sandbox SwiftSeek` 后台跑 4 秒然后 `kill`：
  - stdout/stderr 只含 `SwiftSeek: database ready at ~/Library/Application Support/SwiftSeek/index.sqlite3 schema=2`
  - 未打印 `hotkey registration failed` → ⌥Space 注册成功
  - 进程未 panic / crash 报告
- `swift run --disable-sandbox SwiftSeekSmokeTest` 36/36 全绿（含 7 条 P4）

---

## P5 手工测试（设置页真实闭环）

前置：`swift run SwiftSeek` 已启动。打开 `SwiftSeek → 设置…` 或按 ⌘,。

### 23. 常规 tab：隐藏文件开关
- 初始：复选框默认未勾选
- 勾上 → 关 → 勾上：每次切换要立即写库，用 `sqlite3 <db> "SELECT value FROM settings WHERE key='hidden_files_enabled';"` 应分别返回 `1` / `0` / `1`
- 提示文本应说明"切换后请到维护 → 重建索引让改动生效"

### 24. 索引范围 tab：roots 管理
1. 点击 `新增目录…` → macOS `NSOpenPanel` 弹出 → 选一个真实目录 → 列表多出一项，前缀 ✅
2. 选中某项 → 点 `启用/停用所选` → 前缀切换 ✅ ↔ ⏸
3. 再点一次 → 变回 ✅
4. 选中某项 → 点 `移除所选` → 弹窗警告 → 确认 → 该项消失，且 `sqlite3 <db> "SELECT COUNT(*) FROM files WHERE path LIKE '<removed-path>/%';"` 返回 0（级联清理）
5. 顶部状态栏显示 `共 N 项，启用 M`

### 25. 索引范围 tab：excludes 管理
1. 先把 step 24 里新增的 root 加进来（如 `/tmp/swiftseek-p5-sample`）
2. 用 `SwiftSeekIndex /tmp/swiftseek-p5-sample` 先做一次全量索引（含 `cache/big.log` 等）
3. 回到设置页 → `新增排除目录…` → 选择 `/tmp/swiftseek-p5-sample/cache`
4. 列表多出一项 🚫 `/tmp/swiftseek-p5-sample/cache`
5. 立刻验证：`sqlite3 <db> "SELECT COUNT(*) FROM files WHERE path LIKE '/tmp/swiftseek-p5-sample/cache%';"` = 0（立即清理）
6. 回到搜索窗口查询 `big.log` 应不再命中

### 26. 维护 tab：重建索引
1. 点击 `重建索引` → 按钮 disabled + `NSProgressIndicator` 开始转
2. 状态栏显示 `重建中 · root 1/N · scanned=...` 滚动更新
3. 完成后：按钮重新 enabled，进度停止，状态栏变成两行：
   - `上次重建：<ISO8601 时间> · success`
   - `roots=<N> scanned=<S> inserted=<I> skipped=<Sk> duration=<X.XX>s`
4. 同一 session 内快速双击重建按钮：第二次应被拒绝（状态栏短暂显示"已有重建在进行中，忽略此次触发"）
5. `sqlite3 <db> "SELECT key, value FROM settings WHERE key LIKE 'last_rebuild%';"` 应返回三行

### 27. 关于 tab：诊断信息
- 切到关于 tab 后自动显示：
  - `数据库：~/Library/Application Support/SwiftSeek/index.sqlite3`
  - `schema 版本：3`
  - `roots：总 N，启用 M`
  - `excludes：K`
  - `files 行数：<当前 COUNT(*)>`
  - `隐藏文件纳入索引：是/否`（与常规 tab 一致）
  - `上次重建时间` / `上次重建结果` / `上次重建摘要`（与维护 tab 一致）
- 点 `刷新诊断` → 立刻重算

### 28. P5 完成后受限沙箱下的可观察证据（2026-04-23 Claude round 1）
（沙箱无 GUI，用 CLI + smoke 替代手工 UI 验证）
- `swift run --disable-sandbox SwiftSeekSmokeTest` → `Smoke total: 51  pass: 51  fail: 0`
- `swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-p5.sqlite3` → `database ready ... schema=3` + `startup check PASS`
- 后台启动 SwiftSeek 4s → `database ready ... schema=3` 落盘，未 crash

---

## P6 手工测试（稳定性与交付）

### 29. 本地交付脚本
```
./scripts/build.sh
```
或沙箱：
```
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/build.sh --sandbox
```
期望：
- 依次跑 `swift build -c release`、`SwiftSeekSmokeTest` (51/51)、`SwiftSeekStartup`（临时 db）
- 末尾列出 `.build/release/SwiftSeek*` 五个可执行文件
- 打印运行命令和默认 DB 路径
- 退出码 0

### 30. release 二进制独立运行
```
.build/release/SwiftSeekStartup --db /tmp/ss-delivery.sqlite3
```
期望：
```
SwiftSeek: database ready at /tmp/ss-delivery.sqlite3 schema=3
SwiftSeek: startup check PASS
```

### 31. silent-fail 审计（故意制造 DB 错误）
准备一个只读 DB：
```
cp ~/Library/Application\ Support/SwiftSeek/index.sqlite3 /tmp/readonly.sqlite3
chmod a-w /tmp/readonly.sqlite3
```
然后用该 DB 启动 SwiftSeekIndex（`--db /tmp/readonly.sqlite3` 新增一个 root）。
期望：stderr 打印明确错误路径 / 原因，不是静默退出。

### 32. 日志可观察
运行 GUI 并在 `Console.app` 过滤 `SwiftSeek`：
- 启动时能看到 `SwiftSeek: database ready at ... schema=3`
- 如果热键冲突：`SwiftSeek: global hotkey registration failed — fallback to menu item 搜索…`
- 设置页操作失败会通过 `NSLog("SwiftSeek: ...")` 写出
- MaintenancePane 重建失败会在 UI 显示 `failed: <msg>`，同时写 log

### 33a. E1 相关性 + 多列 + 过滤 + root 状态（快速回归）
1. 启动 GUI，`⌥Space` 呼出搜索窗
2. 输入 `alpha report` → 只返回名字同时含 alpha 和 report 的项（多词 AND）
3. 输入 `ext:md` → 仅 .md 文件（E3 过滤）
4. 点列头切换排序（名称 / 修改时间 / 大小）→ 顺序变化；切回 score 列恢复
5. 设置 → 索引范围 → 点 `+` 添加新目录 → 不弹 confirm，直接看到 ⏳ 索引中 → 自动转 ✅ 就绪（E4）
6. 设置 → 索引范围 → 拖入多个文件夹 → 全部自动索引，无遗漏

### 33b. E5 热键配置
1. 设置 → 常规 → 全局热键下拉 → 切换到 ⌃Space
   - 期望：热键立刻生效；现在按 ⌥Space 不出搜索窗，按 ⌃Space 出
2. 在另一个会占用该组合的 App 打开状态下再次切换（例如切到已被其他 app 占用的组合）
   - 期望：弹窗 "无法注册该热键"；popup 自动回滚到上一个有效值
3. 编辑 `~/Library/Application Support/SwiftSeek/index.sqlite3`：
   ```
   sqlite3 index.sqlite3 "UPDATE settings SET value='not-a-number' WHERE key='hotkey_key_code';"
   ```
   重新启动 GUI → 期望回退到 ⌥Space 默认组合，不崩溃

### 33c. 搜索结果上限（E1 设置化）
1. 设置 → 常规 → 搜索结果上限：改为 50
2. 搜索一个高命中 query（例如 `txt`）
3. 期望状态栏 `仅显示前 50 条`；改回 100 立即生效（无需重启）

### 33d. F3 高密度结果视图 + 排序入口 + 持久化
1. 启动 GUI，`⌥Space` 呼出搜索窗，搜索一个较高命中 query（例如 `txt`）
2. 行高应为 18px（比 E2 的 22px 更紧凑），单屏可见行数明显增多
3. 名称列使用 **中等字重**（.medium），路径列使用 **三级灰**（tertiaryLabel），视觉层次分明
4. 修改时间 / 大小列使用 **等宽数字字体**（monospacedDigitSystemFont），行间数字对齐
5. 文件夹图标带蓝色 tint，文件图标保留 template 灰色，首屏可区分
6. 点击 `名称` 列头切换排序（asc/desc 交替），再点 `大小` 列头切到 size 排序
7. 拖动列边界调整列宽
8. 关闭搜索窗再次呼出 —— 上次的排序 key + 方向 + 列宽应完整恢复
9. 完全退出 GUI 再启动（`⌘Q` 再 `swift run SwiftSeek`）—— 排序与列宽仍应恢复到上次
10. 操作过程中验证键盘流 ↑↓/⏎/⌘⏎/⌘⇧C/⌘Y/ESC 全部不回退
11. 右键菜单、拖拽到 Finder、QuickLook 预览 全部不回退
12. 将列宽拖到很小的值（例如名称 100px）再呼出 —— 应恢复到该值，不重置

### 33e. F3 malformed 配置不崩
1. 关 GUI
2. 手动污染 settings：
   ```
   sqlite3 ~/Library/Application\ Support/SwiftSeek/index.sqlite3 \
     "UPDATE settings SET value='bogus-key' WHERE key='result_sort_key';"
   ```
3. 再启动 GUI —— 应回退到 score 降序，不崩不警告死循环

### 33f. G1 DB 体积观测 + 维护入口
1. CLI：对当前默认 DB 运行
   ```bash
   swift run SwiftSeekDBStats
   ```
   期望输出：DB path、schema version、main/wal/shm 文件大小、page_count/size、六张表行数、avg grams/bigrams per file、per-table 列表
2. CLI 对小库可执行 maintenance：
   ```bash
   swift run SwiftSeekDBStats --db /tmp/ss-g1.sqlite3 --run checkpoint
   swift run SwiftSeekDBStats --db /tmp/ss-g1.sqlite3 --run optimize
   swift run SwiftSeekDBStats --db /tmp/ss-g1.sqlite3 --run vacuum
   ```
   - 不带 `--yes` 时 vacuum 会打印风险横幅并 exit 1
   - 带 `--yes` 时 vacuum 实际执行，末尾打印 before/after main+wal 对比
3. GUI：
   - 设置 → 维护 tab
   - 在"重建索引"下方应显示：`DB 体积` 标题 + 多行 monospace stats（main/wal/shm、pages、files/grams/bigrams 行数、avg、per-table）
   - 四个按钮：`刷新` / `WAL checkpoint` / `Optimize` / `VACUUM…`
   - 点刷新 → stats 立刻重新计算
   - 点 checkpoint / optimize → 下方状态栏显示 "X 完成，用时 Y.YYs"
   - 点 `VACUUM…` → 弹出确认对话框，包含退出其他进程 / 磁盘空间要求 / 耗时 / "只是临时压实，不能根治" 四条
   - 点取消 → 什么都不发生
   - 点"开始 VACUUM" → 后台线程执行，期间按钮禁用；完成后状态栏显示用时 + stats 自动刷新
4. stats 读取失败 fallback：删除 file_bigrams 表（手动 sqlite3）再打开维护 tab，应继续显示其它字段，不崩

### 33g. G4 索引模式切换 UI
1. 设置 → 常规 tab → 滚到最下，应看到"索引模式："下拉
2. 下拉有两个选项：
   - `Compact（推荐）` — 默认（新 DB）
   - `Full path substring（高级，更大体积）`
3. 下拉下方有多行 note 描述两种模式能力差异
4. 切换操作：
   a. 从 Compact 切到 Fullpath：弹窗 "切换到 Full path substring 模式"，说明 plain query 匹配范围变更，点 "切换"。再次查 `getIndexMode()` 应返回 fullpath。
   b. 从 Fullpath 切到 Compact：弹窗 "切换到 Compact 索引模式"，说明 plain query 只匹配文件名；选 "切换并开始 compact 回填" → 后台 MigrationCoordinator 启动（维护页将显示 file_name_grams 行数增长）
   c. 点 "取消"：UI 下拉回滚到之前的选项；DB 未变
5. 维护 tab → DB 体积 stats 能看到 `file_name_grams` / `file_name_bigrams` / `file_path_segments` 行数（G1 已有，G4 无需改动）
5b. 维护 tab → `开始 / 继续 compact 回填` 按钮：
   - Compact 模式下可点击；Fullpath 模式下 disabled，tooltip 说明原因
   - 点击后状态栏显示 `Compact 回填中：X / Y（last_file_id=Z）`，数字会增长
   - 中断（关设置窗口 / 退 app）后再次打开，再点按钮会从 `last_file_id` 续跑
   - 失败时状态栏显示错误 + "再次点击可从断点继续"
6. 模式切换后立即搜索：
   - Compact：`myproj`（路径中间子串）不再命中路径下的文件；`path:docs` 能命中
   - Fullpath：`myproj` 能命中包含 `myproj-old/` 路径的文件

### 33h. H1 usage 数据模型 + `.open` 动作记录
前置：用 release 包启动 SwiftSeek，并确保已索引至少一个可打开的目标文件（如 `~/Documents/<name>.pdf` 或一个 `.md`）。

1. DB 路径 `~/Library/Application Support/SwiftSeek/swiftseek.sqlite3`，先用 `sqlite3` CLI 核 schema：
   ```bash
   sqlite3 ~/Library/Application\ Support/SwiftSeek/swiftseek.sqlite3 \
     'SELECT name FROM sqlite_master WHERE type="table" AND name="file_usage";'
   ```
   应返回 `file_usage` 一行。`PRAGMA user_version;` 应返回 `6`。
2. 打开 SwiftSeek 搜索窗，输入文件名 query，回车打开。
3. 再次 sqlite3 核：
   ```bash
   sqlite3 ~/Library/Application\ Support/SwiftSeek/swiftseek.sqlite3 \
     "SELECT f.path, u.open_count, u.last_opened_at, u.updated_at FROM file_usage u JOIN files f ON f.id = u.file_id ORDER BY u.last_opened_at DESC LIMIT 5;"
   ```
   刚打开的文件 `open_count >= 1`，`last_opened_at` 和 `updated_at` 是最近时间戳（Unix epoch 秒）。
4. 同一目标连续回车打开 3 次，重复 sqlite3 查询，`open_count` 应累加到 4（或原值 +3）。
5. 打开一个**无默认处理器**的文件（如随便 `touch /tmp/swiftseek-h1-bogus.xxnoextxxx` 然后 `SwiftSeekIndex` 索引它再搜索打开） — `NSWorkspace.open` 应返 false，查 DB `file_usage` 不应有这个文件的行。
6. Reveal in Finder（⌘+Enter）和 Copy Path（⌘+Shift+C） **不**应累加 `open_count`（只有 `.open` 算 Run Count）。
7. 从索引中删除某个已有 usage 行的文件（在设置里 remove 其所在 root，或手动 `DELETE FROM files WHERE path=?`），再核 `file_usage` 不应留该行（`ON DELETE CASCADE`）。
8. 若打开成功但 `SearchViewController` 调 `recordOpen` 时目标路径不在 `files` 表（edge case：刚 exclude 或 root disable），应看到 Console 日志 `SwiftSeek: recordOpen skipped, path not in index: ...`；DB 保持不变。

### 33i. H2 usage tie-break + 结果表新列
前置：已通过 33h 手测确保 `file_usage` 会在 `.open` 后累加。

1. 启动 SwiftSeek 搜索窗，输入常用 query；结果表应看到 6 列：
   名称 / 路径 / 修改时间 / 大小 / 打开次数 / 最近打开
2. 从未打开过的行，`打开次数` 列显示 `—`，`最近打开` 显示 `—`；打开过的行显示整数次数和相对时间（与 `修改时间` 同格式）。
3. tie-break 手测：
   - 输入能命中两个**同名**文件的 query（例如在两个不同目录各放一个 `todo.txt` 并已索引）；两条结果应 score 相同
   - 其中一条文件打开 3 次 → 再次 query，该文件应**直接升到第一行**，且两条 `score` 仍相同（可用 `swift run SwiftSeekSearch <query>` 核对）
4. 不同 score 回归：输入一条只命中文件名 vs 只命中路径的多词 query；把命中路径的那条频繁打开 → 再次搜索，命中文件名（高 score）的那条**不应被挤下去**。验证"high-usage 低分不压过 高分零usage"。
5. 列头排序：
   - 点 `打开次数` 列头 — 第一次默认升序（sortDescriptorPrototype.ascending=true）；再点切降序；观察 `—` 的行聚在一侧
   - 点 `最近打开` 列头 — 同上
   - 关闭搜索窗再重开：上次选择的排序键应恢复（F3 持久化路径 + H2 新键）
6. 列宽持久化：
   - 拖动 `打开次数` / `最近打开` 列宽；关搜索窗再开，宽度应保留
   - 可核 `sqlite3 ~/Library/Application\ Support/SwiftSeek/swiftseek.sqlite3 "SELECT key,value FROM settings WHERE key LIKE 'result_col_width_%';"` 能看到两个新 key
7. 既有排序不回退：点 `名称` / `路径` / `修改时间` / `大小` 列头，排序依然按这些键（与 F3 一致），不应被 usage 打乱。

### 33j. H3 recent: / frequent: 入口
前置：通过 33h/33i 已确认 `file_usage` 在 `.open` 后累加。先打开几个不同的文件（至少 3 个，其中两个多开几次）。

1. 搜索窗输入 `recent:`（带冒号的裸 token），回车。结果应按最近打开时间倒序排列；从未打开过的文件不应出现。
2. 输入 `frequent:`。结果应按打开次数倒序排列。对比 sqlite3：
   ```bash
   sqlite3 ~/Library/Application\ Support/SwiftSeek/swiftseek.sqlite3 \
     "SELECT f.path, u.open_count, u.last_opened_at FROM file_usage u JOIN files f ON f.id = u.file_id ORDER BY u.open_count DESC LIMIT 10;"
   ```
   顺序应一致。
3. 组合 filter：`recent: ext:md` 只返回 .md 文件中最近打开的；`frequent: path:Documents` 只返回路径含 Documents 段的高频文件。
4. plain token 组合：`recent: todo` 只返回最近打开且 name 含 "todo" 的文件。
5. 边界：同时写 `recent: frequent:` — 首个赢（mode=.recent），第二个被忽略，行为不报错。
6. 非 mode 形式不被误识别：
   - `recent:foo` 不是 mode 开关；应当作字面 token 处理（普通搜索路径，不走 file_usage）
   - 只有 **空 value 的裸** `recent:` / `frequent:` 才是 mode 开关
7. 普通 query 不被污染：输入 `todo`（无 `recent:` 前缀）应返回 name 含 todo 的所有文件，不只返回已打开过的（这点和 H2 tie-break 不冲突 — 高 usage 项仅在同 score 下靠前）。

### 33k. H4 使用历史隐私控制
前置：通过 33h-33j 已确认 `file_usage` 运作。

1. 设置 → 维护 tab → 滚动到最下方，应看到 "使用历史" 段：
   - 复选框 `记录通过 SwiftSeek 打开的次数（Run Count / 最近打开）`
   - 按钮 `清空使用历史…`
   - 说明文字：`当前记录 N 条 .open 历史（file_usage 表）`
2. 开关关闭测试：
   - 取消复选框勾选。核 sqlite3：
     ```bash
     sqlite3 ~/Library/Application\ Support/SwiftSeek/swiftseek.sqlite3 \
       "SELECT value FROM settings WHERE key='usage_history_enabled';"
     ```
     应返回 `0`
   - 搜索窗打开任一文件；再次核 `file_usage` 对应行 `open_count` 不应增加（观察前后差）
   - Console 应有 `SwiftSeek: recordOpen skipped, usage history disabled: ...` 日志
3. 重新勾选复选框；`usage_history_enabled=1`。打开文件，`open_count` 恢复累加。
4. 清空测试：
   - 点 `清空使用历史…` → 弹二次确认窗，说明效果和不可撤销；点 `清空`
   - 维护 tab 状态栏显示 "使用历史已清空，移除 N 条记录"
   - DB 体积 stats 区 `file_usage` 行数变为 0
   - 搜索窗 `recent:` / `frequent:` 立即返回空
   - 已有搜索结果的"打开次数"列全显示 `—`、"最近打开"列全显示 `—`
5. 边界：
   - 清空后复选框**不应**被改动（清空仅清数据，不改开关）
   - `file_usage` 为空时 `清空使用历史…` 按钮 disabled（无意义）
6. CLI 核对：`./.build/release/SwiftSeekDBStats` 输出里有 `file_usage : N` 一行

### 33l. H5 usage benchmark
前置：release 构建已存在（`./scripts/build.sh` 或等价）。

1. 基本自检：`./.build/release/SwiftSeekBench --mode compact --files 2000 --iters 5 --usage-rows 500` 应在 1 秒内完成且输出包含：
   - `H5 usage_rows=500`
   - `recent:-med=...`
   - `frequent:-med=...`
   - `recordOpen-med=...`
2. 100k 回归：`./.build/release/SwiftSeekBench --mode compact --files 100000 --iters 20 --usage-rows 10000 --record-open-ops 500`（约 1 分钟）。结果应与 `docs/everything_usage_bench.md` 的 100k 表同量级：
   - 3+char (w/usage) median 与空 usage 持平（JOIN 开销 <1ms）
   - `recent:` / `frequent:` 都是 sub-10ms 中位数
   - `recordOpen` sub-ms
3. 500k 全量回归：`--files 500000 --usage-rows 100000`（约 4-5 分钟）。数值量级参考 `docs/everything_usage_bench.md` 的 500k 表。
4. 回归兼容：不传 `--usage-rows` 时 bench 输出与 G5 格式完全相同（不打印 H5 段），确认不破坏既有自动化脚本。
5. 文档对齐：bench 结果明显偏离 `docs/everything_usage_bench.md` 时，应以新数据更新文档而非忽略差异。

### 33m. J1 设置窗口生命周期 + Dock reopen
前置：release 或 debug 构建 + `.app` bundle 更新过。

1. 启动 SwiftSeek；设置窗口应自动出现（`applicationDidFinishLaunching` 末尾 `showSettings(nil)`）。
2. 点设置窗口左上角红色 × 按钮关闭；窗口应消失但 App 仍在（Dock 图标保留，菜单栏图标保留）。
3. 从菜单栏 SwiftSeek 图标 → "设置…"，应重新打开同一个设置窗口（不是新建，位置/tab 与关闭前一致）。
4. 再次关闭 → 菜单栏主菜单 `SwiftSeek → 设置…`（⌘,），应重新打开。
5. 再次关闭 → 关闭搜索窗口（按 ⌥Space 开/关或 ESC 隐藏）→ 现在无可见窗口 → 单击 Dock 图标 → 应重新打开设置窗口（`applicationShouldHandleReopen`）。
6. 压力：重复 "× 关闭 → 菜单栏'设置…'打开" 10 次，观察：
   - 不崩溃
   - 每次都能重开
   - 菜单入口未失效
7. 搜索窗回归：
   - 按 ⌥Space 或主菜单 `SwiftSeek → 搜索…` 呼出搜索窗
   - ESC 隐藏、失焦隐藏（点其它 App 窗口）都应正常
   - 搜索窗关闭不影响设置窗口独立生命周期
8. sqlite 层无新增字段（J1 纯 UI），可用 `./.build/release/SwiftSeekStartup` 核 schema=6 不变。

### 33n. J2 Run Count / 最近打开 可见性
前置：已经用 J1 刷过 `.app` bundle（带 hide-only close 修复），或直接 `./scripts/build.sh` + 复制 binary。

1. **首次启动** 搜索窗默认宽度应约 1020px（而不是旧的 680px），6 列都可见：名称 / 路径 / 修改时间 / 大小 / **打开次数** / **最近打开**。
2. **header tooltip**：鼠标悬停"打开次数"列头 2-3 秒，应显示 tooltip："通过 SwiftSeek 成功打开该文件的次数（Run Count）。不包含 Reveal in Finder / Copy Path，不代表 macOS 全局启动次数。"「最近打开」同理。
3. **Run Count 累加**：搜索任一已索引文件 → 回车打开 3 次（每次回车后窗口收起再 ⌥Space 重开搜索同一 query）。应看到"打开次数"列显示 3（或累加后的当前值）。sqlite3 核对：
   ```bash
   sqlite3 ~/Library/Application\ Support/SwiftSeek/swiftseek.sqlite3 \
     "SELECT f.path, u.open_count, u.last_opened_at FROM file_usage u JOIN files f ON f.id = u.file_id ORDER BY u.last_opened_at DESC LIMIT 5;"
   ```
4. **最近打开**：上一步同文件，"最近打开"应显示类似"刚刚"/"1 分钟前"（和"修改时间"格式一致）。
5. **空值**：从未通过 SwiftSeek 打开过的文件，"打开次数"列显示 `—`，"最近打开"显示 `—`。
6. **列宽恢复**：手动把"打开次数"列宽拖到 20px 左右（几乎不可见）→ 关窗再开（窄宽应持久化）。右键"打开次数" / "最近打开" / 任一列的 header → 菜单出现"重置列宽" → 点击后列宽应立即恢复默认，窗口过窄时自动拉宽。状态栏显示"✓ 已重置列宽"toast。
7. **持久化不误伤排序**：点"打开次数"列头按 usage 排序；然后右键 header → 重置列宽 → 排序顺序应不变（J2 只清列宽，不碰 `result_sort_key`）。
8. **`recent:` / `frequent:`**：
   - 输入 `recent:` 回车，结果第一行应是刚才累计打开次数最多/最近的文件，"打开次数"列值与显示顺序一致
   - 输入 `frequent:`，同理
9. **panel resize 持久化**：手动把搜索面板拖到 1200×500 → 关闭 → ⌥Space 重开 → 尺寸应恢复 1200×500（由 `setFrameAutosaveName` 生效）。
10. **用户使用旧 .app**：如果用户看不到 Run Count，优先确认 Dock 里的 SwiftSeek.app 是最新构建（`ls -lT SwiftSeek.app/Contents/MacOS/SwiftSeek` 的 mtime）；可能是老 bundle。

### 33o. J3 查询语法：wildcard / phrase / OR / NOT
前置：已用 J3 刷过 `.app` bundle；DB 有若干已索引文件（任意两个同名基础词不同扩展的文件即可）。

1. **wildcard `*`**：输入 `alph*`，应命中所有 name 以 "alph" 开头的文件（alpha.md, alphabet.txt, …）。
2. **wildcard `?`**：输入 `f?o`，应命中 name 含 "foo"/"fao"/"fbo" 等单字符 + "o"。
3. **phrase** `"foo bar"`：输入带双引号 → 只命中 name 或 path 中含字面 `foo bar`（中间有空格）的文件。`fooxbar.md` 不应命中。
4. **OR**：输入 `alpha|beta` → 命中含 alpha 或 beta 的文件（union）。
5. **NOT**：输入 `proj -alpha` → 命中路径含 proj 但 name/path 不含 alpha 的文件。
6. **NOT phrase**：输入 `notes !"foo bar"` → 命中 path 含 notes 但不含字面 `foo bar` 的文件。
7. **组合**：`recent: ext:md *ta*` → 最近打开的 .md 文件中 name 含 "ta"（`*` 包住）。
8. **filter 保护**：输入 `foo|ext:md` 应**不**按 OR 处理（right side 是 filter key），而是按字面 `foo|ext:md` 做 substring（大概率 0 结果；测试语义即可）。
9. **容错**：
   - `"foo bar`（未闭合引号）应自动补齐、不崩
   - `|` 单独输入应当字面处理
   - `*` 单独输入应当回落到 bounded scan（最多返回 LIMIT 条）
   - `!`、`-` 单独输入应忽略
10. **CLI 一致**：用同一 query 跑 `./.build/release/SwiftSeekSearch "alpha|beta"`，结果集应与 GUI 搜索窗一致（注意 GUI 按相关性默认排序 + H2 tie-break，CLI 排序按 SearchEngine 默认）。
11. **不回归**：`ext:md` / `kind:file` / `path:docs` / `recent:` / `frequent:` 与 H2 tie-break / J2 列可见性与 J1 生命周期均应不变。

### 33p. J4 搜索历史与 Saved Filters
前置：J4 .app bundle 已更新。若用户有老 DB 可能需触发 migration v6→v7；启动即走。

1. **首次启动**：主搜索窗底部动作栏应多一个 "最近/收藏" 按钮；点击弹出 NSMenu。
2. **菜单初始**：空 DB 下显示 "（暂无最近查询）" + "（暂无已保存过滤器）" + 启用 "保存当前查询…"（若搜索框非空） + "清空搜索历史…"（禁用，因为无数据）。
3. **记录历史**：在搜索框输入 `alpha`，上下移动选中某行，Enter 打开。再次点 "最近/收藏"，应看到 🕒 alpha 条目。
4. **顺序**：重复搜索 `beta` 并打开、再 `gamma` 并打开。再点菜单，应按 last_used_at DESC：gamma / beta / alpha。点 gamma 应把搜索框填为 gamma 并自动重新搜索。
5. **重复不膨胀**：重复打开 alpha 3 次，`sqlite3 ... "SELECT query, use_count FROM query_history"` 应看到 `alpha | 3+`（use_count 累计，不是多条 row）。
6. **保存**：输入 `ext:md recent:`，点菜单 → "保存当前查询…"，输入名字 `本周未读 md` → 保存。菜单再次打开应看到 ★ 本周未读 md；点击后搜索框填 `ext:md recent:`。
7. **隐私开关**：设置 → 维护 tab → 滚到最下 → "搜索历史与 Saved Filters" → 取消勾选 "记录我在 SwiftSeek 里打开文件时使用的查询"。继续做搜索 + 打开，`query_history` 行数不应增加。Console 可看到 "recordQueryHistory skipped, query history disabled: ..." 日志。
8. **重新勾选**：勾选 → 做 open → 行数恢复累加。
9. **清空**：维护 tab "清空搜索历史…" → 二次确认 → 状态栏显示清空行数。点菜单 → 🕒 列空。Saved Filters **不受影响**。
10. **Saved Filter 管理**：维护 tab → 下拉可选已有 filters → "新建 Saved Filter…" 弹双栏对话框 → 保存 → 下拉出现新条目。点"删除所选…"二次确认 → 条目消失。
11. **同名覆盖**：新建同名 Saved Filter → 下拉仍只一条（name PK，UPSERT）；点看 query 已更新为新值。
12. **本地隐私**：DB 位置 `~/Library/Application Support/SwiftSeek/swiftseek.sqlite3`，两表与隐私开关全部在本地。`grep` 项目源没有任何上传 / 网络调用。

### 33q. J5 上下文菜单增强
前置：J5 `.app` bundle 已刷；结果列表有至少一个索引命中。

1. **菜单层次**：在结果行右键，菜单应按顺序：
   - 打开
   - 使用其他应用打开…
   - 在 Finder 中显示
   - —
   - 复制名称
   - 复制完整路径
   - 复制所在文件夹路径
   - —
   - 移到废纸篓
2. **打开** → 同原行为，成功累加 `file_usage.open_count`。
3. **使用其他应用打开…** → 弹 NSOpenPanel（起始目录 `/Applications`，只允许 `.app`）。选 TextEdit（或别的）→ 文件应由该应用打开。`file_usage.open_count` **不变**。Console 无报错。
4. **在 Finder 中显示** → Finder 弹窗选中该文件；`file_usage.open_count` 不变。
5. **复制名称** → 剪贴板应等于文件基本名（含扩展名）。用 `pbpaste` 核对。
6. **复制完整路径** → 剪贴板等于 `SearchResult.path` 全路径。
7. **复制所在文件夹路径** → 剪贴板等于 parent 目录（去掉最后一段）。例如 `/Users/x/foo/bar.md` → `/Users/x/foo`。
8. **移到废纸篓**：
   - 二次确认弹窗，显示"移到废纸篓？"+ 文件名 + 完整路径
   - 点"取消" → 无动作
   - 点"移到废纸篓" → 文件消失到废纸篓，状态栏显示"✓ 已移到废纸篓"
   - 文件不存在时（先 rm）应 toast 失败原因
9. **Run Count 隔离回归**：连续触发 Reveal / 复制 × 各类 / Open With / 移到废纸篓（前 3 个对非破坏性）；`file_usage.open_count` 应**只**因第 2 步的"打开"累加。sqlite3 核。
10. **快捷键回归**：⌘⏎ Reveal、⌘⇧C 复制路径等原有快捷键仍正常（主菜单 / 按钮 selector 不变）。

### 33r. J6 首次使用 / Launch at Login / 窗口状态记忆
前置：J6 `.app` bundle 已刷。

1. **首次使用 banner（roots 空）**：新 DB 启动（或删除现有 roots 直到列表为空），设置窗口顶部 banner 应包含 4 行提示：先加 root、macOS 权限、索引模式说明、Run Count 语义、⌥Space 快捷键。添加至少一个 root 后 banner 消失。
2. **设置窗口尺寸记忆**：拖大设置窗口到 900×700 → 关 → 重开，尺寸应保留。
3. **搜索窗口尺寸记忆（回归 J2）**：拖搜索面板到 1200×500 → 关 → ⌥Space 重开，尺寸应保留。
4. **tab 选中记忆**：设置窗口切到"维护"tab → 关 → 重开应直接在"维护"。切回"常规" → 关 → 重开在"常规"。sqlite3 核 `SELECT value FROM settings WHERE key='settings_tab_index';`。
5. **Launch at Login (macOS 13+)**：
   - 设置 → 常规 tab 最底部应有 "随 macOS 登录自动启动 SwiftSeek" 复选框
   - 说明文字明确调用 SMAppService 且未签名可能需批准
   - 勾选：如成功，note 改 "✓ 已注册为登录项；下次登录会自动启动…"；`settings.launch_at_login_requested = 1`
   - 如失败（常见于 `.build` 直跑）：弹 NSAlert 显示真实错误 + 未签名 / 未公证 / 需手动批准等可能原因；复选框恢复 off；DB 不持久化意图
   - 取消勾选 → 调用 `SMAppService.mainApp.unregister()` → note 改 "未启用"
   - 系统设置 → 通用 → 登录项 查实际状态
6. **低版本 macOS**（< 13）：复选框 disabled，note 显示"当前系统不支持 SMAppService"
7. **状态同步**：手动到 系统设置 → 通用 → 登录项 关掉 SwiftSeek，回到 Settings 常规 tab note 应下次 `viewWillAppear` 时反映为 false；再勾可重注册
8. **持久化不相互干扰**：J2 列宽/F3 排序/J6 tab/窗口 frame 各走不同键；执行 J2 "重置列宽" 不该影响 tab/frame；执行 J6 切 tab 不影响列宽

### 33s. K1 设置窗口 release gate + build identity
前置：用 K1 构建过的 `.app`（Info.plist 含 `GitCommit` / `BuildDate`），或直接 `swift run SwiftSeek`（fallback "dev" 标识）。

#### Build identity
1. **启动日志三连**（Console.app 过滤 SwiftSeek，或 `tail -f` 重定向）应包含按顺序：
   - `SwiftSeek: SwiftSeek <version> commit=<hash> build=<date>`
   - `SwiftSeek: bundle=<path>`
   - `SwiftSeek: binary=<path>`
   - 然后才是 `database ready at ... schema=N`
2. **About 面板**（设置 → 关于）应显示：
   - 标题下方一行 summary：`SwiftSeek <version> commit=<hash> build=<date>`
   - 诊断块顶端有 build identity 五行（版本 / commit / build date / bundle / binary）
   - 然后才是 DB / roots / files 等业务诊断
3. **复制诊断信息**按钮：点击后 `pbpaste` 应得到完整诊断文本（含 build identity）。
4. **Stale bundle 自检**：对比 About 显示的 `binary=` 路径与 `which SwiftSeek` / Activity Monitor 中的进程路径；不匹配说明跑的是旧 bundle。

#### 设置窗口 release gate（每次 release 必跑）
1. 启动 App，设置窗口自动出现。
2. **× 关闭 → 菜单栏 SwiftSeek 图标 → 设置…**：必须重开同一窗口（J1 hide-only + applicationShouldHandleReopen 路径）。
3. **× 关闭 → 主菜单 SwiftSeek → 设置…**（⌘,）：必须重开。
4. **× 关闭 → 隐藏搜索窗（ESC）→ 点 Dock 图标**：无可见窗口时点 Dock 必须重开设置（applicationShouldHandleReopen）。
5. **压力 10 次**：×关 → 菜单栏重开，循环 10 次，不崩溃、不丢 controller、菜单入口不失效。
6. **设置 tab 切换 20 次**：常规 / 索引范围 / 维护 / 关于 之间反复切；不崩溃，KVO 正常持久化（关窗重开应停在最后切到的 tab）。
7. **搜索窗回归**：⌥Space 呼出搜索窗，ESC / 失焦隐藏，再 ⌥Space 呼出 — 行为应与 J1 前一致。

#### 失败处置
- 任何步骤无反应 → 看 Console SwiftSeek 日志：可能 `tabView.delegate` 非法重置（J6 hotfix 应避免）或 windowShouldClose 未实现 hide-only。
- 复制按钮粘贴为空 → 检查 NSPasteboard 调用点未异常。
- 启动日志缺 `SwiftSeek: SwiftSeek ... commit=...` → AppDelegate 未调 `BuildInfo.summary`。

### 33t. K2 可重复 .app 打包流水线
前置：fresh git clone（或干净工作目录）；macOS 13+；CLT 或 Xcode 已装。

#### 一条命令打包
1. `cd <repo>`
2. `./scripts/package-app.sh`
   - 输出末尾应有 `=== done ===` + bundle 路径 `dist/SwiftSeek.app`
   - `plutil -lint` 必须 `OK`
   - `codesign -dv` 必须显示 `Signature=adhoc` + `TeamIdentifier=not set`

#### bundle 结构验证
```bash
find dist/SwiftSeek.app -maxdepth 4 -type f -o -type d
```
应有：
- `dist/SwiftSeek.app/Contents/Info.plist`
- `dist/SwiftSeek.app/Contents/MacOS/SwiftSeek` （可执行）
- `dist/SwiftSeek.app/Contents/Resources/AppIcon.icns`
- `dist/SwiftSeek.app/Contents/_CodeSignature/CodeResources`

#### Info.plist 字段验证
```bash
plutil -p dist/SwiftSeek.app/Contents/Info.plist
```
应含：
- `CFBundleIdentifier` = `com.local.swiftseek`
- `CFBundleShortVersionString` = `1.0-K2`（脚本默认；可 `SWIFTSEEK_APP_VERSION=...` 覆盖）
- `GitCommit` = 当前 `git rev-parse --short HEAD`
- `BuildDate` = 打包当天日期
- `CFBundleIconFile` = `AppIcon`

#### codesign 验证
```bash
codesign -dv --verbose=2 dist/SwiftSeek.app
```
- `Format=app bundle with Mach-O`
- `Signature=adhoc`
- `Sealed Resources version=2`

#### GUI 启动 + build identity 自检
1. `open dist/SwiftSeek.app` 启动（Gatekeeper 拦截 → 右键 → 打开）
2. Console.app 过滤 SwiftSeek，启动头三行应为：
   ```
   SwiftSeek: SwiftSeek 1.0-K2 commit=<hash> build=<date>
   SwiftSeek: bundle=/<...>/dist/SwiftSeek.app
   SwiftSeek: binary=/<...>/dist/SwiftSeek.app/Contents/MacOS/SwiftSeek
   ```
3. 设置 → 关于 → 顶部 summary 应与启动日志一致；诊断块 `bundle:` / `binary:` 行指向 `dist/SwiftSeek.app`
4. 点 "复制诊断信息" → `pbpaste` 应得到完整诊断（含 build identity）

#### 重复打包验证（每次 wipe + 重建）
1. 改一行注释 commit 一次
2. 再跑 `./scripts/package-app.sh`
3. About → 顶部 commit 哈希应变成新值
4. `dist/SwiftSeek.app/Contents/Info.plist` 的 `GitCommit` 同步更新

#### J1/J6 lifecycle 不回退（K1 release gate 复用）
按 §33s 步骤跑 — 设置窗 × 关 → 菜单栏 / 主菜单 / Dock 三路径重开 + 10× 压力 + 20× tab 切换。

### 33u. K3 完整诊断 + bug-report 模板
前置：K2 `dist/SwiftSeek.app` 已生成；启动可见 build identity。

#### About 面板字段验证
1. 设置 → 关于 → 顶部 summary `SwiftSeek <ver> commit=<hash> build=<date>`
2. 诊断块按顺序应有：
   - **build identity**：版本 / commit / build date / bundle / binary 5 行
   - **数据库**：DB 路径 + schema 版本 + main/wal/shm 大小
   - **行数**：files / file_usage / query_history / saved_filters
   - **配置**：索引模式 / 隐藏文件 / usage 开关 / query 开关
   - **roots / excludes**：总 / 启用计数
   - **Launch at Login**：用户意图 + 系统状态（"已注册"/"未注册"）
   - **last rebuild**：时间 / 结果 / 摘要

#### "复制诊断信息" 按钮
3. 点 "复制诊断信息" → `pbpaste` 粘贴 → 文本应包含上述全部字段，可直接贴到 GitHub issue 而不需要补充。

#### 与 SwiftSeekDBStats 口径一致
4. 命令行核对：
   ```bash
   ./.build/release/SwiftSeekDBStats
   ```
   `files` / `file_usage` / `main DB size` 等数字应与 About 一致（同一时刻测量；增量索引中可能轻微漂移）。

#### 启动日志校验
5. Console.app 过滤 SwiftSeek 启动头几行：
   - `SwiftSeek: SwiftSeek <ver> commit=<hash> build=<date>`
   - `SwiftSeek: bundle=<...>`
   - `SwiftSeek: binary=<...>`
   - `SwiftSeek: database ready at <...> schema=<N>`

#### Bug-report 模板
用户反馈问题时**必须**附：
- "复制诊断信息" 输出的整段（含 build identity + schema + 行数 + LAL 状态）
- 复现步骤
- 是否在系统设置 → 通用 → 登录项 / 隐私与安全性 → 完全磁盘访问 中给过 SwiftSeek 权限
- macOS 版本（`sw_vers -productVersion`）

#### J1/J6 lifecycle 不回退（K1 release gate 复用）
按 §33s 步骤跑 — 设置窗 × 关 → 三路径重开 + 10× 压力 + 20× tab 切换。
按 §33t 步骤验证 K2 package-app.sh 仍能 fresh 跑通。

### 33v. K4 安装 / 升级 / 回滚 dry-run
前置：fresh git clone 或干净工作目录；可写 `/Applications`（管理员或 sudo 可豁免）。

#### 安装 dry-run
1. `./scripts/package-app.sh` 完成
2. `cp -R dist/SwiftSeek.app /Applications/`
3. **首次打开 Gatekeeper 路径之一**：
   - Finder 右键 SwiftSeek.app → 打开 → 弹窗点 "打开"
   - 或系统设置 → 隐私与安全性 → "仍要打开"
   - 或 CLI `open /Applications/SwiftSeek.app`
4. 设置 → 关于 → 顶部 summary 应显示当前 commit；`bundle:` 行应是 `/Applications/SwiftSeek.app`
5. 启动日志（Console.app SwiftSeek 过滤）三连匹配

#### 升级 dry-run
1. `pkill -f SwiftSeek` → `pgrep -fl SwiftSeek` 应空
2. 改一行注释 + commit
3. `./scripts/package-app.sh` 重打包（commit hash 应跟随 git）
4. `rm -rf /Applications/SwiftSeek.app && cp -R dist/SwiftSeek.app /Applications/`
5. `open /Applications/SwiftSeek.app`
6. 关于 → commit 应是新 hash；启动日志同步

#### 回滚 dry-run（不真删数据）
1. 升级前重命名旧版：`mv /Applications/SwiftSeek.app /Applications/SwiftSeek-prev.app`
2. 安装新版（按上面 install dry-run）
3. 备份 DB：`cp ~/Library/Application\ Support/SwiftSeek/index.sqlite3{,.bak}`
4. 模拟回滚：`pkill -f SwiftSeek && rm -rf /Applications/SwiftSeek.app && mv /Applications/SwiftSeek-prev.app /Applications/SwiftSeek.app && open /Applications/SwiftSeek.app`
5. 关于 → commit 应回到旧值
6. 如旧 binary 启动出错（schema 太新），按 install.md 步骤删 DB 让其重建

#### Launch at Login 双视角验证
1. 设置 → 常规 → 滚到底 "随 macOS 登录自动启动 SwiftSeek"
2. 勾选：note 应反映系统状态（"已注册" / "未注册"），不应假装成功
3. 系统设置 → 通用 → 登录项 中应能看到 SwiftSeek（或 Codex sandbox 限制下显示需批准）
4. 取消勾选 → note 显示 "未启用"
5. 设置 → 关于 → 复制诊断信息 → 文本应有：
   - `Launch at Login 用户意图：已勾选 / 未勾选`
   - `Launch at Login 系统状态：已注册（...）/ 未注册（...）/ —（headless / unsupported）`
   - 两面状态一致或有清楚解释

#### 多实例 / stale bundle 自检
1. 同时安装 `dist/` 和 `/Applications/` 两份；确认它们分别启动后 About 显示不同 `bundle:` 行
2. 修改源码 + commit，重新 `package-app.sh`，但不替换 `/Applications/SwiftSeek.app`
3. 启动 `/Applications/SwiftSeek.app` → About commit 应是旧 hash（说明这是 stale bundle）
4. 替换后重启 → About commit 应是新 hash

#### J1/J6/K1/K2/K3 不回退（K4 release gate 复用）
- 按 §33s 跑设置窗口生命周期
- 按 §33t 跑 K2 package-app.sh 流程
- 按 §33u 跑 K3 完整诊断字段

### 33w. K5 root 权限 / FDA / recheck 状态矩阵

K5 把 root 不可访问拆成四种显式状态。手测时按矩阵走，每项都要在 设置 → 索引 的 roots 表里看到对应徽标 + tooltip。

#### 准备
- 启动一遍 SwiftSeek（用 §33t 打的 `dist/SwiftSeek.app`）
- 设置 → 索引 → 看到 roots 表底栏新增两个按钮：**"重新检查权限"** 与 **"打开完全磁盘访问设置"**

#### 状态 1：✅ 就绪（基线）
1. 添加一个普通可读目录作为 root（例：`mkdir /tmp/k5-ready && touch /tmp/k5-ready/a.txt` 然后从 UI 添加 `/tmp/k5-ready`）
2. 等"索引中"消失 → 行徽标变 `✅ 就绪`
3. 鼠标悬停该行 → tooltip 出现"可读且已纳入索引"或类似肯定描述
4. 检查诊断（设置 → 关于 → 复制诊断信息）`roots 健康（K5）：` 段有这一行

#### 状态 2：🔌 路径不存在（offline）
1. `mkdir /tmp/k5-gone && open /tmp/k5-gone`
2. 在 UI 添加 `/tmp/k5-gone`，等"索引中"消失变 ✅ 就绪
3. `rm -rf /tmp/k5-gone`
4. 在 UI 点 **"重新检查权限"**
5. 验证：行徽标变 `🔌 路径不存在`，tooltip 含"目录不存在"或等价表述
6. 验证：诊断里同步出现 `🔌 路径不存在  /tmp/k5-gone  — ...`

#### 状态 3：💾 卷未挂载（volumeOffline）
1. 准备一个外接盘 `/Volumes/MyDrive`（U 盘 / 硬盘 / DMG mount 都行）
2. 在外接盘上 `mkdir /Volumes/MyDrive/k5-vol`
3. 在 UI 添加 `/Volumes/MyDrive/k5-vol`，等 ✅ 就绪
4. **退出外接盘**（Finder 推出 / `umount /Volumes/MyDrive` / 物理拔掉）
5. 在 UI 点 **"重新检查权限"**
6. 验证：行徽标变 `💾 卷未挂载`，tooltip 提到"卷 /Volumes/MyDrive 当前未挂载"或等价
7. 重新连接 / 挂载该外接盘 → 再点 "重新检查权限" → 行恢复 `✅ 就绪`
8. **关键边界**：这一项不能与 `🔌 路径不存在` 混淆。如果你看到 `/Volumes/X/...` 路径显示"路径不存在"而不是"卷未挂载"，说明回归。

#### 状态 4：⚠️ 无访问权限（unavailable）
方案 A — 通过权限位制造（最快）：
1. `mkdir /tmp/k5-locked && touch /tmp/k5-locked/x.txt`
2. UI 添加 `/tmp/k5-locked`，等 ✅ 就绪
3. `chmod 000 /tmp/k5-locked`
4. UI 点 "重新检查权限"
5. 验证：行徽标变 `⚠️ 无访问权限`，tooltip 含"权限不允许读取"或"Full Disk Access"提示
6. `chmod 700 /tmp/k5-locked` → 再点 "重新检查权限" → 恢复 ✅ 就绪

方案 B — 通过 Full Disk Access（更贴近真实场景）：
1. 系统设置 → 隐私与安全性 → 完全磁盘访问 → 移除 SwiftSeek（如已加入）或确认未加入
2. UI 添加 `~/Desktop` 或 `~/Documents` 作为 root
3. 验证：行徽标 `⚠️ 无访问权限`，tooltip 提示可能需要 FDA
4. UI 点 **"打开完全磁盘访问设置"** → 系统设置应跳到 完全磁盘访问 面板
5. 加入 SwiftSeek.app 并打开开关
6. 回 SwiftSeek，UI 点 **"重新检查权限"**
7. 验证：行恢复 ✅ 就绪

#### 状态 5：⏸ 已停用（paused，覆盖 disk state）
1. 用任何上述失败状态的 root（`/tmp/k5-locked` chmod 000 时最直观）
2. 选中该行，点 "启用/停用所选" 把它停用
3. 验证：行徽标变成 `⏸ 已停用`，**不**显示 `⚠️` / `🔌` / `💾`，因为 paused 覆盖磁盘状态
4. 再次点 "启用/停用所选" 启用 → 徽标回到对应磁盘状态

#### 按钮 fallback 测试
1. 在虚拟机或较旧的 macOS 上点 **"打开完全磁盘访问设置"**
2. 如果 deep-link URL 失败 → 应自动回退到通用隐私面板
3. 如果两个都失败 → 应弹 NSAlert 给出手动路径"系统设置 → 隐私与安全性 → 完全磁盘访问"

#### 诊断同源校验
1. 在每个状态变化后，点 设置 → 关于 → "复制诊断信息"
2. 粘贴到文本编辑器，检查 `roots 健康（K5）：` 段
3. 每行格式：`  <徽标>  <路径>  — <detail>`
4. UI 显示什么徽标，诊断就该是什么徽标 — 三处口径必须一致

#### J1/J6/K1/K2/K3/K4 不回退（K5 release gate 复用）
- §33s 设置窗口生命周期
- §33t K2 package-app.sh 流程
- §33u K3 完整诊断字段
- §33v K4 安装 / 升级 / 回滚 dry-run

### 33x. K6 Release QA 收口入口

K6 把上面所有阶段（J1 / J6 / K1-K5）整合成一条单页 release gate。每次发布**必须**走 [docs/release_checklist.md](release_checklist.md) 的 15 步全绿，再用 [docs/release_notes_template.md](release_notes_template.md) 复制成本次发布说明。

#### 关键约束
- 任何一项失败 = 不发布。修复 → 从第 1 步重跑。
- release notes "已知边界" 段不可删除（ad-hoc / 无 Developer ID / 无 notarization / 无 DMG / 无 auto updater / FDA / 外接盘）。
- §33s-§33w 都是本 gate 的子项，被 release_checklist.md 显式引用。

#### 干净 workspace 验证（必跑）
```bash
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox
plutil -lint dist/SwiftSeek.app/Contents/Info.plist
codesign -dv --verbose=2 dist/SwiftSeek.app
```
- 任一命令失败 → 标记本次 release ❌
- SmokeTest 当前基线 209/209，不应回退

#### 文档一致性
- README "当前限制" 提到 K6 + 链 release_checklist.md / release_notes_template.md
- known_issues.md §9 写明 K6 已落地
- architecture.md 末尾"everything-productization 收口（K1-K6）"段与代码一致
- install.md 与 release checklist 第 13 步描述不矛盾

### 33. 已知限制文档对照
手动与 [docs/known_issues.md](known_issues.md) 对照一遍：
- macOS 13+ 要求
- 无 Xcode.app 时的 SwiftPM 路径
- Gatekeeper 首次拦截处理
- 沙箱下 env 前缀要求
- FSEvents 沙箱限制
- disable/enable/remove root 语义
- exclude 立即清理语义
- 隐藏文件定义
- 热键冲突兜底
- 日志定位方式

所有条目都应该匹配当前真实实现，不存在未落地的承诺。
