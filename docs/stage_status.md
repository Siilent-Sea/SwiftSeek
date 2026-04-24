# SwiftSeek Track Status

## 轨道总览
- 当前活跃轨道：`everything-alignment`
- 当前阶段：`E2`（多列结果视图 + 排序切换；功能落地，等待 Codex 验收）
- 已归档轨道：`v1-baseline`
- 轨道内已通过阶段：`E1`（2026-04-24 Codex round 2 PASS，session 019dbd4c-e0c9-7370-8a0c-1d4263a9f19b）

## 已归档轨道：`v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0 ~ P6
- 说明：这条记录只代表 v1 baseline 已完成，不是当前活跃轨道的停止条件

## 当前活跃轨道：`everything-alignment`

### 已通过：`E1`（搜索相关性与结果上限）
- 多词 AND 语义
- 4 个加分规则（basename +50、token boundary +30、path segment +40、extension +80）+ 多词 all-in-basename +100
- 搜索结果上限持久化设置，默认 100，范围 [20, 1000]
- 测试：smoke 61/61（含 10 条 E1 覆盖）

### 当前阶段：`E2`
结果视图密度 + 排序切换。

### 当前阶段目标（均已落地，待 Codex 验收）
- ✅ 结果视图升级到 4 列（名称 / 路径 / 修改时间 / 大小）
- ✅ 列标题可点击切换排序
- ✅ 排序维度：score（默认）/ name / path / mtime / size
- ✅ 排序逻辑下沉到 `SearchEngine.sort()`，pure function，smoke 可测
- ✅ 排序保留已选择结果位置；切回默认等价 `.scoreDescending`
- ✅ 键盘流 / 右键菜单 / 拖拽 / QuickLook / 高亮行为保留不回退
- ✅ smoke 覆盖：默认 score-desc、name 升降序、mtime desc、size asc、可逆、tie-break、大小写不敏感

### 当前阶段禁止事项（仍然生效）
- 不做 query DSL（E3）
- 不做 root 状态 / 自动索引（E4）
- 不做热键配置（E5）
- 不做全文搜索 / OCR / AI 语义
- 不做预览面板重构

### 当前代码状态（E2 快照）
- `Sources/SwiftSeekCore/SearchEngine.swift`
  - 新 `SearchSortKey`（score / name / path / mtime / size）
  - 新 `SearchSortOrder`（key + ascending）+ `.scoreDescending` static
  - 新 `SearchEngine.sort(_:by:)` 静态方法，tie-break 稳定
- `Sources/SwiftSeek/UI/SearchViewController.swift`
  - 4 列 `NSTableColumn` + `NSTableHeaderView` + `sortDescriptorPrototype`
  - `tableView(_:sortDescriptorsDidChange:)` 映射 AppKit descriptor → `SearchSortOrder`
  - `rawResults` 保存原始 ranked 结果供重排
  - 新 cell 类型：`NameColumnCell`（icon + 高亮名字，异步加载 Finder icon）、`PathColumnCell`（高亮父目录，tooltip 全路径）、`PlainColumnCell`（mtime / size）
  - `highlightTokens` 多 token 高亮共享函数
  - `MtimeFormatter` / `SizeFormatter` 单例复用
  - 保留 QuickLook、右键菜单、拖拽、选择保持、空态、toast、⌘Y、⌘⏎、⌘⇧C
- `Sources/SwiftSeekSmokeTest/main.swift`
  - 新增 7 条 E2 测试（score 默认、name 升降、mtime desc、size asc、可逆、tie-break、大小写不敏感）
  - 总数 51 + 10 (E1) + 7 (E2) = 68 全绿

### 当前阶段完成判定标准
1. ✅ 结果密度明显高于单列 cell 模式
2. ✅ 清楚展示 name / path / mtime / size
3. ✅ 至少一种可切换排序方式（本实现覆盖 5 种 key）
4. ✅ 打开 / Reveal / Copy Path / QuickLook / 拖拽 / 右键 / 高亮 不回退
5. ✅ `swift build` + smoke 全绿
6. ✅ 新增 E2 smoke 覆盖稳定性 + 可逆性

### 当前最新 Codex 结论
- 轨道内最新 PASS：`E1 / round 2 / 2026-04-24`
- 当前阶段（E2）：等待 round 1 验收

### 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 当前 session id：`019dbd4c-e0c9-7370-8a0c-1d4263a9f19b`（E1 round 1 起沿用）
- 恢复策略：`codex exec resume <session_id>`
