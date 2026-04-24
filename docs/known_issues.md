# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。历史轨道已经完成的能力不重复包装成新成果；当前重点是 `everything-footprint` 暴露的大库体积和维护问题。

## 当前活跃轨道相关限制

### 1. 500k+ 文件下 DB 体积（G1-G5 已解决根治路径）
- **Compact 模式（默认）**：只对 basename 做 gram + path segment 前缀索引。20k 实测 DB 比 fullpath 小 3.2×，索引行数少 5.5×，首次索引快 4.7×。500k 投影 compact ~1GB vs fullpath ~3.2GB。
- **Full path substring 模式**：保留 v4 行为，path 中间子串可搜；体积大。
- 现有 fullpath v4 DB 升级到 v5 默认保留为 fullpath；可在设置 → 常规 → 索引模式切换到 compact，维护 tab 按 "开始 / 继续 compact 回填" 后台回填，期间不阻主。
- VACUUM 仍作为临时压实入口保留（维护 tab），但已不是根治方案 —— 根治靠 compact 模式 + 一次性回填。

### 2. `file_bigrams + file_grams` 是主要体积来源
- `Gram.indexGrams(nameLower:pathLower:)` 与 `Gram.indexBigrams(nameLower:pathLower:)` 都把完整路径纳入滑窗。
- full path 往往比文件名长得多，深目录和长路径会产生大量 gram 行。
- `PRIMARY KEY(file_id, gram)` 只能去掉同一个文件内重复 gram，不能减少跨文件共同路径前缀带来的行数规模。

### 3. v5 migration 已避开巨型事务（G3 已解决）
- `Database.migrate()` v4→v5 分支 CREATE-only + seed `settings.index_mode`，不跑 backfill
- compact backfill 由 `MigrationCoordinator` 后台分批执行（默认 5000 行/批，每批独立事务 + WAL PASSIVE checkpoint），可中断续跑（`migration_progress.compact_backfill_last_file_id`）
- v2→v4 迁移仍有旧的 backfill（`file_grams` / `file_bigrams`），但那是 v3→v4 跃迁，G3 没动；新库一般直接命中 v5。

### 4. DB footprint 观测（G1 已解决）
- CLI `SwiftSeekDBStats`：main/wal/shm 大小、page 信息、六张表行数、平均 grams per file、dbstat per-table 明细（支持时）/ row-count fallback
- Settings → 维护 tab：DB 体积 block 同上 + 刷新 / WAL checkpoint / Optimize / VACUUM 按钮（VACUUM 二次确认）
- `SwiftSeekBench --mode both`：compact vs fullpath 对比报告

### 5. App 内维护入口（G1 / G4 已解决）
- 设置 → 维护 tab 提供 WAL checkpoint / Optimize / VACUUM（二次确认 + 风险说明）/ 开始或继续 compact 回填
- CLI `SwiftSeekDBStats --run {checkpoint,optimize,vacuum}` 等价命令行入口
- 所有维护走后台队列，GUI 不阻塞

### 6. 索引策略可配置（G3 / G4 已解决）
- 设置 → 常规 → 索引模式下拉：Compact（推荐）/ Full path substring（高级）
- 每个新 DB 默认 compact；v4 升级默认 fullpath（保留用户现有搜索能力）
- 切换有二次确认 + 引导回填 / 重建

## 仍然存在但已非当前主线的问题

### 搜索相关性
- 当前已经有 plain token AND、basename / token boundary / path segment / extension bonus。
- 但它仍是第一版启发式相关性，不是成熟 Everything ranking 模型。

### 结果视图
- 当前已经有名称 / 路径 / 修改时间 / 大小四列、列头排序、较高密度显示。
- 但与成熟文件搜索器相比，仍有进一步打磨空间。

### 查询 DSL
- 已支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:`。
- 不支持 OR / NOT / 括号 / 引号短语 / 复杂布尔组合。

### RootHealth
- 已有 ready / indexing / paused / offline / unavailable。
- 设置页 roots 列表和搜索 0 结果空态会暴露部分状态。
- 但 root 级索引体积归因尚未接入，这属于 `everything-footprint` 后续范围。

## 环境约束

### 必须在 macOS 13+ 上构建与运行
- 目标 `.macOS(.v13)`。
- Apple Silicon 与 Intel 都可用，release 二进制跟随本机架构。

### 无 Xcode.app 时只能 SwiftPM 构建
- 仓库未提供 `.xcodeproj` / `.xcworkspace`。
- 仅安装 Command Line Tools 的机器可用 `swift build` / `swift run ...`。

### 无 code signing / notarization / .app bundle
- 当前交付路径是 `scripts/build.sh` 到 `.build/release/SwiftSeek`。
- 正式 `.app` bundle + 签名 + 公证不在当前范围内。

### 受限沙箱下的构建约束
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
- 停用：保留已索引数据，但搜索不返回。
- 启用：无需重建，搜索立即恢复。
- 移除：级联清理该 root 下记录。

### Gatekeeper 首次运行拦截
- release 可执行首次运行可能被 Gatekeeper 拦截。
- 这属于未签名交付的预期限制。
