# SwiftSeek Track Status

## 轨道总览
- 当前活跃轨道：**（无活跃轨道）** `everything-alignment` 已完成
- 已归档轨道：`v1-baseline`（P0–P6 / PROJECT COMPLETE 2026-04-23）
- 已归档轨道：`everything-alignment`（E1–E5 / PROJECT COMPLETE 2026-04-24）

## 已归档轨道：`v1-baseline`
- 状态：`PROJECT COMPLETE`
- 完成日期：2026-04-23
- 范围：P0 ~ P6

## 已归档轨道：`everything-alignment`
- 状态：`PROJECT COMPLETE`（Codex 2026-04-24 E5 round 1 颁发）
- session id：`019dbd4c-e0c9-7370-8a0c-1d4263a9f19b`
- 阶段记录：
  - E1 — 搜索相关性与结果上限（round 2 PASS）
  - E2 — 结果视图与排序切换（round 2 PASS）
  - E3 — 查询语法与过滤（round 1 PASS）
  - E4 — 索引自动化 + root 状态（round 2 PASS）
  - E5 — 热键配置 + 使用习惯优化 + 收尾（round 1 PROJECT COMPLETE）

## 历史阶段详情（归档保留）

### E5（热键自定义 + 使用习惯优化 + 收尾文档）

### 当前阶段目标（均已落地）
- ✅ 全局热键可配置（SettingsTypes `HotkeyPresets` 5 个预设）
- ✅ `Database.{get,set}Hotkey(keyCode:modifiers:)`，持久化到 settings 表
- ✅ AppDelegate 启动读持久化组合 + 提供 `reinstallHotkey()` 供设置页重注册
- ✅ GeneralPane 加热键下拉选单；切换时持久化 + 触发 reinstall；失败时回滚并弹窗
- ✅ 文档收尾：README / manual_test / known_issues / stage_status 对齐 E5 最终行为
- ✅ 5 条 E5 smoke 覆盖（预设完整性 / 全 Space 键 / getHotkey 默认值 / round-trip 所有预设 / 非法值 fallback）
- ✅ 手测对齐（见 docs/manual_test.md 新增章节）

### 当前阶段禁止事项
- 不引入新的搜索后端
- 不做大规模 UX 重写
- 不碰 E1-E4 已 sealed 能力

### 当前代码状态（E5 快照）
- `Sources/SwiftSeekCore/SettingsTypes.swift`
  - `HotkeyPreset` / `HotkeyPresets`（5 个 Spotlight 风格预设，Carbon constants 本地化避免 Core 依赖 Carbon）
  - `Database.getHotkey()` / `setHotkey(keyCode:modifiers:)` extension，默认值 = HotkeyPresets.default，malformed → 默认
- `Sources/SwiftSeek/App/AppDelegate.swift`
  - `installGlobalHotkey` 读持久化组合
  - 新 `reinstallHotkey()` public；调用方传给 SettingsWindowController 构造
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
  - SettingsWindowController init 加 `hotkeyReinstallHandler` 参数
  - GeneralPane 加 `hotkeyPopup` NSPopUpButton；`onHotkeyChanged` 动作 persist + reinstall + 失败回滚
- `Sources/SwiftSeekSmokeTest/main.swift`
  - +5 条 E5 用例
  - 总数：51 + 10(E1) + 7(E2) + 17(E3) + 8(E4) + 5(E5) = 98，全绿

### 当前阶段完成判定标准
1. ✅ 热键可配置且持久化
2. ✅ 热键冲突与无效输入有明确反馈（注册失败弹窗 + 自动回滚）
3. ✅ 文档与手测对齐最终行为
4. ✅ `swift build` + smoke 全绿

### 当前最新 Codex 结论
- 轨道内最新 PASS：`E4 / round 2 / 2026-04-24`
- 当前阶段（E5）：等待 round 1 验收（本轮预期 PROJECT COMPLETE）

### 当前活跃轨道验收会话状态
- 当前 session id：`019dbd4c-e0c9-7370-8a0c-1d4263a9f19b`
- 恢复策略：`codex exec resume <session_id>`
