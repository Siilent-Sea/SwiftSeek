# 下一阶段任务书：K3

当前活跃轨道：`everything-productization`
当前阶段：`K3`
阶段名称：版本信息 / About / diagnostics / 日志导出

## 交给 Claude 的任务

你现在只做 K3。目标不是继续修 `.app` 打包，而是把当前已有的 build identity、About 面板和 diagnostics 收口成用户可复制、开发者可定位问题的完整诊断面。

K3 不做安装/升级/回滚，不做权限引导，不做正式签名/公证，不做 auto updater。

## 必须先审计的代码路径

- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/DatabaseStats.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `scripts/package-app.sh`
- `scripts/build.sh`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

重点确认：
- 当前 About / diagnostics 已经展示了哪些字段，哪些还缺。
- 当前 DB stats、schema、DB path、bundle/binary path 是否能统一口径输出。
- 启动日志是否已经带够 build identity + schema。
- “复制诊断信息” 导出的文本是否足够让别人复盘问题。

## 必须做

1. 扩充 About / diagnostics，至少覆盖：
   - app version
   - build commit
   - build date
   - schema version
   - database path
   - index mode
   - root count
   - DB size
   - usage rows
   - query history rows
   - package path / executable path
   - Launch at Login 意图与系统状态
2. 保留并强化“复制诊断信息”按钮，确保复制出的文本是一份完整诊断快照，而不是零散字段。
3. 统一 diagnostics 与真实数据源口径，避免 About 面板与 `SwiftSeekDBStats`、数据库现状互相矛盾。
4. 启动日志继续保留 build identity，并补足 schema 维度，保证用户贴前几行日志就能看出当前构建和数据库版本。
5. 更新 README / manual_test / known_issues，写清用户反馈 bug 时需要提供什么诊断信息。
6. 保持 K1 build identity、K2 package 流水线、J1/J6 生命周期路径不回退。

## 明确不做

- 不做 K4 的安装 / 升级 / 回滚流程。
- 不做 K5 的 Full Disk Access / 权限引导收口。
- 不做 K6 的 release note / 最终 QA 收口。
- 不做遥测、日志上传、云端收集。
- 不新增搜索 / ranking / 索引功能。

## 验收标准

1. About / diagnostics 一屏能复制完整诊断信息。
2. 诊断信息包含 build identity、schema、DB path、bundle/executable path。
3. DB stats 与真实数据库统计不矛盾。
4. 启动日志包含 build identity 和 schema。
5. 文档写清用户反馈时应提供的诊断内容。

## 必须补的验证

```text
1. shell: `swift run --disable-sandbox SwiftSeekSmokeTest` 继续通过。
2. GUI: 启动 `dist/SwiftSeek.app`，About 顶部 summary 与启动日志一致。
3. GUI: 点“复制诊断信息”，`pbpaste` 内容包含 version / commit / build / schema / DB path / bundle / binary。
4. shell: 用仓库内现有 DB stats 命令或等价路径核对 About 里的统计值。
5. 回归: K1 的设置窗口 reopen / 10x close-show / 20x tab switch 不回退；K2 的 package 脚本仍可成功生成 `.app`。
```

## 验收后文档

K3 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 K4 任务书；如果 REJECT，按 blocker 修复。
