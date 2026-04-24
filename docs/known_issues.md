# SwiftSeek 已知问题 / 当前限制

本文档记录当前仓库的已知限制。这里列的是“当前就是这样”，不是单纯 bug 乱报。

## 当前活跃轨道视角下的明显限制

### 1. 查询语法已接入（E3 起）
- 支持过滤语法：`ext:`、`kind:` (`file` / `dir`)、`path:`、`root:`、`hidden:` (`true`/`false`/`yes`/`no`/`1`/`0`/`on`/`off`)
- filter 与 plain query 可组合（AND 语义）
- 未知过滤 key（如 `foo:bar`）保留为 plain token，不被误解为 filter
- 未知 kind 值、空 filter 值均静默忽略，不抛错
- **不支持** 查询 DSL（括号 / OR / NOT 等）；**不支持** 全文内容搜索；**不支持** AI 语义搜索。

### 2. 结果列表 Everything 风格已接入（E2 起）
- 结果视图已改为 4 列：名称 / 路径 / 修改时间 / 大小
- 列头可点击切换排序；默认仍为 score 降序
- 当前尚不提供 pinned column、多选列、右键列菜单等高级视图能力（留给后续非阶段任务再考虑）

### 3. 热键仍未可配置（留给 E5）
- 默认全局热键仍是固定的 `⌥Space`
- 如果与 Spotlight、Alfred、Raycast 冲突，只能改别的 App，或改代码后重新编译
- 设置页当前没有热键自定义入口
- E5 阶段专门处理热键配置

### 4. 索引自动化体验仍偏手动（留给 E4）
- 新增 root 后当前是弹窗询问是否立即索引，不是默认后台自动开始
- 隐藏文件开关改动后仍依赖手动重建
- exclude 的清理路径已有，但整体“改完设置立即知道系统会怎么生效”的体验还不够完整
- E4 阶段专门处理索引自动化 + root 状态

### 5. 外接盘 / root 可用性状态感知不足（留给 E4）
- root 当前只有启用 / 停用 / 移除语义
- 没有更明确的“根目录当前离线 / 未挂载 / 不可访问”状态提示
- 外接盘拔出后的索引残留主要还是靠手工处理

## E1 已解决的限制（2026-04-24）

### E1 已解决
- **多词 query AND 语义**：`SearchEngine.tokenize` + 逐 token substring AND filter。
- **相关性细粒度 bonus**：basename (+50) / token boundary (+30) / path segment (+40) / extension (+80) / 多词 all-in-basename (+100)。
- **GUI 结果上限可配置**：`search_limit` 持久化到 settings 表，范围 [20, 1000]，默认 100；设置页常规 pane 提供配置入口；SearchViewController 每次查询读取，状态栏动态回显“仅显示前 N 条”。

### E2 已解决
- **多列高密度结果视图**：4 列（名称 / 路径 / 修改时间 / 大小）+ NSTableHeaderView。
- **排序切换**：列头点击；`SearchSortKey.{score, name, path, mtime, size}` + ascending。默认 `.scoreDescending`。
- **排序稳定 + 大小写不敏感**：`SearchEngine.sort(_:by:)` 是 pure function，tie-break 用 shorter-path-then-alphabetical，保证可重现与可逆。
- **键盘流 / 右键 / 拖拽 / QuickLook / 高亮 不回退**：新 cell 类型保留所有原行为。

### E3 已解决
- **5 个字段过滤**：`ext:` / `kind:` / `path:` / `root:` / `hidden:` 通过 `SearchEngine.parseQuery(_:)` 解析。
- **plain + filter 可组合**：plain token 仍走 gram + AND substring；filter 在候选收回后 AND 应用。
- **filter-only 查询**：经 `filterOnlyCandidates` 单条 SQL 收回候选（ext > root > kind 优先级），按 mtime 降序展示。
- **宽容解析**：未知 key / 未知 kind 值 / 空 filter 值均静默退化，不抛错。
- **CLI 与 GUI 同源**：`SwiftSeekSearch` 未改动，parser 自然生效。

## 环境约束

### 必须在 macOS 13+ 上构建与运行
- 目标 `.macOS(.v13)`
- Apple Silicon 与 Intel 都可用，release 二进制跟随本机架构

### 无 Xcode.app 时只能 SwiftPM 构建
- 仓库未提供 `.xcodeproj` / `.xcworkspace`
- 仅安装 `CommandLineTools` 的机器可用 `swift build` / `swift run ...`

### 无 code signing / notarization / .app bundle
- 当前交付路径是 `scripts/build.sh` → `.build/release/SwiftSeek`
- 正式 `.app` bundle + 签名 + 公证不在当前范围内

### 受限沙箱下的构建约束
- 需要：

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/build.sh --sandbox
```

## 明确不做
- 全文内容搜索
- OCR
- AI 语义搜索
- 云盘 / 网络盘实时一致性承诺
- 跨平台
- Electron / Tauri / Web UI 替代原生
- APFS 原始解析
- Finder 插件
- App Store 沙盒适配

## 运行时补充说明

### disable root 语义
- 停用：保留已索引数据，但搜索不返回
- 启用：无需重建，搜索立即恢复
- 移除：级联清理该 root 下记录

### hidden / exclude 生效方式
- 新增 exclude 时会立即清理已索引子树
- hidden 开关切换后，对已有索引数据仍需重建才能完全体现

### 搜索结果上限
- 可配置项，持久化到 DB 的 settings 表
- 默认 100，范围 [20, 1000]
- 超过后写入被 clamp 到边界
- 设置页 → 常规 → 搜索结果上限

### Gatekeeper 首次运行拦截
- release 可执行首次运行可能被 Gatekeeper 拦截
- 这属于未签名交付的预期限制
