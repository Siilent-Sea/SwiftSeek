# SwiftSeek 与更接近 Everything 的当前差距

这份文档只基于当前真实代码写，重点看两件事：
1. 性能
2. 真正落地到代码的功能差距

历史 `everything-alignment` 文档现在只能当归档参考，不能继续当当前事实。

---

## 1. 搜索热路径：短查询仍走 `%LIKE%` 全表式扫描

### 当前现状
- `Sources/SwiftSeekCore/SearchEngine.swift`
  - 2 字符 query 会进入 `likeCandidates(token:limit:)`
  - SQL 形态是：
    - `WHERE name_lower LIKE ? OR path_lower LIKE ?`
    - 绑定值是 `%token%`
- 当前库里虽然有：
  - `idx_files_name_lower`
  - `idx_files_path_lower`
- 但这种 leading-wildcard 查询形态很难真正吃到 B-tree 索引红利

### 为什么这是缺口
- 这正是“明明建了索引但搜起来仍慢”的核心来源
- 2 字符 query 是高频输入阶段，Everything-like 体验最怕这个阶段卡顿

### 推荐优先级
- 高

### 适合放在哪个 F 阶段解决
- `F1`

---

## 2. 搜索热路径：3+ 字符虽走 gram，但仍有重复开销

### 当前现状
- `SearchEngine` 的 3+ 字符查询已经走 `file_grams`
- 但每次搜索仍会：
  - 重新 `sqlite3_prepare_v2`
  - 重新 `database.listRoots()`
- `SearchViewController.runQuery` 每次还会先 `database.getSearchLimit()`
- 空状态渲染时也会再次 `database.listRoots()`

### 为什么这是缺口
- 即使主检索结构对了，热路径上持续做 prepare / roots 读取 / settings 读取，也会把延迟重新垫高
- 这类开销在短 query 高频输入下会累计得很明显

### 推荐优先级
- 高

### 适合放在哪个 F 阶段解决
- `F1`

---

## 3. 缺少真正的 benchmark / perf probe

### 当前现状
- 当前只有：
  - `SwiftSeekSearch` 打印单次 elapsed time
  - GUI 状态栏显示 `ms`
- 仓库里没有真正的 benchmark harness
- 也没有 warm search timing 的固定验收目标

### 为什么这是缺口
- 没有 probe，就无法证明热路径优化是否真实生效
- 后续很容易再次回退到“体感快了一点”的主观判断

### 推荐优先级
- 高

### 适合放在哪个 F 阶段解决
- `F1`

---

## 4. `search_limit` 已存在，但文档与 CLI 仍漂移

### 当前现状
- `Sources/SwiftSeekCore/SettingsTypes.swift`
  - 已有 `SettingsKey.searchLimit`
  - 已有 `getSearchLimit()` / `setSearchLimit(_:)`
- `Sources/SwiftSeek/UI/SearchViewController.swift`
  - GUI 查询热路径已经会读 `database.getSearchLimit()`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
  - 常规页已有结果上限输入
- 但 `Sources/SwiftSeekSearch/main.swift`
  - CLI 默认 `limit` 仍是固定 20

### 为什么这是缺口
- 旧文档里“GUI limit 没接上”已经不是真相
- 但“GUI/CLI limit 语义已完全统一”同样也不是真相
- 这是典型的代码与文档双向漂移

### 推荐优先级
- 中

### 适合放在哪个 F 阶段解决
- `F2`

---

## 5. 搜索相关性已不是 baseline，但仍不够 Everything-like

### 当前现状
- `SearchEngine` 已经有：
  - plain token AND
  - basename bonus
  - token boundary bonus
  - path segment bonus
  - extension bonus
- 但本质仍是 substring + rule bonus 的启发式
- 还没有更细的候选收窄、权重校准、usage 信号或更稳定的 tie-break 体系

### 为什么这是缺口
- 旧 `everything_gap.md` 把它写成“仍完全 baseline”已经不对
- 但把它写成“已经足够接近 Everything”也不对
- 当前状态更准确的说法是：相关性规则已经起步，但仍只是第一层

### 推荐优先级
- 高

### 适合放在哪个 F 阶段解决
- `F2`

---

## 6. 结果视图已经是多列，但仍离文件搜索器感有距离

### 当前现状
- `SearchViewController` 已是 4 列：
  - 名称
  - 路径
  - 修改时间
  - 大小
- 支持列头点击排序
- `rowHeight = 22`
- 但仍是较轻量的 `NSTableView` 表层升级

### 为什么这是缺口
- 旧文档里“还是单列 launcher”已经失真
- 但当前也还谈不上成熟的高密度文件搜索器结果视图
- 列布局、排序入口、显示密度、状态保留都还有进一步打磨空间

### 推荐优先级
- 中

### 适合放在哪个 F 阶段解决
- `F3`

---

## 7. 查询 DSL 已经起步，但仍只是第一版

### 当前现状
- 当前已支持：
  - `ext:`
  - `kind:`
  - `path:`
  - `root:`
  - `hidden:`
- 但仍不支持：
  - OR / NOT
  - 括号
  - 引号短语
  - 更复杂的组合规则
- 对 filter-only 查询，`path:` / `hidden:` 这类场景仍会落到 bounded scan fallback

### 为什么这是缺口
- 旧文档里“完全没有 DSL”已经不准确
- 但当前 DSL 的能力边界还比较窄，且部分路径仍不够高效

### 推荐优先级
- 中

### 适合放在哪个 F 阶段解决
- `F4`

---

## 8. `RootHealth` 已接到 roots UI，但还没有形成完整用户心智

### 当前现状
- `SettingsTypes.swift` 已有 `RootHealth`
- `SettingsWindowController` 的 roots 列表已经显示：
  - 就绪
  - 索引中
  - 停用
  - 未挂载
  - 不可访问
- add root 自动后台索引也已接上
- 但这些状态主要仍停留在设置页 roots 列表

### 为什么这是缺口
- 当前用户仍很难从搜索主路径、诊断视图、菜单栏状态里统一理解“为什么这个 root 没结果”
- 也还没有把 root 健康与搜索行为、索引行为的关系说明得足够完整

### 推荐优先级
- 中

### 适合放在哪个 F 阶段解决
- `F4`

---

## 9. 索引自动化已起步，但整体链路还不算彻底

### 当前现状
- add root 后已自动后台索引
- hidden 开关会弹“立即重建 / 稍后”
- exclude 新增会立即清理已索引子树
- 但索引自动化、状态反馈、性能观测、最终用户心智还没有完全收口

### 为什么这是缺口
- 这说明“完全手动”的旧文档已经不准确
- 但离“设置改动之后系统行为足够自解释、足够稳”还有一段路

### 推荐优先级
- 中

### 适合放在哪个 F 阶段解决
- `F5`

---

## 为什么要新开 `everything-performance`
- 现在最突出的真实差距，不再只是“有没有某个功能”
- 而是：
  - 搜索热路径是否真的快
  - 已经声称落地的功能是否真的落地到代码
  - 文档是否反映当前真实状态
- 因此，新轨道不再适合继续叫 `everything-alignment`
- 更准确的名字是 `everything-performance`：先把性能和真实落地程度做实，再继续谈更像 Everything
