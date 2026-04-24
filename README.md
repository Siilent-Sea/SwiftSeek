# SwiftSeek

macOS 原生本地极速文件搜索器。

当前仓库不是空项目：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage` 均已归档。`everything-usage`（H1-H5）于 2026-04-24 `PROJECT COMPLETE`，补齐了通过 SwiftSeek 打开的使用历史、Run Count、最近打开、`recent:` / `frequent:` 入口、usage tie-break 和 usage history 隐私控制。**当前无活跃轨道**，新轨道由用户发起。

## 当前能力（截至 `everything-usage` 完成）
- **技术栈**：Swift + AppKit + SQLite + FSEvents + Carbon 热键，macOS 13+
- **索引**：首次全量扫描 + FSEvents / polling 双 backend 增量；Schema v5 compact index 默认模式；Full path substring 高级模式保留
- **搜索**：
  - 多词 AND 语义
  - basename / token boundary / path segment / extension bonus
  - 过滤语法：`ext:` / `kind:` / `path:` / `root:` / `hidden:`
  - filter-only 候选路径分层：path segment / path gram > ext-scan > root-prefix > kind > fallback
  - 热路径：prepared statement cache + roots/settings cache
  - Bench 实测（10k 合成文件，release）：warm 2-char median 约 3ms，warm 3+char median 约 3ms
- **结果窗**：
  - 全局热键浮动呼出；热键可在预设中切换
  - 4 列视图（名称 / 路径 / 修改时间 / 大小）；列头排序；列宽 + 排序跨重启持久化
  - 行高 18px，等宽数字对齐，folder/doc 图标分色
  - 键盘流：↑/↓ 移动、Enter 打开、Command+Enter Reveal、Command+Shift+C 复制路径、Command+Y QuickLook、ESC 隐藏
  - 右键菜单、结果拖出、substring 高亮
  - 0 结果空态标注 offline / unavailable / paused 的 root
- **设置页**：索引目录、排除目录、隐藏文件开关、热键预设、结果上限、索引模式、重建索引、DB 维护、诊断信息
- **RootHealth**：ready / indexing / paused / offline / unavailable，设置页 badge + 搜索空态双重暴露
- **Footprint**：500k 实测 compact 1.07 GB vs fullpath 3.46 GB；首次索引 44.87s vs 197.62s
- **Usage**（H1-H5）：`file_usage` 表记录 SwiftSeek 内部 `.open` 次数；结果表"打开次数" / "最近打开"两列；同 score tie-break (openCount → lastOpenedAt)；`recent:` / `frequent:` 查询前缀；设置 → 维护 tab 的记录开关 + 清空入口；500k+100k usage bench：3+char(+usage) 94.33ms 中位，`recent:` 89.44ms，`recordOpen` 8μs

## 当前限制
Run Count / 最近打开 / `recent:` / `frequent:` / usage tie-break 已在 H1-H5 落地（见 [docs/everything_usage_bench.md](docs/everything_usage_bench.md)），且只记录通过 SwiftSeek 打开的次数 —— macOS 全局启动次数不在承诺范围，不读系统隐私数据。剩余限制仍然集中在：500k 规模下 warm 3+char 超出 F1 旧 10k 基线（规模效应，G5 已记录），启发式相关性模型、查询 DSL（不支持 OR/NOT/括号/引号短语/复杂布尔）等。完整限制见 [docs/known_issues.md](docs/known_issues.md)。

## 明确不做
全文内容搜索、OCR、AI 语义搜索、云盘实时一致性、跨平台、Electron / Web UI 替代原生、APFS 原始解析、Finder 插件、App Store 沙盒适配、代码签名 / 公证、macOS 全局启动次数读取、系统隐私数据扫描。

## 当前进度
权威状态见 [docs/stage_status.md](docs/stage_status.md)。

- 已归档轨道：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`（H1-H5，2026-04-24 PROJECT COMPLETE）
- 当前活跃轨道：**无**（新轨道启动由用户发起）
- everything-usage 500k 实测亮点：3+char 加 100k usage JOIN 中位 94.33ms（+4ms），`recent:` 89.44ms，`frequent:` 16.87ms，`recordOpen` 8μs
- everything-usage 实测报告：[docs/everything_usage_bench.md](docs/everything_usage_bench.md)

## 快速上手（本地交付）

最简一条龙：

```bash
./scripts/build.sh
```

受限沙箱用：

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/build.sh --sandbox
```

构建完成后二进制在 `.build/release/` 下：
- `SwiftSeek` - GUI 主程序
- `SwiftSeekIndex` - CLI 首次 / 增量索引
- `SwiftSeekSearch` - CLI 搜索入口
- `SwiftSeekStartup` - 非 GUI 启动检查
- `SwiftSeekSmokeTest` - 冒烟测试
- `SwiftSeekBench` - 搜索热路径 perf probe + compact vs fullpath 对比
- `SwiftSeekDBStats` - DB 体积观测 + checkpoint/optimize/VACUUM 维护 CLI

## 构建与验证

```bash
swift build
swift run SwiftSeekSmokeTest
swift run SwiftSeek
swift run SwiftSeekIndex <path>
swift run SwiftSeekSearch <query>
```

## Roadmap
当前下一轨道是 `everything-usage`：

- 使用历史与 Everything-like 体验差距：[docs/everything_usage_gap.md](docs/everything_usage_gap.md)
- H1-H5 阶段任务书：[docs/everything_usage_taskbook.md](docs/everything_usage_taskbook.md)

历史 footprint 轨道文档仍保留归档参考：
- [docs/everything_footprint_gap.md](docs/everything_footprint_gap.md)
- [docs/everything_footprint_taskbook.md](docs/everything_footprint_taskbook.md)
- [docs/everything_footprint_bench.md](docs/everything_footprint_bench.md)

## 目录
```text
Sources/
  SwiftSeekCore/        核心索引 / 搜索 / DB / watcher / settings
  SwiftSeek/            AppKit GUI
  SwiftSeekIndex/       CLI 索引器
  SwiftSeekSearch/      CLI 搜索入口
  SwiftSeekStartup/     headless 启动检查
  SwiftSeekSmokeTest/   冒烟测试
  SwiftSeekBench/       benchmark / probe
  SwiftSeekDBStats/     DB stats / maintenance CLI
docs/
  stage_status.md
  codex_acceptance.md
  next_stage.md
  architecture.md
  manual_test.md
  known_issues.md
  everything_gap.md
  everything_alignment_taskbook.md
  everything_performance_gap.md
  everything_performance_taskbook.md
  everything_footprint_gap.md
  everything_footprint_taskbook.md
  everything_footprint_bench.md
  everything_usage_gap.md
  everything_usage_taskbook.md
  agent-state/
AGENTS.md / CLAUDE.md
```

## 协作模式
- Claude：主开发代理，负责实现、自检。
- Codex：独立验收代理，负责 REJECT / PASS / 下一阶段任务书。
- 当前继续推进的是 `everything-usage`，不得因历史轨道 `PROJECT COMPLETE` 而停止。
