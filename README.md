# SwiftSeek

macOS 原生本地极速文件搜索器。

当前仓库不是空项目：`v1-baseline` 已完成，`everything-alignment` 已归档；当前开启的新活跃轨道是 `everything-performance`。

## 当前能力（截至 `everything-performance` F4）
- **技术栈**：Swift + AppKit + SQLite + FSEvents + Carbon 热键，macOS 13+
- **索引**：首次全量扫描 + FSEvents / polling 双 backend 增量；3-gram + 2-gram（F1）倒排
- **搜索**：
  - 多词 AND 语义（E1）
  - basename / token boundary / path segment / extension bonus（E1）
  - 过滤语法：`ext:` / `kind:` / `path:` / `root:` / `hidden:`（E3/F4）
  - filter-only 候选路径分层：path-gram > ext-scan > root-prefix > kind > fallback（F4）
  - 热路径：prepared statement cache + roots/settings cache（F1）
  - Bench 实测（10k 合成文件，release）：warm 2-char median ~3ms，warm 3+-char median ~3ms
- **结果窗**：
  - ⌥Space 浮动呼出；热键可在预设中切换（E5）
  - 4 列视图（名称 / 路径 / 修改时间 / 大小）；列头排序；列宽 + 排序跨重启持久化（E2/F3）
  - 行高 18px 密度，等宽数字对齐，folder/doc 图标分色（F3）
  - 键盘流：↑/↓ 移动 · ⏎ 打开 · ⌘⏎ Reveal · ⌘⇧C 复制路径 · ⌘Y QuickLook · ESC 隐藏
  - 右键菜单、结果拖出、substring 高亮（E5 UX polish）
  - 0 结果空态标注 offline / unavailable / paused 的 root（F4）
- **设置页**：索引目录、排除目录、隐藏文件开关、热键预设、结果上限、重建索引、诊断信息
- **RootHealth** 5 档（E4/F4）：ready / indexing / paused / offline / unavailable，设置页 badge + 搜索空态双重暴露

## 明确不做
全文内容搜索、OCR、AI 语义搜索、云盘实时一致性、跨平台、Electron / Web UI 替代原生、APFS 原始解析、Finder 插件、App Store 沙盒适配、代码签名 / 公证。完整限制见 [docs/known_issues.md](docs/known_issues.md)。

## 当前进度
权威状态见 [docs/stage_status.md](docs/stage_status.md)。

- 已归档轨道：`v1-baseline`、`everything-alignment`
- 当前活跃轨道：`everything-performance`
- 当前阶段：轨道内 F1 / F2 / F3 / F4 全部 PASS；F5 为最终收尾 + PROJECT COMPLETE

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
- `SwiftSeek` — GUI 主程序
- `SwiftSeekIndex` — CLI 首次 / 增量索引
- `SwiftSeekSearch` — CLI 搜索入口（默认 limit 读 `settings.search_limit`，F2 起 GUI/CLI 同源）
- `SwiftSeekStartup` — 非 GUI 启动检查（headless）
- `SwiftSeekSmokeTest` — 冒烟测试（119+ 用例）
- `SwiftSeekBench` — 搜索热路径 perf probe（F1，`--enforce-targets` 验收用）

## 构建与验证

```bash
swift build
swift run SwiftSeekSmokeTest
swift run SwiftSeek
swift run SwiftSeekIndex <path>
swift run SwiftSeekSearch <query>
```

## Roadmap
当前路线已切到 `everything-performance`，README 只保留入口：

- 当前性能 / 落地差距清单：[docs/everything_performance_gap.md](docs/everything_performance_gap.md)
- 当前阶段任务书：[docs/everything_performance_taskbook.md](docs/everything_performance_taskbook.md)

## 目录
```text
Sources/
  SwiftSeekCore/        核心索引 / 搜索 / DB / watcher / settings
  SwiftSeek/            AppKit GUI
  SwiftSeekIndex/       CLI 索引器
  SwiftSeekSearch/      CLI 搜索入口
  SwiftSeekStartup/     headless 启动检查
  SwiftSeekSmokeTest/   冒烟测试
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
  agent-state/
AGENTS.md / CLAUDE.md
```

## 协作模式
- Claude：主开发代理，负责实现、自检。
- Codex：独立验收代理，负责 REJECT / PASS / 下一阶段任务书。
- 历史 `v1-baseline` 与 `everything-alignment` 都已归档；当前继续推进的是 `everything-performance`。
