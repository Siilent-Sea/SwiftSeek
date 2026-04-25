# SwiftSeek

macOS 原生本地极速文件搜索器。

当前仓库不是空项目：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity` 均已完成归档。`everything-ux-parity`（J1-J6）在 2026-04-25 `PROJECT COMPLETE`，收口了桌面 App 生命周期、Run Count 可见性、Everything 风格查询表达、搜索历史 / Saved Filters、上下文菜单、首次使用引导、Launch at Login 说明与窗口状态记忆。当前活跃轨道是 `everything-productization`，聚焦 `.app` 打包、版本标识、stale build 防护、安装/升级/回滚、诊断和 release QA。

## 当前能力（截至 `everything-ux-parity` 完成）
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

## 当前限制
SwiftSeek 已完成 `everything-ux-parity`，产品化轨道 `everything-productization` 当前已落地 K1-K5：K1 build identity（version / commit / build date / bundle / binary）+ 设置窗口 release gate；K2 `scripts/package-app.sh` 一条命令重复打包 + ad-hoc codesign；K3 `Diagnostics.snapshot` 单一来源；K4 `docs/install.md` 安装 / 升级 / 回滚 / Launch at Login / stale bundle 文档；K5 root 权限四态徽标 + RootHealthReport tooltip + "重新检查权限" + "打开完全磁盘访问设置" 按钮 + 诊断同源。仍未完成：release QA 收口（K6）。本轨道明确不做正式 Apple Developer ID 签名 / notarization / DMG / auto updater。

**确认是否运行最新构建**：设置 → 关于 → 看顶部一行 `SwiftSeek <version> commit=<hash> build=<date>`，下方诊断块的 `bundle:` / `binary:` 行和你正在编辑的源码路径对比；不一致就是 stale bundle。详细排查见 [docs/manual_test.md](docs/manual_test.md) §33s。完整限制见 [docs/known_issues.md](docs/known_issues.md)。

## 明确不做
全文内容搜索、OCR、AI 语义搜索、云盘实时一致性、跨平台、Electron / Web UI 替代原生、APFS 原始解析、Finder 插件、App Store 沙盒适配、代码签名 / 公证、macOS 全局启动次数读取、系统隐私数据扫描。

## 当前进度
权威状态见 [docs/stage_status.md](docs/stage_status.md)。

- 已归档轨道：`v1-baseline`、`everything-alignment`、`everything-performance`、`everything-footprint`、`everything-usage`、`everything-ux-parity`
- 当前活跃轨道：`everything-productization`（K1 起步）
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
当前下一轨道是 `everything-productization`：

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
  agent-state/
AGENTS.md / CLAUDE.md
```

## 协作模式
- Claude：主开发代理，负责实现、自检。
- Codex：独立验收代理，负责 REJECT / PASS / 下一阶段任务书。
- 当前继续推进的是 `everything-productization`，不得因历史轨道 `PROJECT COMPLETE` 而停止。
