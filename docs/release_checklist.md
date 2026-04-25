# SwiftSeek Release Checklist（K6 + L1 单页）

每次发布本地 ad-hoc bundle 前**必须**从干净 workspace 走完整张表。任何一项失败都不算 release-ready。

**当前 release gate** = K6 收口 + L1 menubar-agent 形态默认。未签名 / 未公证 / 无 DMG / 无 auto updater 是当前轨道明确边界，不要在这条路径里夸大交付。L1 起 SwiftSeek 默认 **不显示 Dock 图标**；菜单栏状态项是主入口。

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
- [ ] 当前基准 N = **209**（K5 落地后），本轮总数不应少于 209

## 3. 一条命令打包 .app

```bash
HOME=/tmp/swiftseek-home \
CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
./scripts/package-app.sh --sandbox
```

- [ ] 命令成功，输出 `[package-app.sh] === done ===`
- [ ] `dist/SwiftSeek.app` 存在

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
