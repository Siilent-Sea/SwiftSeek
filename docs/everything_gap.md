# SwiftSeek 与 Everything-like 体验的当前差距

> Archived note:
> 这份文档是 `everything-alignment` 轨道的历史 gap 快照。
> 它不再代表当前事实，尤其不再覆盖当前最突出的热路径性能问题。
> 当前应优先查看 [docs/everything_performance_gap.md](docs/everything_performance_gap.md)。

本文档只基于当前真实仓库写，不按理想空项目脑补。

---

## 1. 搜索相关性

### 当前现状
- `Sources/SwiftSeekCore/SearchEngine.swift`
  - `normalize(_:)` 只做 trim / lowercase / 空白折叠
  - `search(_:)` 对 plain query 仍按单个完整字符串走候选召回和最终包含判断
  - `score()` 只有 4 档：
    - 文件名精确命中 1000
    - 文件名前缀 800
    - 文件名包含 500
    - 仅路径包含 200

### 为什么是缺口
- Everything-like 文件搜索器最关键的是“多词 query 能不断收窄”与“高质量命中稳定排前”
- 当前实现对多词 query 仍偏 baseline 级别，不能很好处理 basename、token 边界、路径段、扩展名这些常见排序信号

### 推荐优先级
- 高

### 适合放在哪个后续阶段解决
- `E1`

---

## 2. 结果密度 / 结果视图

### 当前现状
- `Sources/SwiftSeek/UI/SearchViewController.swift`
  - `NSTableView` 只有一个 column
  - `headerView = nil`
  - `rowHeight = 36`
  - `ResultCell` 以单 cell 方式混合展示图标、名称、路径和右侧少量 metadata
  - 没有列排序，也没有排序切换 UI

### 为什么是缺口
- 当前视图更像“轻量 launcher 列表”，不是高密度文件搜索器列表
- 当结果量上来后，用户无法快速扫出 name / path / mtime / size，也无法按不同维度切换

### 推荐优先级
- 高

### 适合放在哪个后续阶段解决
- `E2`

---

## 3. 查询语法 / 过滤能力

### 当前现状
- 当前 query 入口只有原始文本
- 仓库中没有 query parser，也没有 `ext:` / `kind:` / `path:` / `root:` / `hidden:` 这类字段过滤
- `SwiftSeekSearch` 目前只支持 `--limit`、`--show-score` 这类 CLI 参数

### 为什么是缺口
- Everything-like 使用习惯里，字段过滤是效率核心
- 现在用户只能依赖字符串匹配和有限排序，复杂查询成本高

### 推荐优先级
- 高

### 适合放在哪个后续阶段解决
- `E3`

---

## 4. 索引自动化体验

### 当前现状
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
  - `onAddRoot()` 最后走 `promptRebuildAfterAdd`
  - 现状是弹窗询问“是否立即建立索引”，不是自动后台开始
  - hidden 开关切换后说明文字要求用户手动点“立即重建”
  - exclude 新增时会立即 `deleteFilesMatchingExclude`，但整体自动化体验还不统一
- `Sources/SwiftSeekCore/RebuildCoordinator.swift`
  - 当前主要承担手动 rebuild 流程

### 为什么是缺口
- Everything-like 体验不是“加目录后再自己决定要不要重建”，而是系统默认知道应该开始工作
- 当前设置改动与索引状态之间的用户心智链路仍然偏手动

### 推荐优先级
- 高

### 适合放在哪个后续阶段解决
- `E4`

---

## 5. 热键与用户设置

### 当前现状
- `Sources/SwiftSeek/App/GlobalHotkey.swift`
  - `defaultKeyCode` 与 `defaultModifiers` 是固定常量
- `SettingsWindowController` 没有热键自定义 UI
- 搜索结果上限也尚未以用户设置形式暴露

### 为什么是缺口
- 文件搜索器是高频工具，热键和结果规模都是习惯层面的核心设置
- 当前只能“接受默认”或“改代码重编译”，不适合继续迭代后的日常使用

### 推荐优先级
- 中

### 适合放在哪个后续阶段解决
- 热键：`E5`
- 结果上限设置化：`E1`

---

## 6. 外接盘 / root 状态感知

### 当前现状
- `SettingsWindowController` 当前能展示 roots、启用停用、移除
- `AboutPane` 主要展示数量与数据库信息，不展示 root 在线 / 离线 / 不可访问状态
- `docs/known_issues.md` 也已经承认：外接盘弹出后的索引残留主要靠手工移除 root 或重建

### 为什么是缺口
- Everything-like 的一个重要体验点是：用户能知道某个 root 现在为什么没结果，是未索引、离线、还是不可访问
- 当前 SwiftSeek 对 root 健康状态的反馈还不够直接

### 推荐优先级
- 中

### 适合放在哪个后续阶段解决
- `E4`

---

## 当前主路线判断
- `E1` 先处理相关性与结果上限，是因为这些问题已经直接写在 `SearchEngine.swift` 和 `SearchViewController.swift` 里，且不需要先做大 UI 改版
- `E2` 再做结果视图，是为了避免在相关性还没稳定前就先重写展示层
- `E3` 再引入 query 语法，能避免把 parser 和排序一起搅在第一阶段
- `E4` 统一处理索引自动化与 root 健康，是因为它们都属于“系统状态是否自解释”
- `E5` 最后收热键自定义、使用习惯优化和文档收尾，风险最低
