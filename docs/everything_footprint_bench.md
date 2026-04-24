# G5 — Compact vs Fullpath Benchmark（500k 实测）

SwiftSeekBench 实测数据（release build，`--mode both`，checkpoint 后采样）。用来验证 G2/G3 proposal 对 500k+ 库的体积目标是否成立。

## Setup
- 硬件：本机 Apple Silicon Mac，macOS 13+
- 合成文件：每个文件名 `<word1>-<word2>-<i>.<ext>`，分布在 `<word1>/<word2>/` 子目录下（35 词汇 × 35 depth buckets）
- 平均 path 长度 ~80-100 字符；basename ~18-25 字符
- Release build：`swift build -c release --disable-sandbox`
- 每条 query warm up 2 轮，然后采样，取 median / p95
- `computeStats()` 前调 WAL checkpoint(TRUNCATE)，`main` 字段反映真实磁盘占用
- reopen / migrate 计时：关闭索引完成的 DB，再次 Database.open + migrate()，测真实"启动打开 populated DB"的成本

## 20k files 实测（2026-04-24）

| 指标 | Compact | Fullpath | 比例 |
|------|---------|----------|------|
| main DB | 39.7 MB | 128 MB | **0.31×（3.2× 更小）** |
| 索引行数 | 868,794 | 4,763,509 | **0.18×（5.5× 更少）** |
| 首次索引时间 | 1.42s | 6.77s | **0.21×（4.7× 更快）** |
| reopen time | ~1ms | ~1ms | 持平 |
| migrate time | ~0ms | ~0ms | 持平（已是最新 schema） |
| warm 2-char median | 2.68ms | 3.24ms | 两者都 <50ms F1 目标 |
| warm 3+char median | 4.11ms | 3.47ms | 两者都 <30ms F1 目标 |

## 500k files 实测（2026-04-24，iters=20）

这是 G5 round 2 真实采集的大规模数据，不是外推。

| 指标 | Compact | Fullpath | 比例 |
|------|---------|----------|------|
| **main DB** | **1.07 GB** | **3.46 GB** | **0.31×（3.2× 更小）** |
| **索引行数总** | 23,024,963 | 118,932,793 | **0.19×（5.2× 更少）** |
| file_grams | 0 | 61,779,145 | — |
| file_bigrams | 0 | 57,153,648 | — |
| file_name_grams | 9,123,504 | 0 | — |
| file_name_bigrams | 9,415,745 | 0 | — |
| file_path_segments | 4,485,714 | 0 | — |
| **首次索引时间** | **44.87s** | **197.62s** | **0.23×（4.4× 更快）** |
| **reopen time** | **0.001s** | **0.001s** | 持平 — G3 migrate CREATE-only 关键证据 |
| **migrate time** | **0.000s** | **0.000s** | 持平（启动时 schema 已是最新，无 backfill） |
| warm 2-char median | 2.62ms | 3.22ms | 都 < F1 50ms 目标 ✓ |
| warm 2-char p95 | 5.25ms | 6.30ms | 都 < F1 150ms 目标 ✓ |
| warm 3+char median | 89.63ms | 95.97ms | ⚠️ 超 F1 30ms 目标；两者相近 |
| warm 3+char p95 | 258.96ms | 397.45ms | ⚠️ 超 F1 100ms 目标；compact 仍快 35% |

### 关键观察

**1. 真实用户 586k=3.4GB 与本 500k=3.46GB 吻合**
用户报告的 586k 文件 fullpath DB main file 3.4 GB。我们 500k 合成实测 3.46 GB。数据模型正确。

**2. compact 3.2× 更小是稳定数字**
20k 和 500k 两个规模下 main DB size 比例都是 0.31×，说明缩减效果不是小规模偶然，线性成立。

**3. reopen/migrate 几乎为 0**
G3 migrate() CREATE-only 的核心承诺在 500k 规模下得到验证：关闭+重新打开+migrate() 合计 ~1ms。这意味着用户升级 v4→v5 不会遇到"启动时卡几分钟"的问题（G1 触发新轨道的起因）。

**4. 索引速度 4.4× 快**
Compact mode 首次全量索引 500k 文件用 44.87s（对比 fullpath 的 197.62s）。对首次安装或 reset 索引的用户有意义。

**5. warm 3+char 超 F1 目标 — 需要诚实记录**
F1 原本在 10k 规模下定的 30ms 中位 / 100ms p95 目标，在 500k 规模下两种模式都超了。compact 89.63ms / 258.96ms p95，fullpath 95.97ms / 397.45ms p95。
- 绝对速度仍是亚秒级
- compact 比 fullpath 略快
- 这不是 G-系列回归（F1 基线是 10k），而是规模效应暴露的事实
- F1 目标在新的 500k 基线下应重写。这是 G5 结论之一，留给后续轨道（如果有需要）处理；本轨道收尾不改 F1 合同。

## 500k 结果 vs proposal §2 目标

- ✅ 显著缩小 DB footprint — 3.2× 实测（proposal 粗估 10×）
- ✅ 大部分查询语义保持 — 2-char / 3+char / path: 前缀 / ext / kind / root / hidden 均正常
- ✅ 能力换体积明确 — full-path substring 作为可选模式保留 v4 表
- ✅ 迁移路径可控 — reopen/migrate 在 500k 上都是 ms 级
- ✅ 可回滚 — v4 `file_grams` / `file_bigrams` 未删，mode 切回 fullpath 立即可用

## 为什么没达 10×

Proposal §3.2 粗估 "每文件 ~45 rows" 基于 8 个 segment + 短 basename；实测每文件 compact ~46 rows（9.1M+9.4M+4.5M / 500k = 46），fullpath ~238 rows（61.8M+57.2M / 500k）。单文件比值 5.2×，不是 10×。

差距来自：
- 合成文件 basename 比实际用户长（`alpha-beta-12345.txt` 20-25 字符）
- 实际用户文件名常 8-12 字符，compact 相对优势应更大
- fullpath trigrams 主要来自 path（88 字符 → ~260 个 3-gram），而非 basename
- 用户真实场景 compact 相对优势大概率 >5×，但需用户真实数据验证

对 500k 用户：3.4 GB → 1.07 GB 是决定性收益，足够消除之前启动卡顿 / WAL 暴涨问题。

## 如何复现

```bash
# 快速双模式对比（20k，~8s 完成）
./.build/release/SwiftSeekBench --mode both --files 20000 --iters 30

# 大规模验收（500k，~4 分钟）
./.build/release/SwiftSeekBench --mode both --files 500000 --iters 20

# 单模式超大规模（500k + 50 iters，~5 分钟）
./.build/release/SwiftSeekBench --mode compact --files 500000 --iters 50
./.build/release/SwiftSeekBench --mode fullpath --files 500000 --iters 50

# F1 性能目标硬检查（注：500k 3+char 会超目标）
./.build/release/SwiftSeekBench --enforce-targets --files 10000
```

## 时间戳

- 2026-04-24：G5 round 2 落地 500k 实测 + reopen/migrate 计时
