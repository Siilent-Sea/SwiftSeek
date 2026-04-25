# 下一阶段任务书：K4

当前活跃轨道：`everything-productization`
当前阶段：`K4`
阶段名称：安装、升级、回滚与 Launch at Login 稳定化

## 交给 Claude 的任务

你现在只做 K4。目标不是继续扩 diagnostics，也不是做正式签名发行，而是把当前可运行的 `dist/SwiftSeek.app` 收口成“用户知道怎么安装、升级、回滚，且 Launch at Login 边界诚实”的本地工具使用路径。

K4 不做 Full Disk Access 指引，不做正式 Apple Developer ID 签名 / notarization，不做 DMG，不做 auto updater。

## 必须先审计的代码路径

- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/App/LaunchAtLogin.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `scripts/package-app.sh`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

重点确认：
- 当前 bundle 放到哪里最合理，首次打开会遇到什么系统行为。
- Launch at Login 现在如何展示“用户意图”和“系统实际状态”。
- 旧 app / 新 app / `dist/SwiftSeek.app` / `/Applications/SwiftSeek.app` 并存时，如何避免 stale bundle 与 schema 混用。
- 回滚时旧版 app 遇到新版 DB schema 的边界怎么写清。

## 必须做

1. 写清本地安装流程：
   - 如何生成 `dist/SwiftSeek.app`
   - 推荐放到哪里（如 `/Applications` 或自定义目录）
   - 首次打开 / Gatekeeper / ad-hoc 边界
2. 写清升级流程：
   - 退出旧 app
   - 替换 app
   - 启动后如何用 build identity 确认替换成功
3. 写清回滚流程：
   - 如何保留旧 app
   - DB schema 边界
   - 新 schema DB 不能随意拿旧 app 打开
4. 保持 Launch at Login 的“用户意图 + 系统状态”双视角呈现，并在文档中诚实写清 unsigned / ad-hoc 环境可能失败。
5. 至少提供多实例 / stale bundle / 旧版 app 并存的风险说明，避免 DB、登录项、设置状态混乱。
6. 保持 K1 build identity、K2 package 流水线、K3 diagnostics、J1/J6 生命周期路径不回退。

## 明确不做

- 不做 K5 的 Full Disk Access / 权限引导收口。
- 不做 K6 的 release note / 最终 QA 收口。
- 不做正式签名 / notarization / DMG / auto updater。
- 不新增搜索 / ranking / 索引功能。

## 验收标准

1. 本地安装流程写清并可执行。
2. 升级流程写清，且能通过 build identity 验证是否替换成功。
3. 回滚流程写清，schema 边界没有糊弄。
4. Launch at Login 的限制说明与当前 UI 行为一致。
5. 多实例 / stale bundle / schema 混用风险已明确写出。

## 必须补的验证

```text
1. shell: `./scripts/package-app.sh --sandbox` 继续能生成 `dist/SwiftSeek.app`。
2. GUI: 按文档执行一次“旧 app 替换为新 app”，用 About / 启动日志确认 build identity 已更新。
3. GUI: 模拟保留旧 app 场景，确认文档中的 stale bundle 排查步骤能工作。
4. GUI: Launch at Login 勾选/取消后，UI 和文档说明不互相矛盾。
5. 回归: K1/K2/K3 已通过面不回退。
```

## 验收后文档

K4 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 K5 任务书；如果 REJECT，按 blocker 修复。
