# Schema v5 / Compact index 设计 Proposal（G2）

本文件是 `everything-footprint` 轨道 G2 阶段的输出。**只是设计，不包含代码**。G3 根据本文件真实实现；G4 做 UI；G5 做 500k 规模验证。

如果读到本文时发现与 HEAD 代码不一致，以 HEAD 代码为准 —— 本文件是 G2 固化的设计意图，实现细节可能在 G3 根据实测调整。

---

## 1. 当前 (v4) 状态回顾

- `file_grams`：3-gram 倒排，来源是 `nameLower ∪ pathLower` 的滑窗 union
- `file_bigrams`：2-gram 倒排，同样来源
- 每个文件的索引贡献 ≈ `len(name_lower) - 1 + len(path_lower) - 1` 个 bigram + `len(name_lower) - 2 + len(path_lower) - 2` 个 trigram，每条 gram 是一个 `(file_id, gram)` 行
- **核心问题**：full path 被整段做滑窗。一个文件典型 path 长度 80-150 字符，gram 行数 200-300；500k 文件 × 250 gram ≈ 1.25 亿行。主库加 WAL 容易到数 GB。

用户实测：500k 文件 → main 3.4 GB + WAL 1.3 GB。

---

## 2. 设计目标（v5）

1. **典型库体积减半或更多**。目标 500k 文件下 main ≤ ~1.5 GB。
2. **大部分查询语义不变**。用户日常 query（文件名 / 常见 token / ext 过滤）不回退。
3. **一种明确的能力换体积 tradeoff**：对 full-path substring 搜索的极端场景（例如在路径中间搜索随机片段）明确允许"高级模式"；默认模式不承诺。
4. **迁移路径可控**：不强制一次性全量重建，不在启动主线程做长事务。
5. **可回滚**：v4 数据仍在，不删除，用户可手动切回 full-path mode。

---

## 3. Compact mode 索引策略

Compact mode 是 G3 引入的默认模式。基本想法：**只对 basename 做 gram，不对 full path 整段滑窗**；path 另建一个 per-segment 表用于 `path:` 过滤和按路径定位。

### 3.1 新表（Compact）

| 表 | 内容 | 用途 |
|-----|-------|------|
| `file_name_grams` (file_id, gram, PRIMARY KEY(file_id, gram) WITHOUT ROWID) | basename 的 3-gram | name-contains 查询的主路径 |
| `file_name_bigrams` (file_id, gram, 同上) | basename 的 2-gram | 2-字符 name-contains 查询 |
| `file_path_segments` (file_id, segment, PRIMARY KEY(file_id, segment) WITHOUT ROWID) | path 拆分出的每个 segment（按 `/` 切） | `path:<token>` filter + segment 级别定位 |
| `idx_file_path_segments_segment` ON `file_path_segments(segment)` | B-tree 索引 | 同上 |

**不新增**：v4 的 `file_grams` / `file_bigrams` 保留，但 compact mode 下不写入。

### 3.2 基本数据规模粗估

假设典型 basename 长 20 字符、path 拆 8 个 segment、segment 平均长 12 字符：

- 每文件 `file_name_grams` ≈ 18 行（vs v4 ~250）
- 每文件 `file_name_bigrams` ≈ 19 行（vs v4 ~250）
- 每文件 `file_path_segments` ≈ 8 行（vs v4 ~0，新表）

总行数 ~45 rows/file（compact）vs ~500 rows/file（v4，name+path 合并）→ **体积缩 10×**。

实际数据会因文件名 / 路径长度偏态有波动，500k 规模下的真实数字在 G5 `SwiftSeekBench` 用 synthetic fixture 测。

---

## 4. Full-path substring 高级模式

用户可在设置页切到"完整路径子串模式"。该模式下：

- 额外写入 `file_grams` / `file_bigrams`（即 v4 行为）
- 额外体积成本：约 10× Compact 模式
- 查询能力：支持路径中间任意位置的 substring 命中（例如用户 `docs/myproj/1.2.3/subfolder/thing` 搜 `yproj/1.2`）

**默认关闭**。UI 明确标注"大幅增加 DB 体积"。

### 4.1 模式持久化
- `SettingsKey.indexMode`：`"compact"` | `"fullpath"`；新 DB 默认 `"compact"`
- 旧 v4 DB migrate 到 v5 时 `indexMode` 默认 `"fullpath"`（保留用户现状，避免静默丢能力）
- 设置页切换后弹窗引导全量重建（rebuild 会清对应 indexer mode 下的 gram 表）

---

## 5. 搜索语义差异

### 5.1 Compact mode 下 query 行为 — 冻结定义

**硬定义（G3 必须按此实现；偏离 = 越界）：**

| 维度 | Compact v5 冻结行为 |
|------|---------------------|
| `plain-token`（无 `path:` 前缀） | 只在 **basename** 匹配。`token.count >= 3` 走 `file_name_grams`；`token.count == 2` 走 `file_name_bigrams`；`token.count == 1` 走 LIKE fallback（仅对 `name_lower`）。**绝不召回 path-only 命中**。 |
| `path:<token>` | 走 `file_path_segments` 做**前缀匹配**（SQL: `segment = ? OR segment LIKE ? \|\| '%'`）。token 无需是完整 segment；但必须从 segment 开头开始。长度无限制。 |
| `path:` 多 token | 每 token 独立 AND：所有 token 都必须在 row 的某个 segment 上命中前缀 |
| `root:<prefix>` | 不变 — `path_lower LIKE 'prefix/%'`，走 `idx_files_path_lower` |
| `ext:` / `kind:` / `hidden:` | 不变 |

**正例（compact 模式必须命中）**：

1. query `foo` on file `foo-bar.txt` under `/a/b/` → hit（basename substring `file_name_grams` 命中）
2. query `al` on `/docs/alpha.md` → hit（2-char basename `file_name_bigrams` 命中）
3. query `path:docs` on `/work/docs/a.md` → hit（`docs` 是整个 segment，前缀匹配命中）
4. query `path:doc` on `/work/docs/a.md` → hit（`doc` 是 segment `docs` 的前缀）
5. query `ext:md` on `/work/readme.md` → hit（ext filter 不变）

**反例（compact 模式明确不命中）**：

1. query `myproj` on `/home/myproj-old/a.txt` → **miss**（`myproj` 只在 segment `myproj-old` 中间 substring；basename `a.txt` 不含 `myproj`）。要命中需切 fullpath mode。
2. query `path:oj` on `/home/myproj/a.txt` → **miss**（`oj` 不是 segment `myproj` 的前缀，只是中间 substring）
3. query `path:proj` on `/home/myproj/a.txt` → **miss**（不是前缀）
4. query `proj` on `/home/myproj/a.txt`（basename 不含 proj）→ **miss**（plain query 不再召回 path substring）

G3 smoke 必须至少各覆盖一条正例 + 一条反例。

### 5.2 明确能力 delta（compact）

- ✅ 保留：文件名任意 substring、path segment **前缀**匹配、ext / kind / root / hidden filter、多词 AND、所有 E1 bonus 评分
- ⚠️ 变化：plain query 不再召回 path-only 命中 —— 用户要搜路径中的 token 必须加 `path:` 前缀
- ⚠️ 变化：`path:<token>` 只做前缀匹配，不做 segment 内部 substring；中间 substring 必须走 fullpath mode
- ⚠️ 变化：路径中 segment 外观被 `-` / `_` / `.` 切的子部分（例如 `myproj-old` 里的 `old`）不在 compact index 里

UI 文案（G4）必须明确这个变化。

---

## 6. Schema v5 迁移计划

### 6.1 Schema migration statements

Migration target 5:
```sql
CREATE TABLE IF NOT EXISTS file_name_grams (
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    gram TEXT NOT NULL,
    PRIMARY KEY(file_id, gram)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_file_name_grams_gram ON file_name_grams(gram);

CREATE TABLE IF NOT EXISTS file_name_bigrams (
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    gram TEXT NOT NULL,
    PRIMARY KEY(file_id, gram)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_file_name_bigrams_gram ON file_name_bigrams(gram);

CREATE TABLE IF NOT EXISTS file_path_segments (
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    segment TEXT NOT NULL,
    PRIMARY KEY(file_id, segment)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_file_path_segments_segment ON file_path_segments(segment);

CREATE TABLE IF NOT EXISTS migration_progress (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

`migration_progress` 是 G3 分批 backfill 恢复点表（`last_file_id_processed` / `batch_mode`）。

### 6.2 分批 backfill 策略（G3）

**核心约束**：不在 migrate() 的单事务内跑 backfill；不在 App 启动时做大规模维护。

方案：

1. `Database.migrate()` 在 v4→v5 只 CREATE 新表，不 backfill
2. 新增 `settings.index_mode` 默认值：
   - 全新 DB：`"compact"`
   - 从 v4 升级：`"fullpath"`（保留用户现行能力直到其手动切换）
3. 背景 backfill 不由 migrate 触发，而是：
   - Compact mode 激活后，indexer 对**新增 / 更新**的行写 compact 表
   - 对已有 v4 行 backfill 由用户在维护页显式触发（新按钮"背景回填 compact 索引"），走 `MigrationCoordinator`（G3 新增）
4. `MigrationCoordinator` 分批：
   - 每批 ~5000 行
   - 每批独立 `BEGIN IMMEDIATE / COMMIT`
   - 每批结束 `PRAGMA wal_checkpoint(PASSIVE)` 
   - 写 `migration_progress.last_file_id_processed` → 支持中断后续跑
5. 失败回退：migration_progress 行保留，下次打开维护页可继续（按钮文字变"继续回填 (X/Y)"）

### 6.3 v4 保留策略

- 升级不删除 `file_grams` / `file_bigrams`
- 用户在 fullpath mode 下继续写入 v4 表
- 如果用户明确切到 compact mode 并完成回填，可选"清空 v4 索引释放空间"（维护页新按钮）—— 最后一步 VACUUM 释放磁盘

### 6.4 Rollback + Rebuild Plan（冻结）

**触发场景 / 响应矩阵**：

| 用户动作 | 当前 state | 响应 |
|---------|-----------|-----|
| 切 `fullpath → compact` | v4 表有数据、compact 表空 | UI 弹窗"需回填 compact 索引"；点"开始"触发 `MigrationCoordinator.backfillCompact(resume:true)`；不阻主；进度写入 `migration_progress.last_file_id_processed` |
| 切 `compact → fullpath` | v4 表完整 | mode 立即生效（SearchEngine 读新 mode 走 v4 表）；无需重建 |
| 切 `compact → fullpath` | v4 表已被"清空 v4 索引"按钮清过 | UI 弹窗"需重建 v4 索引"；点"开始"调用 `RebuildCoordinator.rebuild()` 全量重新索引，写 v4 表；**不重置 migration_progress**（compact 表不动，下次切回 compact 可继续） |
| backfill 失败（任一批次 throw） | 部分 compact 回填完 | `migration_progress` 保留已完成的 `last_file_id_processed`；UI 维护页按钮变"继续回填（X / Y）"；用户点击继续 |
| 用户在 compact 模式下新建 root 索引 | compact 表活动 | Indexer 对新 root 直接写 compact 表（不走 backfill），不影响 migration_progress |
| 用户"清空 v4 索引释放空间" | mode=compact + backfill 完成 | UI 二次确认后 `DELETE FROM file_grams; DELETE FROM file_bigrams; VACUUM;` 释放磁盘；**切回 fullpath 需全量重建** |

**rebuild 目标表**：

- `RebuildCoordinator.rebuild()` 的目标表由当前 `index_mode` 决定：
  - mode=compact → 清空并重建 `file_name_grams` / `file_name_bigrams` / `file_path_segments`（不动 v4 表）
  - mode=fullpath → 清空并重建 `file_grams` / `file_bigrams`（不动 v5 compact 表）
- `RebuildCoordinator` 的 indexer options 增加 `indexMode` 字段
- **绝不同时重建两套表** — 避免 5×+ 磁盘占用

**`migration_progress` 生命周期**：

- 创建：首次切到 compact 模式时
- 更新：每批 backfill 后
- 清理：backfill 完成（last_file_id_processed >= max files.id）后，UI 提示"回填完成"；`migration_progress` row 保留用于审计，但 coordinator 下次看到"完成"态不再触发工作
- 重置：用户在 compact 模式下点"强制重新回填"（隐藏在维护页高级操作里），coordinator 清 `migration_progress` 行 + 清 compact 表然后重新开始

**越界 / 不允许的 G3 行为**（Codex 验收时 reject）：

- ❌ G3 在 `Database.migrate()` 单事务里跑 compact backfill
- ❌ G3 在 App 启动主线程自动触发 backfill（哪怕是"少量"）
- ❌ G3 同时重建 v4 + v5 两套表
- ❌ G3 删除 v4 `file_grams` / `file_bigrams` 或 unsafely 清空用户数据而无 UI 确认
- ❌ G3 在 compact mode 下对 path 做 full substring 匹配（必须 fullpath mode 才行）
- ❌ G3 忽略 `migration_progress` — 每次打开都从 id=0 重新回填

**符合设计的 G3 行为**：

- ✅ v4→v5 migrate 只跑 `CREATE TABLE` + `CREATE INDEX` + `INSERT INTO settings(index_mode, 'fullpath')` ;
- ✅ 新 DB 自动 `index_mode='compact'`
- ✅ Indexer 按 mode 写对应表
- ✅ MigrationCoordinator 分批（batch_size 可配，默认 5000）+ 每批独立事务 + `wal_checkpoint(PASSIVE)`
- ✅ `migration_progress` 按 batch 更新
- ✅ SearchEngine 按 mode 分流 candidates

### 6.5 Schema v5 向前兼容

- Schema v5 添加的表不在回滚时删除
- 保留空表占用可忽略（几 KB）
- 未来 v6 可选择删除 v4 表；不是 v5 的范围

---

## 7. 查询路径变更（G3 实现约束）

### 7.1 `SearchEngine.candidates` 分流

```
if indexMode == .compact:
    long tokens → file_name_grams (basename trigram)
    short tokens → file_name_bigrams (basename bigram)
    path: tokens → file_path_segments
    fallback → like

if indexMode == .fullpath:
    long tokens → file_grams (v4)
    short tokens → file_bigrams (v4)
    path: tokens → file_grams
    fallback → like
```

### 7.2 兼容期（v4 DB 刚升到 v5，mode=fullpath）
- 完全复用 v4 查询路径，无行为差异
- `SearchEngine` 读 `indexMode` 的开销已被 F1 settings cache 吸收

### 7.3 Compact 回填中期（v4 表还有，compact 表正在回填）
- Mode=fullpath 时继续走 v4 表
- Mode=compact + 回填未完时：搜索结果可能不完整；UI 显示"索引回填中 X/Y"提示

---

## 8. Benchmark 目标（G5）

### 8.1 指标
- DB main file size
- WAL size
- `file_grams` / `file_bigrams` / `file_name_grams` / `file_name_bigrams` / `file_path_segments` 行数
- First-index time
- Warm search median / p95 per query type (2-char / 3+char / path: / ext:)
- Migrate v4→v5 time（CREATE-only）
- Compact backfill time
- Startup time

### 8.2 规模
- `SwiftSeekBench --files N` 支持任意 N
- 对比表：N ∈ {10k, 50k, 250k, 500k}
- 每条 benchmark 在 compact 和 fullpath 模式下各跑一次

### 8.3 预期
- 500k compact 模式 main ≤ 1.5 GB（vs v4 fullpath 3.4 GB）
- warm 2-char median ≤ 5ms（不回退 F1 水平）
- warm path: median ≤ 30ms
- compact backfill 500k 约 2-5 分钟（分批 + checkpoint，不阻主）

---

## 9. G3-G5 Task 对齐

- **G3**：Schema v5 + MigrationCoordinator + index mode 存储 + indexer 双写（根据 mode）+ SearchEngine 分流 + v4→v5 migrate CREATE-only
- **G4**：设置页 mode 选择 + 维护页"开始回填"按钮 + 进度条 + rebuild 引导
- **G5**：SwiftSeekBench 扩展 + compact vs fullpath 对比报告 + docs 最终收口

---

## 10. 验收矩阵（G2 设计阶段）

| 维度 | 设计要点 | G3 验收检查 |
|------|---------|-----------|
| 体积 | compact 表约为 v4 的 1/10 | G5 实测 500k 体积比对 |
| 搜索语义 | basename 无变化；path 变为 segment-based | G3 smoke 覆盖所有 E1/F4 查询模式 |
| 迁移恢复 | migrate CREATE-only / 背景分批 / 可继续 | G3 测试中断后续跑 |
| 回滚 | mode 可切换；v4 表保留 | G4 切回用例 |
| 启动影响 | migrate 单事务只 CREATE（几 ms） | G3 startup time smoke |
| 失败恢复 | migration_progress 行为 | G3 中断模拟测试 |

---

## 11. 本 proposal 明确不包含

- G3 具体代码实现 —— 仅约束接口
- 索引回填的精确 batch size / checkpoint 策略（G3 按 500k fixture 实测微调）
- UI 视觉设计 —— G4
- 500k benchmark 最终数字 —— G5

---

## 12. 变更日志

- v1（2026-04-24，G2 round 1）：首版设计文档，G1 之后 round 1 立项
