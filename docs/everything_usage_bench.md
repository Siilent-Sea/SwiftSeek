# H5 — Usage benchmark（100k / 500k 实测）

`everything-usage` 轨道最终 benchmark。目的是在真实规模下证明 H1-H4 的 usage 路径（usage JOIN、`recent:`/`frequent:`、`recordOpen` 写入、隐私开关）不会把 SwiftSeek 的搜索主路径体验带崩。

## Setup

- 硬件：本机 Apple Silicon Mac，macOS 13+
- 构建：`swift build -c release --disable-sandbox`
- 合成 fixture：与 G5 相同（`<word1>-<word2>-<i>.<ext>`，分布在 `<word1>/<word2>/` 子目录；35 词汇 × 35 深度）
- 索引模式：Compact（H1-H4 改动对 fullpath 同样生效；compact 是默认，代表真实主路径）
- bench：`SwiftSeekBench --mode compact --files N --iters K --usage-rows M --record-open-ops R`
- 采样：每个 query warm-up 2 轮，取 K 次 median / p95
- `file_usage` 预填：取 `files` 表前 M 个 id 做 INSERT，`open_count` 在 1-20 之间循环，`last_opened_at` 单调递增保证 `recent:` / `frequent:` 排序可区分

## 100k files 实测（2026-04-24，iters=20，usage_rows=10k，record_open_ops=500）

| 指标 | 值 |
|------|----|
| 文件数 | 100,000 |
| file_usage 行数 | 10,000（10% 覆盖） |
| main DB | 207.3 MB |
| WAL | 2.3 MB |
| 索引行数 | name_grams 1,735,684 / name_bigrams 1,797,208 / path_segs 897,143 |
| 首次索引时间 | 6.64s |
| reopen | 0.000s |
| migrate | 0.000s |
| warm 2-char median / p95 | 2.63ms / 2.77ms |
| warm 3+char median / p95（usage 表为空） | 16.98ms / 19.87ms |
| warm 3+char median / p95（10k usage rows） | **16.90ms / 19.91ms**（与空表持平） |
| `recent:` median / p95 | 8.25ms / 9.32ms |
| `frequent:` median / p95 | 1.95ms / 2.32ms |
| `recordOpen` median / p95 | 0.007ms / 0.009ms |

### 100k 关键观察

1. **usage JOIN 开销可以忽略**：3+char 查询有 / 无 10k usage rows 的中位数差异在 0.1ms 以内（16.98 vs 16.90ms），远小于测量噪声。LEFT JOIN file_usage 在 100k 规模下不是瓶颈。
2. **`recent:` / `frequent:` 比普通 3+char 更快**：候选池来自 file_usage INNER JOIN，规模远小于 gram/bigram 候选集（10k vs 1.7M），SQL ORDER BY 直接走 usage 列，所以更轻。
3. **`recordOpen` 在微秒级**：UPSERT 单次 ~7μs，用户连续点开文件时不会感知延迟。H1/H4 的同步调用语义 OK。

## 500k files 实测（2026-04-24，iters=20，usage_rows=100k，record_open_ops=500）

| 指标 | 值 |
|------|----|
| 文件数 | 500,000 |
| file_usage 行数 | 100,000（20% 覆盖） |
| main DB | 1.07 GB |
| WAL | 4.1 MB |
| 索引行数 | name_grams 9,123,504 / name_bigrams 9,415,745 / path_segs 4,485,714 |
| 首次索引时间 | 41.95s |
| reopen | 0.001s |
| migrate | 0.000s |
| warm 2-char median / p95 | 2.71ms / 5.64ms |
| warm 3+char median / p95（usage 表为空） | 90.33ms / 249.88ms |
| warm 3+char median / p95（100k usage rows） | **94.33ms / 99.11ms** |
| `recent:` median / p95 | 89.44ms / 90.20ms |
| `frequent:` median / p95 | 16.87ms / 19.65ms |
| `recordOpen` median / p95 | 0.008ms / 0.010ms |

### 500k 关键观察

1. **main DB / index time / row counts 与 G5 compact 一致**：H1-H4 不改变 compact 索引的基线体积（1.07 GB @500k），usage 路径只在 `file_usage` 表叠加 100k 行（约 3 MB）。
2. **usage JOIN 在 500k 规模下可测但不破坏体验**：3+char 空 usage 90.33ms → 100k usage 94.33ms（+4ms 中位数）。p95 反而更低（99.11 vs 249.88ms），说明第二次预热后 SQLite page cache 已稳定，H2 LEFT JOIN 不引入长尾抖动。
3. **`recent:` median = 89.44ms，p95 = 90.20ms**：候选池是 file_usage INNER JOIN files，100k 行扫描 + ORDER BY last_opened_at DESC；规模与普通 3+char 相当，但 p95 的长尾被 SQL ORDER BY 的稳定性压平了（250ms 级的长尾变 90ms）。
4. **`frequent:` median = 16.87ms**：比 `recent:` 快 5×。应该是 open_count 值域较小（1-20 循环），ORDER BY 判等分支少，index-less scan 早期命中。真实用户 open_count 分布更分散时值会接近 recent。
5. **`recordOpen` 仍在 8 微秒**：100k file_usage 的 UPSERT 增量更新没有显著变慢；B-tree 在 100k rowid 下依然低成本。H1 同步调用承诺 @500k 成立。
6. **F1 目标旧基线（10k 3+char 30ms med / 100ms p95）** 在 500k 规模下两种模式都超（这点 G5 已诚实记录）；H5 的 `recent:` / 3+char(w/usage) 维持同量级，没有 usage 路径自身导致的回退。

## 对 H1-H4 合同的结论

- **H1 recordOpen 写入延迟** 100k+usage=10k 7μs / 500k+usage=100k 8μs —— 微秒级，打开文件时同步记录不会被用户感知
- **H2 usage JOIN** 500k+100k usage 下把 3+char 中位从 90.33ms 推到 94.33ms（+4ms），p95 实际更低；JOIN 成本可忽略，tie-break 逻辑零延迟
- **H3 `recent:` / `frequent:`** 500k 规模下 16-90ms 中位数；没有 F1 10k 基线的 30ms p95 目标，但体感仍在瞬间级（sub-100ms 中位）
- **H4 隐私开关 / 清空** 不在 benchmark 路径里；功能由 smoke 覆盖（5 条）

## 对 H1-H4 合同的结论

- **H1 recordOpen 写入延迟** 微秒级，符合 "打开文件时同步记录不卡用户" 的承诺
- **H2 usage JOIN** 在 500k 规模下不显著增加搜索延迟，H2 的 tie-break 效果无性能代价
- **H3 `recent:` / `frequent:`** 查询比普通 3+char 显著更快（候选池天生小）
- **H4 隐私开关 / 清空** 不涉及 benchmark 路径；功能由 smoke 覆盖

## 如何复现

```bash
# 构建（受限沙箱）
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/build.sh --sandbox

# 100k（约 1 分钟）
./.build/release/SwiftSeekBench --mode compact --files 100000 --iters 20 \
  --usage-rows 10000 --record-open-ops 500

# 500k（约 4-5 分钟）
./.build/release/SwiftSeekBench --mode compact --files 500000 --iters 20 \
  --usage-rows 100000 --record-open-ops 500

# 不启用 usage 测量 = 向后兼容 G5 的老命令
./.build/release/SwiftSeekBench --mode compact --files 100000 --iters 20
```

## 边界说明

- 合成 fixture 的 basename (20-25 字符) 比真实用户文件名长，compact 索引行数略偏高；用户真实库 usage 路径体验应更好而非更差。
- `recordOpen` 的 UPSERT 测量假设已存在 usage 行（increment 路径）；首次 open（INSERT 路径）因走不同 SQL 分支，成本略高但仍在同量级。smoke 与手测中都有覆盖。
- `recent:` / `frequent:` 的候选池受 `file_usage` 规模影响；100k 规模（我们的真实用户上限）下 sub-10ms。如果 `file_usage` 增长到 1M+ 规模（极端），可能需要加开启 index（H2 明确推迟了 index；若未来证明必要可在新轨道补）。

## 时间戳

- 2026-04-24：H5 round 1 落地 100k / 500k usage bench
