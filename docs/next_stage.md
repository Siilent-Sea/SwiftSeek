# 下一阶段任务书：K5

当前活跃轨道：`everything-productization`
当前阶段：`K5`
阶段名称：权限引导、Full Disk Access 与 root coverage 诚实收口

## 交给 Claude 的任务

你现在只做 K5。目标不是新增搜索能力，也不是做正式签名发行，而是把“哪些 root 真正可访问、哪些因为权限或卷状态不可访问、用户该怎么补救”收口成可见、可解释、可复检的产品面。

K5 不做 release notes，不做最终 QA checklist，不做 notarization / Developer ID / DMG / auto updater。

## 必须先审计的代码路径

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/App/LaunchAtLogin.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/RootHealthSnapshot.swift`
- `Sources/SwiftSeekCore/RootHealthMonitor.swift`
- `Sources/SwiftSeekCore/RootRecord.swift`
- `README.md`
- `docs/install.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

重点确认：
- 当前 app 对“root 不可访问 / 权限不足 / 卷离线 / 路径不存在”分别能暴露到什么程度。
- 现有 UI、diagnostics、startup log 里，哪些地方已经能承载 K5 的状态与提示，哪些还只是静默失败。
- 用户如何得知 Full Disk Access 是系统权限问题，而不是索引器坏了。
- 外接盘、Downloads/Desktop/Documents、其他受保护目录的边界如何诚实表达。

## 必须做

1. 让 root 不可访问状态变成显式产品面：至少要能看到“权限被拒绝 / 卷离线 / 路径不存在 / 其他错误”的可区分状态。
2. 给出 Full Disk Access 引导：告诉用户在哪个系统面板授权，以及授权后如何回到 SwiftSeek 重新检查。
3. 提供 recheck / refresh 权限路径：用户补权限后，不应只能靠重装或猜测恢复。
4. 在 About / diagnostics / root health 或等价位置，把 root coverage 边界写清，不要继续把缺权限 root 伪装成已正常索引。
5. 对外接盘和临时离线 root，明确区分“设备不在”与“权限不够”。
6. 更新 `README.md`、`docs/install.md`、`docs/manual_test.md`、`docs/known_issues.md`，把权限边界、FDA 指引、恢复步骤写成用户可执行文档。
7. 保持 K1 build identity、K2 package 流水线、K3 diagnostics、K4 安装文档、J1/J6 生命周期路径不回退。

## 明确不做

- 不绕过 macOS 权限模型。
- 不用 private API。
- 不承诺对网络盘 / 云盘 / 外接盘做实时一致性保证。
- 不做 K6 的 release notes / 最终 QA 收口。
- 不新增搜索 / ranking / 索引业务功能。

## 验收标准

1. 用户能明确看见某个 root 为什么不可用，而不是只看到结果少了。
2. 用户能从 UI 或文档知道如何补齐 Full Disk Access。
3. 补齐权限后，有明确的 recheck / refresh 路径。
4. 外接盘离线、路径不存在、权限被拒绝不会混成同一种状态。
5. diagnostics / docs / UI 三处口径一致，不夸大能力。
6. K1-K4 已通过面不回退。

## 必须补的验证

```text
1. shell: `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift build --disable-sandbox`
2. shell: `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache swift run --disable-sandbox SwiftSeekSmokeTest`
3. shell: `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache ./scripts/package-app.sh --sandbox`
4. GUI: 至少验证一个无权限目录或需要 Full Disk Access 的目录，确认 UI/diagnostics 能显示明确原因。
5. GUI: 补齐权限后执行一次 recheck / refresh，确认状态能更新。
6. GUI: 断开再重连一个外接盘或模拟离线路径，确认“卷离线”与“权限不足”不会混淆。
7. 回归: K1/K2/K3/K4/J1/J6 已通过面不回退。
```

## 验收后文档

K5 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 K6 任务书；如果 REJECT，按 blocker 修复。
