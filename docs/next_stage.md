# 下一阶段任务书：J5

当前活跃轨道：`everything-ux-parity`
当前阶段：`J5`
阶段名称：上下文菜单与文件操作增强

## 交给 Claude 的任务

你现在只做 J5。目标是让结果右键菜单更接近成熟文件搜索器，减少用户跳回 Finder 的次数。

J5 不做首次使用流程，不做云同步，不做遥测，不做系统搜索历史读取，不做完整文件管理器。

## 必须先审计的代码路径

- `Sources/SwiftSeek/UI/SearchViewController.swift`
- `Sources/SwiftSeek/UI/ResultActionRunner.swift`
- `Sources/SwiftSeekCore/ResultAction.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `docs/manual_test.md`
- `docs/known_issues.md`

重点确认：
- 现有右键菜单和按钮动作分别有哪些
- 哪些操作已经有 runner / enum 语义，哪些还没有
- clipboard 相关逻辑是否已可复用
- usage / Run Count 统计当前只在哪条路径上增加
- 失败反馈和破坏性确认是否已有统一模式

## 必须做

1. 扩展结果右键菜单，至少覆盖：
   - Open
   - Open With...
   - Reveal in Finder
   - Copy Name
   - Copy Full Path
   - Copy Parent Folder
   - Move to Trash
2. 所有破坏性操作必须确认。
3. 操作失败必须有可见反馈。
4. `Open With...` 必须使用公开 AppKit API，不能走 private API。
5. Copy Name / Full Path / Parent Folder 必须写入正确剪贴板内容。
6. usage 统计只对 Open 生效；Reveal / Copy / Trash 都不能增加 Run Count。
7. 如果决定做 Rename，必须把索引更新和 UI 状态恢复收口；如果这轮不做 Rename，必须在文档明确推迟原因。
8. 更新 `docs/manual_test.md`，补 J5 手测步骤。
9. 给 `Sources/SwiftSeekSmokeTest/main.swift` 补可自动化的纯字符串/路径动作 smoke，例如 file name / parent folder 提取。
10. 更新 `docs/known_issues.md`，把 J5 已解决和剩余限制写清楚。

## 明确不做

- 不做 J6：首次使用完整向导、Launch at Login、签名 / 公证。
- 不做完整文件管理器。
- 不做权限绕过。
- 不做批量重命名器。
- 不把 Reveal / Copy 计入 Run Count。
- 不做云同步。
- 不做遥测。
- 不读取系统搜索历史。

## 验收标准

1. 右键菜单包含新增动作且目标正确。
2. Copy Name / Full Path / Parent Folder 写入剪贴板内容准确。
3. Open With 使用公开 AppKit API。
4. Rename 成功后索引和 UI 状态可恢复；若不做 Rename，文档明确推迟原因。
5. Move to Trash 有确认和失败反馈。
6. 只有 Open 增加 Run Count。
7. `swift build --disable-sandbox` 通过。
8. `swift run --disable-sandbox SwiftSeekSmokeTest` 通过。
9. `docs/manual_test.md` 有明确 J5 GUI 手测步骤。

## 必须补的手测

```text
1. 右键结果项，确认新增菜单项都出现且目标正确。
2. 分别执行 Copy Name / Copy Full Path / Copy Parent Folder，检查剪贴板内容。
3. 执行 Open With...，确认走系统公开面板或公开 API。
4. 执行 Move to Trash，确认有二次确认；成功后结果和索引状态合理更新。
5. 制造一个失败场景，确认用户能看到失败反馈。
6. 对照 Run Count：Open 后增加；Reveal / Copy / Trash 不增加。
```

## 验收后文档

J5 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 J6 任务书；如果 REJECT，按 blocker 修复。
