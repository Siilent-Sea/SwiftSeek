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

### 4. 结果上限的真实现状（F2 收口）
- GUI：
  - 已有 `search_limit`
  - 设置页可改
  - 搜索窗口热路径已读取该值（F1 起 settings cache 命中）
- CLI：
  - `SwiftSeekSearch` 默认仍是固定 20
  - 需要 `--limit` 才能改
  - F2 阶段会把 CLI 默认值对齐到 DB 的 `search_limit`

### 5. roots 健康状态的真实现状
- `RootHealth` 类型已存在
- roots UI 已显示：
  - 就绪
  - 索引中
  - 停用
  - 未挂载
  - 不可访问
- 但这些状态主要还停留在设置页 roots 列表，尚未形成更完整的跨页面用户心智

### 6. 结果视图的真实现状
- 结果视图已经不是单列 launcher：
  - 名称 / 路径 / 修改时间 / 大小 四列都已存在
  - 已支持列头排序
- 但当前仍只是第一版多列结果视图，还不算真正成熟的高密度文件搜索器视图

### 7. DSL 的真实现状
- 当前已支持：
  - `ext:`
  - `kind:`
  - `path:`
  - `root:`
  - `hidden:`
- 当前仍不支持：
  - OR
  - NOT
  - 括号
  - 引号短语
- 对部分 filter-only 查询，当前仍会走 bounded scan fallback

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
