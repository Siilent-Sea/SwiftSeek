# SwiftSeek

macOS 原生本地极速文件搜索器。

当前仓库不是空项目：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`、`everything-productization`、`everything-menubar-agent`、`everything-filemanager-integration` 均已完成归档。当前新开活跃轨道是 `everything-dockless-hardening`，用于处理真实用户反馈的“打包后 Dock 仍常驻”问题。

## 当前能力（截至 `everything-menubar-agent` 完成）
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
  - 6 列视图（名称 / 路径 / 修改时间 / 大小 / 打开次数 / 最近打开）；列头排序；列宽 + 排序跨重启持久化
  - 行高 18px，等宽数字对齐，folder/doc 图标分色
  - 键盘流：↑/↓ 移动、Enter 打开、Command+Enter Reveal、Command+Shift+C 复制路径、Command+Y QuickLook、ESC 隐藏
  - 右键菜单、结果拖出、substring 高亮
  - 右键菜单扩展：Open With、Copy Name、Copy Full Path、Copy Parent Folder、Move to Trash（二次确认）
  - 0 结果空态标注 offline / unavailable / paused 的 root
- **设置页**：索引目录、排除目录、隐藏文件开关、热键预设、结果上限、索引模式、重建索引、DB 维护、诊断信息、搜索历史 / Saved Filters 管理、Launch at Login 状态、K5 权限重检 + 完全磁盘访问跳转
- **RootHealth**（K5 已细化）：ready / indexing / paused / offline（路径不存在）/ volumeOffline（卷未挂载）/ unavailable（无访问权限），设置页 badge + 鼠标悬停 detail tooltip + 诊断块 + 搜索空态四重暴露
- **Footprint**：500k 实测 compact 1.07 GB vs fullpath 3.46 GB；首次索引 44.87s vs 197.62s
- **Usage**（H1-H5）：`file_usage` 表记录 SwiftSeek 内部 `.open` 次数；结果表"打开次数" / "最近打开"两列；同 score tie-break (openCount → lastOpenedAt)；`recent:` / `frequent:` 查询前缀；设置 → 维护 tab 的记录开关 + 清空入口；500k+100k usage bench：3+char(+usage) 94.33ms 中位，`recent:` 89.44ms，`recordOpen` 8μs
- **UX parity**（J1-J6）：设置窗口 hide-only 生命周期、Dock / reopen 行为、搜索窗宽度与列恢复、wildcard / quote / OR / NOT、recent queries / Saved Filters、首次使用 banner、设置 tab 记忆、设置窗 frame 记忆、Launch at Login 公开 API 包装
- **菜单栏 agent**（L1-L4 历史归档）：菜单栏常驻、Dock 显示开关、菜单栏 tooltip / menu 状态、同 bundle id 单实例防护已实现；但真实用户反馈 Dock 仍可能常驻，当前 `everything-dockless-hardening` 会重新硬化 package / activation policy / `dock_icon_visible` 诊断与验收
- **文件管理器集成**（M1-M4）：设置 → 常规 → "显示位置" 可选 Finder（默认）或 自定义 App…（如 `/Applications/QSpace.app`、Path Finder.app 等任意 `.app`）；打开模式可选「父目录」或「文件本身」；搜索结果按钮 / 右键菜单 / hint 跟随当前 reveal target 动态变化；customApp 不存在 / 非 .app / 打开失败时 toast `⚠️ 无法用 <AppName> 显示，已回退到 Finder：…` 并 fallback 到 Finder 选中**原始**目标；reveal 不计入 Run Count；不调任何文件管理器私有 API、不假设 bundle id / URL scheme；外部 app 是否能"选中"具体文件由该 app 自身实现决定

## 当前限制
`everything-menubar-agent` 和 `everything-filemanager-integration` 已归档，但当前用户反馈表明 no-Dock 体验仍不够稳定：`scripts/package-app.sh` 仍写 `LSUIElement=false`，实际 Dock 形态由 runtime activation policy 和 DB 中 `dock_icon_visible` 决定。如果该设置被旧状态 / 测试 / 用户操作写成 `1`，SwiftSeek 会在启动后切到 `.regular` 并显示 Dock。`everything-dockless-hardening` 完成前，不再把“Dock 隐藏已完全稳定”作为无条件结论。本项目仍不做正式 Apple Developer ID 签名 / notarization / DMG / auto updater；跨用户多实例、不同 bundle id 的自定义构建、系统全局最近项目 / Finder 历史、外部文件管理器的「选中具体文件」语义、私有 API 都不在当前承诺范围。

**确认是否运行最新构建**：设置 → 关于 → 看顶部一行 `SwiftSeek <version> commit=<hash> build=<date>`，下方诊断块的 `bundle:` / `binary:` 行和你正在编辑的源码路径对比；不一致就是 stale bundle。详细排查见 [docs/manual_test.md](docs/manual_test.md) §33s。完整限制见 [docs/known_issues.md](docs/known_issues.md)。

## 明确不做
全文内容搜索、OCR、AI 语义搜索、云盘实时一致性、跨平台、Electron / Web UI 替代原生、APFS 原始解析、Finder 插件、App Store 沙盒适配、代码签名 / 公证、macOS 全局启动次数读取、系统隐私数据扫描。

## 当前进度
权威状态见 [docs/stage_status.md](docs/stage_status.md)。

- 已归档轨道：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`、`everything-productization`、`everything-menubar-agent`、`everything-filemanager-integration`
- 当前活跃轨道：`everything-dockless-hardening`
- 当前阶段：`N1`（Dock 常驻根因审计与诊断暴露）
- Release gate：[docs/release_checklist.md](docs/release_checklist.md) + [docs/release_notes_template.md](docs/release_notes_template.md)
- Dockless hardening 文档：[docs/everything_dockless_hardening_gap.md](docs/everything_dockless_hardening_gap.md) + [docs/everything_dockless_hardening_taskbook.md](docs/everything_dockless_hardening_taskbook.md)
- File-manager integration 文档（归档）：[docs/everything_filemanager_integration_gap.md](docs/everything_filemanager_integration_gap.md) + [docs/everything_filemanager_integration_taskbook.md](docs/everything_filemanager_integration_taskbook.md)
- everything-usage 500k 实测亮点：3+char 加 100k usage JOIN 中位 94.33ms（+4ms），`recent:` 89.44ms，`frequent:` 16.87ms，`recordOpen` 8μs
- everything-usage 实测报告：[docs/everything_usage_bench.md](docs/everything_usage_bench.md)

## 快速上手（本地交付）

**只想用 `.app`（推荐）— 一条命令打包出可启动 bundle**：

```bash
./scripts/package-app.sh
# 产物 dist/SwiftSeek.app，含 Info.plist + AppIcon.icns + ad-hoc codesign
# 双击或 open dist/SwiftSeek.app 启动
# 受限沙箱：./scripts/package-app.sh --sandbox
```

**完整安装 / 升级 / 回滚 / Launch at Login / stale bundle 排查** → [docs/install.md](docs/install.md)

**只要 CLI 二进制（开发迭代）**：

```bash
./scripts/build.sh                                # 标准
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/build.sh --sandbox                       # 受限沙箱
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
当前下一轨道是 `everything-dockless-hardening`：

- Dockless hardening 差距清单：[docs/everything_dockless_hardening_gap.md](docs/everything_dockless_hardening_gap.md)
- N1-N4 阶段任务书：[docs/everything_dockless_hardening_taskbook.md](docs/everything_dockless_hardening_taskbook.md)

最近完成轨道是 `everything-filemanager-integration`：

- 外部文件管理器集成差距清单：[docs/everything_filemanager_integration_gap.md](docs/everything_filemanager_integration_gap.md)
- M1-M4 阶段任务书：[docs/everything_filemanager_integration_taskbook.md](docs/everything_filemanager_integration_taskbook.md)

历史 menubar agent 轨道文档仍保留归档参考：

- 菜单栏 agent 差距清单：[docs/everything_menubar_agent_gap.md](docs/everything_menubar_agent_gap.md)
- L1-L4 阶段任务书：[docs/everything_menubar_agent_taskbook.md](docs/everything_menubar_agent_taskbook.md)

历史 productization 轨道文档仍保留归档参考：

- 产品化差距清单：[docs/everything_productization_gap.md](docs/everything_productization_gap.md)
- K1-K6 阶段任务书：[docs/everything_productization_taskbook.md](docs/everything_productization_taskbook.md)

历史 UX parity 轨道文档仍保留归档参考：

- UX parity 差距清单：[docs/everything_ux_parity_gap.md](docs/everything_ux_parity_gap.md)
- J1-J6 阶段任务书：[docs/everything_ux_parity_taskbook.md](docs/everything_ux_parity_taskbook.md)

历史 usage 轨道文档仍保留归档参考：
- [docs/everything_usage_gap.md](docs/everything_usage_gap.md)
- [docs/everything_usage_taskbook.md](docs/everything_usage_taskbook.md)
- [docs/everything_usage_bench.md](docs/everything_usage_bench.md)

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
  everything_usage_bench.md
  everything_ux_parity_gap.md
  everything_ux_parity_taskbook.md
  everything_productization_gap.md
  everything_productization_taskbook.md
  everything_menubar_agent_gap.md
  everything_menubar_agent_taskbook.md
  everything_filemanager_integration_gap.md
  everything_filemanager_integration_taskbook.md
  agent-state/
AGENTS.md / CLAUDE.md
```

## 协作模式
- Claude：主开发代理，负责实现、自检。
- Codex：独立验收代理，负责 REJECT / PASS / 下一阶段任务书。
- 最近完成的是 `everything-filemanager-integration`；后续新轨道仍以 `docs/stage_status.md` 为准，不能复用旧轨道的 `PROJECT COMPLETE`。
