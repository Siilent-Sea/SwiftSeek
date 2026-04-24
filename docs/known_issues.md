# SwiftSeek 已知问题 / 当前限制

本文档记录当前仓库的已知限制。这里列的是“当前就是这样”，不是单纯 bug 乱报。

## 当前活跃轨道视角下的明显限制

### 1. 查询语法尚未支持（留给 E3）
- 当前只有 plain text query（E1 已支持多词 AND）
- 尚不支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:` 等过滤语法
- E3 阶段专门处理查询语法与过滤能力

### 2. 结果列表还不是高密度 Everything 风格（留给 E2）
- 当前 `SearchViewController` 仍是单列表单元格视图
- 名称 / 路径 / mtime / size 虽有部分展示，但不是高密度多列结果视图
- 目前也没有排序切换或列排序
- E2 阶段专门处理结果视图与排序 / 显示密度

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

以下三项在 E1 阶段已经落地（本文件同步移除“尚未”状态）：

- **多词 query AND 语义**：`SearchEngine.tokenize` + 逐 token substring AND filter。
- **相关性细粒度 bonus**：basename (+50) / token boundary (+30) / path segment (+40) / extension (+80) / 多词 all-in-basename (+100)。
- **GUI 结果上限可配置**：`search_limit` 持久化到 settings 表，范围 [20, 1000]，默认 100；设置页常规 pane 提供配置入口；SearchViewController 每次查询读取，状态栏动态回显“仅显示前 N 条”。

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
