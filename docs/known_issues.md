# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制，不把“已经部分落地”写成“已经完全解决”。

## 当前活跃轨道相关限制

### 1. 短查询性能（F1 已改进）
- 2 字符查询走新的 `file_bigrams` 倒排索引路径（Schema v4）
- 不再以 `%token%` LIKE 全表扫描为主路径
- 1 字符查询仍保留 LIKE fallback（低频场景，保留兜底）
- 实测 release build 10k 文件：warm 2-char median 2-4ms
- 仍会受数据库规模影响；100k+ 的大库需单独观测

### 2. 搜索热路径开销（F1 已改进）
- SearchEngine 有 prepared statement cache（SQL 串 → `OpaquePointer`）
- Database 有 roots cache 和 settings cache
- 写路径自动 invalidate
- 实测 bench 10k 文件 50 iters：stmt cache 98.6% hit、roots cache 99.7% hit

### 3. 搜索相关性的真实现状
- 现在已经不是最早的 baseline：
  - plain token AND 已有
  - basename / token boundary / path segment / extension bonus 已有
- 但它仍是 substring + bonus 的第一版启发式
- 还谈不上成熟的 Everything-like 相关性模型

### 4. 结果上限的真实现状（F2 已收口）
- GUI：
  - `search_limit` 持久化到 `settings` 表
  - 设置页可改，范围 [20, 1000]，默认 100
  - 搜索窗口热路径读取该值（F1 起 settings cache 命中，几乎零开销）
- CLI：
  - `SwiftSeekSearch` 默认读取 `settings.search_limit`，与 GUI 同源
  - `--limit N` 显式覆盖保留（脚本 / 一次性调试用）
  - stderr 日志显式标注 limit 来源（`settings.search_limit` vs `--limit override`）
- GUI 与 CLI 在默认行为上已一致；旧的"CLI 固定 20"口径已过期。

### 5. roots 健康状态的真实现状（F4 已扩大覆盖）
- `RootHealth` 类型：ready / indexing / paused / offline / unavailable
- 设置页 roots 列表显示状态 badge（E4 起）
- F4 起：搜索窗口 0 结果空态提示会列出 offline / unavailable / paused 的 root 路径，让用户可以判断"为什么没结果"而不是默认以为是查询打错了

### 6. 结果视图的真实现状
- 结果视图已经不是单列 launcher：
  - 名称 / 路径 / 修改时间 / 大小 四列都已存在
  - 已支持列头排序
- 但当前仍只是第一版多列结果视图，还不算真正成熟的高密度文件搜索器视图

### 7. DSL 的真实现状（F4 已收口一轮）
- 已支持：
  - `ext:<a,b,c>`（多扩展名逗号分隔）
  - `kind:file` / `kind:dir`
  - `path:<token>`（多词 AND 组合，token 可任意长）
  - `root:<prefix>`（路径前缀匹配，处理 `/` 边界）
  - `hidden:true` / `hidden:false`（接受 true/false/yes/no/1/0/on/off 多种别名）
- 组合语义：所有 filter 之间 AND；filter 可与 plain query 组合
- filter-only 查询候选路径优先级（F4 更新）：
  1. `path:` token ≥3 字符 → `file_grams`（trigram）
  2. `path:` token ==2 字符 → `file_bigrams`（bigram）
  3. `ext:` → `name_lower LIKE '%.ext'`（trailing wildcard，B-tree 可用）
  4. `root:` → `path_lower LIKE 'prefix/%'`
  5. `kind:` → `is_dir = ?`
  6. bounded scan 兜底（只有 `hidden:` 单独使用时触发）
- 不支持：OR / NOT / 括号 / 引号短语 / 复杂布尔组合

### 8. 索引自动化的真实现状
- add root 后已自动后台索引
- hidden 开关会提示立即重建或稍后
- exclude 新增会立即清理已索引子树
- 但索引自动化、状态反馈和最终用户心智仍未完全收口

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

### Gatekeeper 首次运行拦截
- release 可执行首次运行可能被 Gatekeeper 拦截
- 这属于未签名交付的预期限制
