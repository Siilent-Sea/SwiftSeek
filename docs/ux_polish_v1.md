# SwiftSeek v1 UX 打磨任务书（P6 之后的体验收尾）

## 背景
Codex 已颁发 `VERDICT: PROJECT COMPLETE`（v1 核心验收全通过）。
本轮是**产品体验打磨**，不改变 v1 scope，只补首次上手 / 空态提示 / 键盘流可见性 / 结果信息密度 / 菜单栏入口 / QuickLook 预览 / 拖拽等标准 macOS 搜索器应有的体验。

Codex 原始建议（来自 /tmp/codex-ux.out）+ Claude 补充，最终 16 条任务全部做。

---

## 16 条任务清单

### 必做（低成本高体验）
1. **搜索窗底部常驻快捷键提示条**
   - 位置：SearchViewController 底部（action bar 下方）
   - 文案：`↑↓ 移动 · ⏎ 打开 · ⌘⏎ Reveal · ⌘⇧C 复制 · ESC 关闭`
   - 灰色小号（systemFont 10pt / tertiaryLabelColor）

2. **首次启动 roots 空时设置窗顶部大号引导条**
   - 位置：SettingsWindowController 顶部（tab 上方）
   - 触发：listRoots 为空时显示
   - 文案：`👋 先在「索引范围」添加要搜索的目录，添加后会自动索引。之后按 ⌥Space 随时搜索。`

3. **空查询 / 无结果 空态提示**
   - 位置：SearchViewController tableView 上覆盖 overlay
   - 空 query：`输入关键字开始搜索`
   - 无 roots：`还没配置索引目录，请在菜单 SwiftSeek → 设置… → 索引范围 添加`
   - 有 roots 但无命中：`未找到匹配 "query"`

4. **结果 >20 时状态栏标 "仅显示前 20 条"**
   - 当前：`N 条 · Xms`
   - 改为：如果 hits.count == 20 且可能更多，显示 `仅显示前 20 条 · Xms`

5. **复制路径 toast 改短**
   - 当前：`已复制：<整条路径>`
   - 改为：`✓ 已复制`，2 秒后自动清空

6. **热键注册失败首次弹 NSAlert**
   - 当前：仅 NSLog
   - 改为：首次失败时弹 NSAlert `⌥Space 快捷键被占用。可通过菜单「SwiftSeek → 搜索…」呼出`
   - 用 UserDefaults `hotkey_fail_alerted_v1` 标记，只弹一次

7. **添加 root 后自动触发重建**
   - 当前：添加 root 后要手动去「维护」tab 点重建
   - 改为：onAddRoot 成功后弹 NSAlert `已添加 <path>。是否立即索引？`（默认：立即索引）→ 调 rebuildCoordinator.requestRebuild

### 高价值（中成本）
8. **结果行匹配 substring 高亮**
   - NSMutableAttributedString.addAttribute(.backgroundColor, systemYellow withAlphaComponent 0.25) 到文件名/路径中命中 q 的范围
   - 大小写不敏感匹配（使用 nameLower / pathLower 找 range，映射回原字符串）

9. **结果行加 mtime + size**
   - ResultCell 右侧次要信息：`3 天前 · 1.2 MB` 或 `—`（目录无 size）
   - mtime 用 RelativeDateTimeFormatter，size 用 ByteCountFormatter

10. **菜单栏 NSStatusItem**
    - AppDelegate 建 NSStatusItem（text template icon 或 "⌕" 符号）
    - 点击菜单：`搜索…`、`设置…`、`索引：空闲 / 进行中...`、分隔线、`退出`
    - 保留 Dock 图标（LSUIElement 保持 false）

11. **QuickLook 预览（Space 键）**
    - SearchViewController 在 `doCommandBy` 里捕获 Space
    - 用 `QLPreviewPanel.shared()` + `NSApplication.presentPreviewPanel`
    - 实现 QLPreviewItem + QLPreviewPanelDataSource/Delegate

12. **拖拽结果到其他 app**
    - tableView(_:pasteboardWriterForRow:) 返回 NSURL(fileURLWithPath:)
    - 允许拖到邮件、聊天、Finder 等

13. **roots tab 支持拖入文件夹**
    - rootsTable registerForDraggedTypes: [.fileURL]
    - tableView(_:validateDrop:proposedRow:proposedDropOperation:) 接受目录
    - tableView(_:acceptDrop:row:dropOperation:) 调 addRoot

### 可选补全
14. **结果右键菜单**
    - NSTableView.menu 或 viewFor 返回 view 加 menuForEvent
    - 菜单：打开 / 在 Finder 显示 / 复制路径 / 移到废纸篓

15. **隐藏文件开关旁 "立即重建" 按钮**
    - GeneralPane.checkbox 旁边加按钮
    - 调 rebuildCoordinator.requestRebuild

16. **菜单栏进度显示**
    - 重建进行中时 NSStatusItem.button.title 改为 "⌕ 索引中…"
    - 完成后恢复 "⌕"

---

## 验收要求（Codex 第 2 次独立审计）
所有改动完成后，Codex 按以下命令独立验收：

```bash
HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
    swift build --disable-sandbox
# 期望：Build complete!

HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
    swift run --disable-sandbox SwiftSeekSmokeTest
# 期望：51/51 pass（P0~P5 不回退）

HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
    swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-ux.sqlite3
# 期望：database ready schema=3 + startup check PASS
```

代码审查重点：
- 16 条是否每条都有对应实现（文件位置 + 行号）
- 未新增 v1 scope 外功能
- 无 silent-fail 回退
- 无回归

---

## Claude 开发顺序（单次集中改完）
1-7（必做）→ 14-16（可选小补）→ 8-13（高价值，独立改动）
每批改完 build + smoke，最后一次性 codex 审计。
