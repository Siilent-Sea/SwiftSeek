# SwiftSeek 已知问题 / 当前限制

本文档记录当前用户真实会感知到的限制。历史轨道已经完成的能力不重复包装成新成果；当前重点是 `everything-usage` 暴露的使用历史、打开次数和 Everything-like 体验差距。

## 当前活跃轨道相关限制

### 1. 不能读取 macOS 全局启动次数
- SwiftSeek 不应承诺读取系统级 Run Count、全局 App 启动次数或其他工具的打开历史。
- macOS 没有适合作为普通 App 稳定读取这类数据的公开、低风险接口。
- 后续 `Run Count` 语义必须限定为：**通过 SwiftSeek 打开的次数**。
- 不使用 private API，不扫描系统隐私数据。

### 2. SwiftSeek 内部 open count 已在 H1 落地
- Schema v6 新增 `file_usage` 表，字段：`file_id`（PK，`ON DELETE CASCADE` 关联 `files.id`）/ `open_count` / `last_opened_at` / `updated_at`。
- `ResultActionRunner.perform(.open)` 返回 Bool（`NSWorkspace.shared.open(url)` 结果）。
- `SearchViewController.openSelected()` 成功后调 `Database.recordOpen(path:)`，UPSERT `open_count+=1` + 两个时间戳。
- 打开失败或目标路径不在 DB → 不累加；未索引 path 会 `NSLog` 诊断，不 silent fail。
- 文件从 `files` 删除后 usage 记录随外键级联清理（`PRAGMA foreign_keys=ON`）。
- **Run Count 语义**：仅表示通过 SwiftSeek 触发 `.open` 的次数。**不代表 macOS 全局启动次数**；不读 system 最近项目、不用 private API。
- H1 只做数据模型 + 动作记录。ranking tie-break / 结果列 / 最近打开入口 / 隐私开关留给 H2-H4。

### 3. 当前排序不含 usage tie-break
- `SearchResult` 只有 path/name/isDir/size/mtime/score。
- `SearchEngine.sort` 只支持 score/name/path/mtime/size。
- 同等文本相关性下，常用文件不会因为打开次数更高而靠前。

### 4. 当前结果视图没有 Run Count / 最近打开信息
- 结果表已有名称 / 路径 / 修改时间 / 大小。
- 但没有打开次数、最近打开、usage score 或 Run Count 列。
- 用户也无法按打开次数或最近打开排序。

### 5. 当前没有使用历史清理 / 隐私控制
- 设置页没有“记录使用历史”开关。
- 设置页没有“清空使用历史”入口。
- DB stats 尚未展示 usage 表大小和行数。
- 后续引入 usage 后必须补隐私控制，否则不应进入最终收口。

## 已归档轨道后的保留限制

### DB footprint（G1-G5 已解决主路径）
- Compact 模式（默认）已将 500k 实测 main DB 从 fullpath 3.46 GB 降到 1.07 GB。
- Full path substring 模式仍可选，但体积更大。
- VACUUM / checkpoint 仍是维护入口，不是替代 compact 的根治方案。
- 500k 下 warm 3+char 会超出 F1 在 10k 规模时设定的旧目标，这是已记录的规模效应事实，不是 usage 轨道范围。

### 搜索相关性
- 当前已有 plain token AND、basename / token boundary / path segment / extension bonus。
- 但它仍是启发式相关性，不是成熟 Everything ranking 模型。
- usage-based tie-break 尚未实现，属于当前 `everything-usage` 轨道。

### 查询 DSL
- 已支持 `ext:` / `kind:` / `path:` / `root:` / `hidden:`。
- 不支持 OR / NOT / 括号 / 引号短语 / 复杂布尔组合。

### RootHealth
- 已有 ready / indexing / paused / offline / unavailable。
- 设置页 roots 列表和搜索 0 结果空态会暴露部分状态。
- RootHealth 与 usage 无直接关系，本轨道不扩 root 状态模型。

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
- macOS 全局启动次数读取
- 系统隐私数据扫描

## 运行时补充说明

### disable root 语义
- 停用：保留已索引数据，但搜索不返回。
- 启用：无需重建，搜索立即恢复。
- 移除：级联清理该 root 下记录。

### Gatekeeper 首次运行拦截
- release 可执行首次运行可能被 Gatekeeper 拦截。
- 这属于未签名交付的预期限制。
