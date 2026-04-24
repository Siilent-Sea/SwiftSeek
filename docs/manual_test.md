# SwiftSeek 手工测试（baseline + 所有归档轨道）

> Note:
> 这份文档覆盖 P0-P6、E1-E5、F1-F5 已落地能力的手工验证。
> 当前活跃轨道是 `everything-footprint`，阶段 G1 起的 DB 体积 / 维护要求以 `docs/everything_footprint_taskbook.md` 为准；G1 手测见 §33f。
> 历史性能轨道 benchmark 仍可参考 `docs/everything_performance_taskbook.md`（已归档）。

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
Smoke total: 98  pass: 98  fail: 0
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
