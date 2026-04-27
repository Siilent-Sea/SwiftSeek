# SwiftSeek Release Checklist（K6 + L1-L4 + M1-M4 单页）

> `everything-dockless-hardening` 已开新轨道。当前清单中的 L1/L2 no-Dock gate 是历史 release gate，不足以覆盖用户反馈的 Dock 仍常驻问题。N4 前发布时必须额外记录 `LSUIElement`、`dock_icon_visible`、activation policy、bundle path 和 fresh/旧 DB 场景；最终硬 gate 以 N4 更新后的清单为准。

每次发布本地 ad-hoc bundle 前**必须**从干净 workspace 走完整张表。任何一项失败都不算 release-ready。

**当前 release gate** = K6 收口 + L1 menubar-agent 形态默认 + L2 Dock 显示开关 + L3 菜单栏状态可见性 + L4 单实例防护 + M1 Reveal Target 设置 UI + M2 Finder/自定义 App 运行时路由 + M3 动态文案 / fallback / Diagnostics + M4 文档对齐。未签名 / 未公证 / 无 DMG / 无 auto updater 是当前轨道明确边界，不要在这条路径里夸大交付。L1 起 SwiftSeek 默认 **不显示 Dock 图标**；菜单栏状态项是主入口；L4 起重复打开同一 bundle id 的实例会主动 defer + 唤醒旧实例；M1-M3 起 "在 Finder 中显示" 可配置为任意 `.app`，不依赖任何文件管理器私有 API。

## 0. 前置确认

- [ ] macOS 13 或更高
- [ ] `swift --version` ≥ 6.x
- [ ] 当前 git status 干净 或 已知改动是发布范围内的
- [ ] 本次发布版本号已确定（默认随 `Package.swift` / `Info.plist` 默认值，需要覆盖时用 `SWIFTSEEK_APP_VERSION=...`）

## 1. Fresh / Clean Build

普通开发机：
```bash
swift build -c release
```

受限沙箱（Codex 等）：
```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift build --disable-sandbox
```

- [ ] 命令成功（exit 0）
- [ ] 无编译错误 / 无新增 warning（无关历史 warning 可忽略）

## 2. Smoke Tests 全绿

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
swift run --disable-sandbox SwiftSeekSmokeTest
```

- [ ] 末行 `Smoke total: N  pass: N  fail: 0`
- [ ] 当前基准 N = **256**（everything-filemanager-integration M3 落地后），本轮总数不应少于 256

## 3. 一条命令打包 .app

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/package-app.sh --sandbox          # N2 默认 agent 模式，LSUIElement=true
```

- [ ] 命令成功，输出 `[package-app.sh] === done ===`
- [ ] `dist/SwiftSeek.app` 存在
- [ ] 末尾输出包含 `mode: agent (no-Dock / menu bar agent (default))` 与 `LSUIElement: true`
- [ ] 中段断言 `LSUIElement assertion OK (=true, mode=agent)` 出现

如发布需要 Dock app 包（N2 显式 opt-in）：
```bash
./scripts/package-app.sh --sandbox --dock-app   # LSUIElement=false
```
- [ ] 末尾输出 `mode: dock_app (Dock app (opt-in via --dock-app))` 与 `LSUIElement: false`
- [ ] 断言 `LSUIElement assertion OK (=false, mode=dock_app)` 出现

## 4. Bundle 文件结构 + 元数据

```bash
plutil -lint dist/SwiftSeek.app/Contents/Info.plist
codesign -dv --verbose=2 dist/SwiftSeek.app
ls dist/SwiftSeek.app/Contents/{MacOS,Resources}
file dist/SwiftSeek.app/Contents/Resources/AppIcon.icns
```

- [ ] `plutil -lint` 输出 `OK`
- [ ] `codesign -dv` 输出包含 `Signature=adhoc` 和 `Identifier=com.local.swiftseek`（默认）
- [ ] `Contents/MacOS/SwiftSeek` 存在且可执行
- [ ] `Contents/Resources/AppIcon.icns` 存在，`file` 显示为 Mac OS X icon
- [ ] `Info.plist` 关键字段：
  - [ ] `CFBundleShortVersionString` 与本次发布预期一致
  - [ ] `CFBundleIdentifier` = `com.local.swiftseek`（或自定义覆盖值）
  - [ ] `GitCommit` = 当前 `git rev-parse --short HEAD`
  - [ ] `BuildDate` ≈ 今天
  - [ ] `LSUIElement` = `true`（默认 agent 包）或 `false`（`--dock-app` 包），与本次发布预期 mode 一致

## 5. App 启动 + Build Identity 三连

```bash
open dist/SwiftSeek.app
# 立刻打开 Console.app，过滤 "SwiftSeek"
```

期望 Console 里头三行：
```
SwiftSeek: SwiftSeek <ver> commit=<hash> build=<date>
SwiftSeek: bundle=<bundle 路径>
SwiftSeek: binary=<binary 路径>
```

- [ ] 三行同时出现
- [ ] `commit=` 与 `git rev-parse --short HEAD` 一致
- [ ] `bundle=` 路径就是刚 `open` 的 `dist/SwiftSeek.app`
- [ ] `binary=` 指向 `Contents/MacOS/SwiftSeek`

## 5b. L1 menubar-agent 形态验证（每次发布必跑）

L1 把默认形态从普通 Dock App 改成菜单栏常驻工具。Dock 不显示是预期行为，不是 bug。

- [ ] 启动后 **Dock 中没有** SwiftSeek 图标（看 Dock 全栏；L1 通过 `NSApp.setActivationPolicy(.accessory)` 在 `applicationDidFinishLaunching` 设置）
- [ ] **菜单栏右上角** 出现放大镜图标（`NSStatusItem`）
- [ ] 点菜单栏图标弹出菜单，包含：搜索…（⌥Space）/ 设置…（⌘,）/ 索引：… / 退出 SwiftSeek（⌘Q）
- [ ] 点菜单栏 → "搜索…" → 搜索窗前置可输入
- [ ] 点菜单栏 → "设置…" → 设置窗前置
- [ ] 全局热键 `⌥Space` 可呼出搜索窗（不依赖菜单栏可见）
- [ ] 点菜单栏 → "退出 SwiftSeek" → 进程退出，菜单栏图标消失
- [ ] 重复 `open dist/SwiftSeek.app` → 退出 → 启动 3 次，菜单栏图标每次正常出现/消失，无残留进程

## 5c. L2 Dock 显示开关验证（每次发布必跑）

L2 给用户一个可持久化、重启生效的方式恢复 Dock 图标。

- [ ] 全新 DB（首次安装）下，设置 → 常规 → 最下方 "在 Dock 显示 SwiftSeek 图标" 复选框 **未勾选**
- [ ] 复选框下方 note 显示当前 "✓ 当前以菜单栏 agent 形态运行（默认）" 之类
- [ ] **勾选** 复选框
- [ ] note 立即变成 "⚠️ 已勾选「在 Dock 显示」，但当前进程仍是菜单栏 agent 模式"
- [ ] 菜单栏 → "退出 SwiftSeek" → `open dist/SwiftSeek.app` → 这次 Dock **出现** SwiftSeek 图标
- [ ] Dock visible 模式下确认仍可用：菜单栏图标存在 / 菜单栏 → 搜索 / 菜单栏 → 设置 / 全局热键 `⌥Space` / 菜单栏 → 退出
- [ ] 设置 → 常规 → 复选框现在已勾选，note 显示 "✓ 当前以普通 App 形态运行：Dock 中可见..."
- [ ] **取消** 勾选 → 退出 → 重启 → Dock 再次隐藏
- [ ] 没有任何模式下 SwiftSeek 完全无入口（菜单栏图标始终在）
- [ ] 重复 Dock visible → no Dock 一个完整循环；状态与设置一致，无残留进程或重复菜单栏图标

## 5d. L3 菜单栏状态可见性验证（每次发布必跑）

L3 把菜单栏从"入口"升级为"主入口 + 快速状态面板"。tooltip + 只读状态行让用户不打开设置窗也能确认当前构建、索引、模式、root 健康和 DB 大小。

- [ ] 悬停菜单栏放大镜图标 → tooltip 出现 5 行：build identity / 索引 / 模式 / roots / DB 大小
- [ ] tooltip 第 1 行 build summary 与 `git rev-parse --short HEAD` 一致
- [ ] tooltip 第 2 行 "索引：空闲"（启动后未触发重建时）
- [ ] tooltip 第 3 行 "模式：Compact"（默认）或 "Full path"
- [ ] tooltip 第 4 行 "roots：..."；新装无 root 时为 "暂无 root"
- [ ] tooltip 第 5 行 "DB 大小：..." 显示 KB/MB/GB（不会是负数或 -1）
- [ ] 点开菜单 → 状态行（disabled）顺序：索引 / build / 模式 / roots / DB 大小，文本与 tooltip 同步
- [ ] 添加一个 root → 等索引开始 → 菜单栏图标变 `magnifyingglass.circle` + 索引行变 "索引中 · N/M roots"；tooltip 第 2 行同步
- [ ] 索引完成 → 菜单栏图标回 `magnifyingglass` + 索引行变 "空闲"；tooltip 同步
- [ ] 添加一个不存在路径作为 root（或删除已存在 root 的目录后 "重新检查权限"）→ tooltip 与菜单 roots 行包含 "不健康"
- [ ] 点菜单栏 → "搜索…" / "设置…" / "退出 SwiftSeek" 仍正常工作（L1/L2 不回归）

## 5e. L4 单实例 / 多 bundle 防护验证（每次发布必跑）

L4 实现 single-instance defense：同 `CFBundleIdentifier` 的第二份实例启动时主动 defer + 唤醒旧实例。

- [ ] **场景 A — 同一 `.app` 双击两次**：
  - `open dist/SwiftSeek.app` → 等菜单栏图标出现 → 再次 `open dist/SwiftSeek.app`
  - `pgrep SwiftSeek` 仍只有一个 PID
  - 菜单栏仍只一个图标
  - 旧实例的设置窗口前置（DistributedNotification → showSettings 路径）
  - Console 过滤 SwiftSeek，新实例的 K1 三连之后有一行 `another instance detected — sibling pid=...`
- [ ] **场景 B — `dist` 与 `/Applications` 并存**：
  - `cp -R dist/SwiftSeek.app /Applications/`
  - `open dist/SwiftSeek.app` → 等菜单栏出现
  - `open /Applications/SwiftSeek.app`
  - 仍只一个菜单栏图标 + 一个 PID
  - 第二启动方的 NSLog 冲突日志同时显示两条 bundle path（`dist/...` 和 `/Applications/...`）
  - 用户能从日志看出哪个先启动 / 哪个被 defer
- [ ] **场景 C — Launch at Login + 手动启动**：
  - 设置 → 常规 → 勾选 Launch at Login → 退出 SwiftSeek
  - 注销重登 → SwiftSeek 自动启动
  - 立即手动 `open dist/SwiftSeek.app`
  - 仍只一个 PID + 一个菜单栏图标
- [ ] **场景 D — defer 不破坏 L1/L2/L3**：
  - 上面三个场景之后，旧实例：
    - 菜单栏图标仍可点
    - 全局热键 `⌥Space` 仍有效
    - 设置窗口可正常打开
    - tooltip / 菜单状态行仍可见（L3）
- [ ] **swift run dev 路径降级行为**：
  - `swift run SwiftSeek`（不打包，无 Bundle.main.bundleIdentifier）
  - Console 有 `single-instance check skipped (Bundle.main.bundleIdentifier is nil; likely raw swift run)` 一行
  - 这是 dev 路径已知降级，release 路径不受影响

## 5f. M3 Reveal Target 动态文案 / fallback / 诊断（每次发布必跑）

M3 让 reveal 文案、fallback toast、diagnostics 跟随当前 reveal target 变化。

- [ ] 默认 Finder：搜索结果按钮 + 右键菜单显示 `在 Finder 中显示`；点击成功
- [ ] 切到 `/Applications/QSpace.app`：按钮 + 右键菜单显示 `在 QSpace 中显示`（QSpace 启发式生效）
- [ ] 切到 `/Applications/Path Finder.app`（或任意 .app）：按钮 + 右键菜单显示 `在 Path Finder 中显示`（去 `.app` 后缀）
- [ ] **关键**：fallback toast 必须以 `⚠️` 开头，包含 `无法用 <AppName> 显示，已回退到 Finder：` 前缀，并显示底层原因
- [ ] **关键**：失效 app 路径下 fallback 后 Finder 仍选中**原始文件**（不是 parentFolder 父目录）
- [ ] About → 复制诊断信息 → 包含 `Reveal target（M3）：` 块；切换设置后块内容跟随更新
- [ ] reveal 不增加 Run Count（每次发布必跑）
- [ ] 不出现任何 QSpace 私有 API / bundle id / URL scheme / AppleScript 痕迹

## 6. 设置窗口生命周期 Release Gate

按 `docs/manual_test.md` §33s 执行（J1 + J6 修复回归门禁）：

- [ ] **菜单栏** SwiftSeek 状态项 → "设置…" 打开（L1 之后这是主入口；不再依赖 Dock）
- [ ] 关闭设置窗口（红点 / Cmd-W）
- [ ] 菜单栏 → "设置…" **重新打开** 设置窗口
- [ ] 重复 close / open **10 次**
- [ ] 每次都成功打开
- [ ] 切换 tab：常规 / 索引 / 维护 / 关于 全部正常切换（J6 KVO 路径）
- [ ] 双击 `dist/SwiftSeek.app` 第二次（applicationShouldHandleReopen 路径）→ 设置窗口前置作为 fallback
- [ ] **不**期望 Dock 图标可点击（L1 默认隐藏 Dock）；如出现 Dock 图标说明 `.accessory` 失败，标记本次 release ❌

## 7. 搜索热键 + ESC 隐藏

- [ ] 默认 `Option+Space` 唤出搜索窗
- [ ] 输入字符立即出结果
- [ ] `ESC` 隐藏搜索窗
- [ ] 再次按热键再次唤出

## 8. Add Root → Search → Open File → Run Count

1. 设置 → 索引 → 新增目录 → 选 `~/Documents` 子目录
2. 等"索引中"消失，徽标变 ✅ 就绪
3. 唤出搜索窗 → 输入新加目录里某文件名
4. 按 Enter 打开
5. 回搜索窗，搜同一文件 → 检查"打开次数"列

- [ ] add root 后徽标变绿
- [ ] 搜索能命中新加目录的文件
- [ ] Enter 真的打开了文件
- [ ] 回搜索窗看到 Run Count = 1（多打开几次应递增）

## 9. DB Stats / Diagnostics 复制

- [ ] 设置 → 关于 → 顶部 summary 与第 5 步 Console 三连一致
- [ ] 点 "复制诊断信息" → 粘贴到文本编辑器
- [ ] 包含 K3 字段：
  - [ ] 版本 / build commit / build date / bundle / binary
  - [ ] 数据库路径 / schema 版本
  - [ ] main / wal / shm 大小
  - [ ] files / file_usage / query_history / saved_filters 行数
  - [ ] 索引模式 / 隐藏文件 / usage history / query history 开关
  - [ ] roots 总数与启用数 / excludes 数
  - [ ] **K5 字段**：`roots 健康（K5）：` 段，每行 `<徽标>  <路径>  — <detail>`
  - [ ] Launch at Login 用户意图 + 系统状态
  - [ ] last rebuild 时间 / 结果 / 摘要

## 10. K5 Root Health / FDA Recheck

按 `docs/manual_test.md` §33w 至少跑：

- [ ] 添加一个普通 root → 徽标 `✅ 就绪`
- [ ] 删除底层目录 → 点 "重新检查权限" → 徽标变 `🔌 路径不存在`
- [ ] 鼠标悬停该行 → tooltip 显示 detail 文案
- [ ] 点 **"打开完全磁盘访问设置"** → 系统设置跳到 完全磁盘访问 面板
- [ ] 关掉系统设置 → 回 SwiftSeek → 点 **"重新检查权限"** 不报错

> 完整 4 状态矩阵（ready / offline / volumeOffline / unavailable / paused）见 §33w；release gate 至少跑 ready / offline / FDA-jump 三项即可，volumeOffline / unavailable 视手边硬件条件做能做的部分。

## 11. Launch at Login 视察（不强制）

- [ ] 设置 → 常规 → "随 macOS 登录自动启动 SwiftSeek" 复选框勾选 / 取消正常
- [ ] 点击立即生效，不弹错（如弹错记入 release notes 已知边界）
- [ ] 诊断块的 `Launch at Login 用户意图` 与勾选状态一致

## 12. App Icon 验证

- [ ] `dist/SwiftSeek.app` 在 Finder 里显示自定义 App Icon（不是默认 Swift / 通用图标）
- [ ] **不**期望 Dock 中显示 App Icon（L1 默认隐藏 Dock）
- [ ] 关于面板里图标显示正常
- [ ] 菜单栏 `NSStatusItem` 显示放大镜模板图标（不是 App Icon — status bar 走 SF Symbol `magnifyingglass`，索引中切换为 `magnifyingglass.circle`）

## 13. 安装 / 升级 / 回滚 Dry-Run

按 `docs/install.md` + `docs/manual_test.md` §33v 至少做：

- [ ] `cp -R dist/SwiftSeek.app /Applications/` 成功
- [ ] `/Applications/SwiftSeek.app` 双击启动；启动日志三连里 `bundle=/Applications/...`
- [ ] 模拟一次升级：改一行源码 → 重打包 → 替换 `/Applications/SwiftSeek.app` → 启动 → commit hash 已变
- [ ] 回滚步骤可读：`docs/install.md` 的 schema forward-only 表与当前 schema v7 一致
- [ ] FDA recheck 路径在 `docs/install.md` "权限 / Full Disk Access / Root 覆盖（K5）" 里写清

## 14. Release Notes（K6）

- [ ] 复制 `docs/release_notes_template.md` 作为本次发布说明
- [ ] 模板中"已知边界"段未被删去（ad-hoc / 无 Developer ID / 无 notarization / 无 DMG / 无 auto updater / FDA / 外接盘 / 网络盘）
- [ ] 填入本次发布的 commit / build date / 修复列表 / 已知问题
- [ ] 不在 release notes 里夸大签名 / 公证 / DMG / 升级机制状态

## 15. 文档一致性收口

- [ ] `README.md` "当前限制" 段反映 K6 状态
- [ ] `docs/known_issues.md` §1-§9 与代码一致（K5 已落地、K6 release QA 已落地）
- [ ] `docs/install.md` 仍是单一安装入口，没有 K6 期间的过期内容
- [ ] `docs/manual_test.md` §33s-§33w + 本 checklist 联通无矛盾
- [ ] `docs/architecture.md` 末尾的 K1-K6 productization 段与 stage_status.md 一致

## 失败处置

任何一项失败：
1. **不发布**
2. 在本 checklist 上标注 ❌ + 现象
3. 修代码 / 文档 → 从第 1 步重跑（不要跳过任何一步以为只验证局部）
4. release notes 不要发，等下一轮全绿
