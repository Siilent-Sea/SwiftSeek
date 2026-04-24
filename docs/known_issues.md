# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。历史轨道已经完成的能力不重复包装成新成果；当前重点是 `everything-footprint` 暴露的大库体积和维护问题。

## 当前活跃轨道相关限制

### 1. 500k+ 文件下 DB 可显著膨胀
- 当前 schema v4 同时维护 `file_grams` 和 `file_bigrams`。
- 两张表都按 `(file_id, gram)` 存储，文件数上来后行数会随每个文件的 basename 和 full path 长度增长。
- 用户真实使用中已反馈主 DB 可膨胀到数 GB。
- 这不是单纯 VACUUM 能根治的问题，核心在当前索引策略本身体积成本偏高。

### 2. `file_bigrams + file_grams` 是主要体积来源
- `Gram.indexGrams(nameLower:pathLower:)` 与 `Gram.indexBigrams(nameLower:pathLower:)` 都把完整路径纳入滑窗。
- full path 往往比文件名长得多，深目录和长路径会产生大量 gram 行。
- `PRIMARY KEY(file_id, gram)` 只能去掉同一个文件内重复 gram，不能减少跨文件共同路径前缀带来的行数规模。

### 3. v4 migration 在大库上有巨型事务风险
- `Database.migrate()` 对 pending migrations 使用单个 `BEGIN IMMEDIATE` / `COMMIT`。
- v4 `backfillFileBigrams()` 在迁移路径中执行。
- backfill 会先 `SELECT id, name_lower, path_lower FROM files` 并把所有行装进 Swift 数组，然后写入 `file_bigrams`。
- 对大库，这可能导致 WAL 暴涨、启动迁移耗时很长、失败回滚成本高。

### 4. 当前缺少 DB footprint 观测
- App 内没有清楚展示：
  - DB 总大小
  - WAL 大小
  - `file_grams` 行数
  - `file_bigrams` 行数
  - 每文件平均 gram 数
  - 各 root 贡献的索引规模
- `SwiftSeekBench` 目前主要测 warm search timing，不测 DB size 和 table size。
- `SwiftSeekIndex` 目前只输出 roots/files 行数。

### 5. 当前缺少 App 内维护入口
- 当前代码没有产品化的 checkpoint / optimize / VACUUM 入口。
- 用户只能手工用 sqlite3 处理 WAL 和压实。
- VACUUM / checkpoint 可临时压实或回收 WAL，但不是根治 full-path gram 膨胀的方案。
- VACUUM 还需要额外临时空间，并可能耗时较长，不能无提示自动执行。

### 6. 当前索引策略不可配置
- 默认总是把完整路径纳入 bigram/trigram。
- 用户无法选择“紧凑模式 / 完整路径子串模式”。
- 对 500k+ 文件长期使用，更合理的方向是引入 compact index：默认降低路径滑窗成本，把 full-path substring 作为高级可选模式。

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
