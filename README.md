# SwiftSeek

macOS 原生本地极速文件搜索器。

当前仓库不是空项目：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint` 均已归档。`everything-footprint`（G1-G5）于 2026-04-24 `PROJECT COMPLETE`，解决了 500k+ 文件规模下的 DB 体积、迁移和维护体验问题。**当前无活跃轨道**，新轨道由用户发起。

## 当前能力（截至 `everything-performance` 完成）
- **技术栈**：Swift + AppKit + SQLite + FSEvents + Carbon 热键，macOS 13+
- **索引**：首次全量扫描 + FSEvents / polling 双 backend 增量；3-gram + 2-gram 倒排
- **搜索**：
  - 多词 AND 语义
  - basename / token boundary / path segment / extension bonus
  - 过滤语法：`ext:` / `kind:` / `path:` / `root:` / `hidden:`
  - filter-only 候选路径分层：path-gram > ext-scan > root-prefix > kind > fallback
  - 热路径：prepared statement cache + roots/settings cache
  - Bench 实测（10k 合成文件，release）：warm 2-char median 约 3ms，warm 3+char median 约 3ms
- **结果窗**：
  - 全局热键浮动呼出；热键可在预设中切换
  - 4 列视图（名称 / 路径 / 修改时间 / 大小）；列头排序；列宽 + 排序跨重启持久化
  - 行高 18px，等宽数字对齐，folder/doc 图标分色
  - 键盘流：↑/↓ 移动、Enter 打开、Command+Enter Reveal、Command+Shift+C 复制路径、Command+Y QuickLook、ESC 隐藏
  - 右键菜单、结果拖出、substring 高亮
  - 0 结果空态标注 offline / unavailable / paused 的 root
- **设置页**：索引目录、排除目录、隐藏文件开关、热键预设、结果上限、重建索引、诊断信息
- **RootHealth**：ready / indexing / paused / offline / unavailable，设置页 badge + 搜索空态双重暴露

## 当前限制
500k+ 文件规模下，Schema v5 compact 模式已把 DB 体积从 fullpath 3.46 GB 压到 1.07 GB（3.2× 更小），迁移 CREATE-only（reopen/migrate ms 级），compact 回填由后台 MigrationCoordinator 分批执行。仍保留的限制（如 warm 3+char 在 500k 下超 F1 旧 30ms/100ms 目标等规模效应事实）见 [docs/known_issues.md](docs/known_issues.md)。

## 明确不做
全文内容搜索、OCR、AI 语义搜索、云盘实时一致性、跨平台、Electron / Web UI 替代原生、APFS 原始解析、Finder 插件、App Store 沙盒适配、代码签名 / 公证。

## 当前进度
权威状态见 [docs/stage_status.md](docs/stage_status.md)。

- 已归档轨道：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`（G1-G5，2026-04-24 PROJECT COMPLETE）
- 当前活跃轨道：**无**（新轨道启动由用户发起）
- everything-footprint 500k 实测亮点：compact 1.07 GB vs fullpath 3.46 GB（3.2× 更小），首次索引 44.87s vs 197.62s（4.4× 更快），reopen/migrate 都是 ms 级

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
- `SwiftSeekBench` - 搜索热路径 perf probe + compact vs fullpath 对比（G5）
- `SwiftSeekDBStats` - DB 体积观测 + checkpoint/optimize/VACUUM 维护 CLI（G1）

## 构建与验证

```bash
swift build
swift run SwiftSeekSmokeTest
swift run SwiftSeek
swift run SwiftSeekIndex <path>
swift run SwiftSeekSearch <query>
```

## Roadmap
当前下一轨道是 `everything-footprint`：

- 大库体积与维护差距：[docs/everything_footprint_gap.md](docs/everything_footprint_gap.md)
- G1-G5 阶段任务书：[docs/everything_footprint_taskbook.md](docs/everything_footprint_taskbook.md)

历史性能轨道文档仍保留归档参考：
- [docs/everything_performance_gap.md](docs/everything_performance_gap.md)
- [docs/everything_performance_taskbook.md](docs/everything_performance_taskbook.md)

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
  agent-state/
AGENTS.md / CLAUDE.md
```

## 协作模式
- Claude：主开发代理，负责实现、自检。
- Codex：独立验收代理，负责 REJECT / PASS / 下一阶段任务书。
- 当前继续推进的是 `everything-footprint`，不得因历史轨道 `PROJECT COMPLETE` 而停止。
