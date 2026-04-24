# SwiftSeek

macOS 原生本地极速文件搜索器。

当前仓库不是空项目：`v1-baseline` 已完成，`everything-alignment` 已归档；当前开启的新活跃轨道是 `everything-performance`。

## v1 baseline 能力
- Swift + AppKit + SQLite + FSEvents，macOS 13+
- 本地文件 / 文件夹搜索（文件名 / 路径优先，3-gram 倒排）
- 首次全量索引 + FSEvents + 文件系统 polling 双 backend 增量更新
- 全局热键 ⌥Space 呼出浮动搜索窗口
- 键盘流：↑/↓ 移动 · ⏎ 打开 · ⌘⏎ Reveal · ⌘⇧C 复制路径 · ESC 隐藏
- 设置页真实连线：索引目录（roots）/ 排除目录 / 隐藏文件开关 / 重建索引 / 诊断信息

## 明确不做
全文内容搜索、OCR、AI 语义搜索、云盘实时一致性、跨平台、Electron / Web UI 替代原生、APFS 原始解析、Finder 插件、App Store 沙盒适配、代码签名 / 公证。完整限制见 [docs/known_issues.md](docs/known_issues.md)。

## 当前进度
权威状态见 [docs/stage_status.md](docs/stage_status.md)。

- 已归档轨道：`v1-baseline`
- 当前活跃轨道：`everything-performance`
- 当前阶段：`F1`

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
- `SwiftSeek`
- `SwiftSeekIndex`
- `SwiftSeekSearch`
- `SwiftSeekStartup`
- `SwiftSeekSmokeTest`

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
