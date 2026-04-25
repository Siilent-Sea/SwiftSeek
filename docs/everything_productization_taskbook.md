# SwiftSeek Everything-productization 任务书

目标：在 `everything-ux-parity` 已完成的基础上，把 SwiftSeek 从“功能完成的本地项目”推进到“可重复打包、可安装、可升级、可诊断、可回归验证的 macOS 工具”。当前轨道不新增搜索功能，重点是发布链路、`.app` bundle、版本标识、生命周期 release gate、安装/升级/回滚、权限引导和最终 QA。

硬约束：
- 当前轨道固定为 `everything-productization`
- 阶段固定为 `K1` 到 `K6`
- 不把未签名 / 未公证构建伪装成正式签名发行版
- 不承诺 App Store 沙盒适配
- 不做 auto updater
- 不使用 private API
- 每次只做当前阶段，不允许提前实现后续阶段

---

## K1：设置窗口回归门禁 + stale build 防护

### 阶段目标
把用户真实遇到过的设置窗口 / 设置菜单问题变成永久回归门禁，并让用户能判断当前运行的是不是最新构建。

### 明确做什么
- 审计并记录当前设置窗口修复状态：
  - `windowShouldClose`
  - hide-only close
  - Dock reopen
  - 主菜单设置入口
  - menu bar 设置入口
  - tab index 记忆使用 KVO，不能回退到非法 `tabView.delegate`
- 建立 release gate：
  - GUI 手测文档必须覆盖设置窗口 10 次关闭/打开
  - 启动后打开设置、关闭、再从菜单栏/主菜单/Dock 重开
  - 设置 tab 切换不崩溃
  - 搜索窗口 hotkey / menu bar / ESC hide 不回归
- 增加运行时 build identity：
  - About / diagnostics 显示 app version、schema、git commit 或 build timestamp
  - About / diagnostics 显示 bundle path 或 executable path
  - 启动日志打印 build identity
- 如果暂时无法自动注入 git commit，先生成 build-info 文件或常量，并说明限制。
- 更新文档说明如何确认当前 bundle / binary 是否刷新。
- 修正 `scripts/build.sh` 已知文案漂移，至少不能继续打印 schema v3。

### 明确不做什么
- 不做正式 `.app` 打包流水线。
- 不做 DMG。
- 不做 notarization。
- 不做 Apple Developer ID 签名。
- 不做 Launch at Login 大改。
- 不新增搜索 / 索引业务功能。

### 涉及关键文件
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/UI/SearchWindowController.swift`
- `Sources/SwiftSeekCore/Schema.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekSmokeTest/main.swift`
- `scripts/build.sh`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/codex_acceptance.md`
- `docs/next_stage.md`

### 验收标准
1. 设置窗口 release gate 写入手测或 checklist，覆盖 10 次关闭/打开、菜单栏重开、主菜单重开、Dock reopen。
2. 设置 tab 切换不再使用非法 delegate 方案，KVO 或等价安全方案被保留。
3. About / diagnostics 或等价 UI 可见 app version、schema、build timestamp 或 git commit、bundle/executable path。
4. 启动日志打印 build identity。
5. 用户能通过 README / known issues / manual test 知道如何判断 stale bundle。
6. `scripts/build.sh` 不再输出过期 schema v3 文案。
7. `swift build` 和 `swift run SwiftSeekSmokeTest` 通过。

### 必须补的测试 / 手测 / release checklist
- smoke：build identity 字符串存在且非空，如实现为纯 Swift 常量。
- smoke：设置窗口 10 次 close/show 的现有 J1 覆盖继续存在。
- 手测：设置窗口关闭 / 菜单栏重开 / 主菜单重开 / Dock reopen。
- 手测：切换设置 tab 20 次不崩溃。
- 手测：About / diagnostics 与启动日志能看出当前构建身份。
- release checklist：确认当前运行路径不是旧 `.app` / 旧 binary。

---

## K2：可重复生成 `.app` bundle 的打包流水线

### 阶段目标
让 `.app` bundle 不再靠手工拼，建立可重复的本地 app package 流程。

### 明确做什么
- 新增或重写脚本，例如 `scripts/package-app.sh`。
- 脚本必须自动完成：
  - swift release build
  - 创建 `SwiftSeek.app/Contents/MacOS/SwiftSeek`
  - 生成 `Info.plist`
  - 生成或复制 `AppIcon.icns`
  - 写入 `CFBundleIdentifier`
  - 写入 `CFBundleVersion`
  - 写入 `CFBundleShortVersionString`
  - 写入 build commit 或 build timestamp
  - ad-hoc codesign
  - 验证 app bundle 结构
- `scripts/make-icon.swift` 接入 package 流程，不再只是手工脚本。
- `scripts/build.sh` 要么调用 package 脚本，要么明确区分 CLI release build 与 app package。
- 产物目录统一，例如 `dist/SwiftSeek.app`。
- `.gitignore` 与文档明确哪些是生成物、哪些模板应被跟踪。

### 明确不做什么
- 不做正式 Apple Developer ID 签名。
- 不做 notarization。
- 不做 DMG，除非任务明确扩展。
- 不做 auto updater。

### 涉及关键文件
- `scripts/build.sh`
- `scripts/make-icon.swift`
- `scripts/package-app.sh`
- `Package.swift`
- `.gitignore`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. fresh clone 后一条命令能生成 `.app`。
2. `.app/Contents/MacOS/SwiftSeek` 存在且可执行。
3. `Info.plist` 字段完整且与 README 一致。
4. `AppIcon.icns` 自动生成或复制进 bundle。
5. `codesign -dv` 显示 ad-hoc 签名。
6. `open dist/SwiftSeek.app` 或等价命令可启动。
7. 打包脚本可重复运行，旧产物清理策略明确。

### 必须补的测试 / 手测 / release checklist
- shell 验证：bundle 文件结构。
- shell 验证：`plutil -lint` / `plutil -p`。
- shell 验证：`codesign -dv --verbose=2`。
- 手测：双击 / `open` 启动 app。
- 手测：Dock 图标和 App 名称正确。

---

## K3：版本信息 / About / diagnostics / 日志导出

### 阶段目标
让用户反馈问题时能提供完整诊断信息，让开发者能快速判断版本、包、DB、权限和运行环境。

### 明确做什么
- About / diagnostics 显示：
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
- 提供复制诊断信息按钮。
- 提供导出诊断日志或复制 log 命令。
- DB stats 与 About 面板口径统一。
- 文档写清用户反馈 bug 时应提供什么。

### 明确不做什么
- 不上传日志。
- 不做遥测。
- 不自动读取用户文件内容。
- 不收集系统隐私数据。

### 涉及关键文件
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/DatabaseStats.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `scripts/build.sh`
- `scripts/package-app.sh`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `README.md`

### 验收标准
1. About / diagnostics 一屏能复制完整诊断信息。
2. 诊断信息包含 build identity、schema、DB path、executable/bundle path。
3. DB stats 与 `SwiftSeekDBStats` 不矛盾。
4. 启动日志包含 build identity 和 schema。
5. 用户反馈模板写入文档。

### 必须补的测试 / 手测 / release checklist
- smoke：diagnostics builder 输出必要字段，如能抽离为纯函数。
- 手测：复制诊断信息到剪贴板。
- 手测：用 copied diagnostics 判断当前 app 是否是最新构建。
- release checklist：启动日志包含 version / commit / schema。

---

## K4：安装、升级、回滚与 Launch at Login 稳定化

### 阶段目标
让用户知道怎样安装、升级、回滚和开机启动，且 UI 对未签名 / ad-hoc 环境的边界诚实。

### 明确做什么
- 写清本地安装流程：
  - 构建 app
  - 放到 `/Applications` 或自定义目录
  - 首次打开
  - Gatekeeper 处理
- 写清升级流程：
  - 退出旧 app
  - 替换 app
  - 启动后确认 build identity
- 写清回滚流程：
  - 保留旧 app
  - DB schema 限制说明
  - 新 schema DB 不能随意用旧 app 打开
- Launch at Login 稳定化：
  - UI 显示系统实际状态和用户意图
  - 文档说明 unsigned/ad-hoc 环境可能失败
  - 诊断页显示相关状态
- 防止多实例导致 DB / 登录项 / 设置状态混乱，至少给出文档或 runtime 提示方案。

### 明确不做什么
- 不做正式安装器。
- 不做 auto updater。
- 不承诺 Apple notarization。
- 不绕过 macOS 安全策略。

### 涉及关键文件
- `Sources/SwiftSeek/App/LaunchAtLogin.swift`
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `scripts/package-app.sh`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

### 验收标准
1. README 或 install 文档有明确安装 / 升级 / 回滚步骤。
2. 启动后能确认当前 app build identity。
3. Launch at Login 失败时 UI 显示真实错误和处理建议。
4. 诊断信息显示登录项意图与系统状态。
5. 未签名 / 未公证限制被明确写清，不假装正式发行。

### 必须补的测试 / 手测 / release checklist
- 手测：复制 app 到 `/Applications` 后启动。
- 手测：替换 app 后 build identity 改变。
- 手测：Launch at Login 成功或失败路径都有清楚反馈。
- 手测：回滚说明覆盖 schema 兼容边界。

---

## K5：权限 / Full Disk Access / root 覆盖引导

### 阶段目标
把 macOS 文件访问权限从“提示语”推进到可诊断、可复核的产品体验。

### 明确做什么
- 诊断 root 可访问性。
- 对不可访问 root 给出 Full Disk Access 指引。
- 首次使用引导加入更明确的 root 覆盖建议：
  - Home 目录
  - Downloads / Documents / Desktop
  - External volumes
  - Full Disk Access
- 权限不足时不要静默失败。
- 提供“重新检查权限”按钮或诊断项。
- 文档写清 external volume / root offline / unavailable 的差异。

### 明确不做什么
- 不绕过 macOS 权限。
- 不使用 private API。
- 不承诺云盘 / 网络盘实时一致性。

### 涉及关键文件
- `Sources/SwiftSeek/UI/SettingsWindowController.swift`
- `Sources/SwiftSeekCore/SettingsTypes.swift`
- `Sources/SwiftSeekCore/Database.swift`
- `Sources/SwiftSeekCore/RootHealth` 相关实现
- `docs/manual_test.md`
- `docs/known_issues.md`
- `README.md`

### 验收标准
1. 不可访问 root 在 UI 中有明确状态和解释。
2. 用户能从 UI 或文档知道如何授予 Full Disk Access。
3. 重新检查权限路径存在。
4. external volume offline 与 permission denied 不混淆。
5. 权限引导不承诺越权能力。

### 必须补的测试 / 手测 / release checklist
- smoke：RootHealth 状态逻辑不回归。
- 手测：无权限目录提示。
- 手测：外接盘断开 / 重连提示。
- 手测：授权 Full Disk Access 后状态刷新。

---

## K6：Release QA、包体产物、最终收口

### 阶段目标
把 productization 轨道收口到可验收状态，让 Codex 能判断 `PROJECT COMPLETE`。

### 明确做什么
- 建立 release checklist：
  - fresh clone build
  - package app
  - launch app
  - settings reopen
  - search window hotkey
  - add root
  - search
  - open file
  - Run Count update
  - DB stats
  - Launch at Login note
  - app icon
  - About build identity
  - diagnostics copy
  - install / upgrade / rollback docs
- 生成 release notes 模板。
- README / known_issues / manual_test / architecture 最终同步。
- 确认 `scripts/build.sh`、`scripts/package-app.sh`、icon、plist、codesign 文档一致。
- 保留未签名 / 未公证边界，不假装正式发行版。

### 明确不做什么
- 不做 Apple Developer ID 签名，除非用户提供身份和明确要求。
- 不做 notarization，除非用户明确要求。
- 不做 Sparkle / auto updater。
- 不做 App Store packaging。

### 涉及关键文件
- `scripts/build.sh`
- `scripts/package-app.sh`
- `scripts/make-icon.swift`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`
- `docs/architecture.md`
- `docs/codex_acceptance.md`
- `docs/stage_status.md`
- `docs/everything_productization_gap.md`
- `docs/everything_productization_taskbook.md`

### 验收标准
1. release checklist 可从 fresh clone 实际跑通。
2. `.app` 产物可重复生成并启动。
3. app icon、Info.plist、bundle id、version、build identity 可验证。
4. 设置窗口生命周期 release gate 通过。
5. About / diagnostics 可复制。
6. README / known issues / manual test 与最终代码一致。
7. Codex 可基于实证输出 `PROJECT COMPLETE`。

### 必须补的测试 / 手测 / release checklist
- fresh clone package test。
- app launch smoke。
- settings reopen 10 次。
- search + open + Run Count。
- DB stats / diagnostics copy。
- Launch at Login note。
- install / upgrade / rollback dry run。
- final `swift build` + `SwiftSeekSmokeTest`。
